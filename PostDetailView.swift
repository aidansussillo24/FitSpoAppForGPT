//
//  PostDetailView.swift
//  FitSpo
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import CoreLocation
import UIKit

// ─────────────────────────────────────────────────────────────
struct PostDetailView: View {

    // ── injected
    let post: Post
    @Environment(\.dismiss) private var dismiss

    // ── author
    @State private var authorName      = ""
    @State private var authorAvatarURL = ""
    @State private var isLoadingAuthor = true

    // ── geo
    @State private var locationName = ""

    // ── like / comments
    @State private var isLiked: Bool
    @State private var likesCount: Int
    @State private var showHeart = false
    @State private var commentCount = 0
    @State private var showComments = false

    // ── share
    @State private var showShareSheet = false
    @State private var shareChat: Chat?
    @State private var navigateToChat = false

    // ── delete / report
    @State private var isDeleting = false
    @State private var showDeleteConfirm = false
    @State private var showReportSheet = false

    // ── outfit pins
    @State private var outfitItems : [OutfitItem]
    @State private var outfitTags  : [OutfitTag]
    @State private var showPins    = false          // ⇠ default OFF
    @State private var expandedTag : String? = nil
    @State private var showOutfitSheet = false

    // ── misc
    @State private var postListener: ListenerRegistration?
    @State private var imgRatio: CGFloat? = nil
    @State private var faceTags: [UserTag] = []

    init(post: Post) {
        self.post = post
        _isLiked     = State(initialValue: post.isLiked)
        _likesCount  = State(initialValue: post.likes)
        _outfitItems = State(initialValue: post.outfitItems ?? [])
        _outfitTags  = State(initialValue: post.outfitTags  ?? [])
    }

    // =========================================================
    // MARK: body
    // =========================================================
    var body: some View {
        ZStack(alignment: .bottom) {

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    postImage
                    actionRow
                    captionRow
                    timestampRow
                    Spacer(minLength: 32)
                }
                .padding(.top)
            }

            if showComments {
                CommentsOverlay(
                    post: post,
                    isPresented: $showComments,
                    onCommentCountChange: { commentCount = $0 }
                )
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeInOut, value: showComments)
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            toolbarDeleteButton
            toolbarMoreButton
        }
        .alert("Delete Post?", isPresented: $showDeleteConfirm,
               actions: deleteAlertButtons)
        .overlay { if isDeleting { deletingOverlay } }
        .sheet(isPresented: $showShareSheet)  { shareSheet }
        .sheet(isPresented: $showOutfitSheet) {
            OutfitItemSheet(items: outfitItems,
                            isPresented: $showOutfitSheet)
        }
        .sheet(isPresented: $showReportSheet) {
            ReportSheetView(postId: post.id,
                            isPresented: $showReportSheet)
        }
        .background { chatNavigationLink }
        .onAppear   { attachListenersAndFetch() }
        .onDisappear{ postListener?.remove() }
    }

    // MARK: ----------------------------------------------------
    // MARK: header
    // MARK: ----------------------------------------------------
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            NavigationLink(destination: ProfileView(userId: post.userId)) {
                avatarView
            }
            VStack(alignment: .leading, spacing: 4) {
                NavigationLink(destination: ProfileView(userId: post.userId)) {
                    Text(isLoadingAuthor ? "Loading…" : authorName)
                        .font(.headline)
                }
                if !locationName.isEmpty {
                    Text(locationName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    // MARK: ----------------------------------------------------
    // MARK: main image w/ overlays
    // MARK: ----------------------------------------------------
    private var postImage: some View {
        GeometryReader { geo in
            if let url = URL(string: post.imageURL) {
                ZoomableAsyncImage(url: url, aspectRatio: $imgRatio)
                    .frame(width: geo.size.width,
                           height: (imgRatio ?? 1) * geo.size.width)
                    .clipped()
                    .highPriorityGesture(
                        TapGesture(count: 2).onEnded { handleDoubleTapLike() }
                    )
                    .overlay { faceTagOverlay(in: geo) }
                    .overlay { if showPins { outfitPinsOverlay(in: geo) } }
                    .overlay(HeartBurstView(trigger: $showHeart))
                    // shopping‑bag toggle (bottom‑left)
                    .overlay(alignment: .bottomLeading) {
                        Button {
                            if outfitItems.isEmpty { showOutfitSheet = true }
                            else { showPins.toggle() }
                        } label: {
                            Image(systemName: showPins ? "bag.fill" : "bag")
                                .font(.system(size: 17, weight: .semibold))
                                .padding(12)
                                .background(.ultraThickMaterial, in: Circle())
                        }
                        .padding(16)
                    }
            } else {
                Color.gray.opacity(0.2)
            }
        }
        .frame(height: UIScreen.main.bounds.width * (imgRatio ?? 1))
    }

    // face tags ------------------------------------------------
    private func faceTagOverlay(in geo: GeometryProxy) -> some View {
        ForEach(faceTags) { tag in
            NavigationLink(destination: ProfileView(userId: tag.id)) {
                Text(tag.displayName)
                    .font(.caption2.weight(.semibold))
                    .padding(6)
                    .background(.thinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .position(
                x: tag.xNorm * geo.size.width,
                y: tag.yNorm * geo.size.width * (imgRatio ?? 1)
            )
        }
    }

    // outfit pins ---------------------------------------------
    private func outfitPinsOverlay(in geo: GeometryProxy) -> some View {
        ForEach(outfitTags) { t in
            if let item = outfitItems.first(where: { $0.id == t.itemId }) {

                let isExpanded = expandedTag == t.id

                Group {
                    if isExpanded {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.label).bold()
                            if !item.brand.isEmpty {
                                Text(item.brand)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if !item.shopURL.isEmpty {
                                Button("Buy") {
                                    if let url = URL(string: item.shopURL) {
                                        UIApplication.shared.open(url)
                                    }
                                }
                                .font(.caption.weight(.semibold))
                            }
                        }
                        .padding(8)
                        .background(.ultraThickMaterial,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .onTapGesture { expandedTag = nil }

                    } else {
                        Text(item.label)
                            .font(.caption2.weight(.semibold))
                            .padding(6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .onTapGesture { expandedTag = t.id }
                    }
                }
                .animation(.spring(), value: expandedTag)
                .position(
                    x: t.xNorm * geo.size.width,
                    y: t.yNorm * geo.size.width
                )
            }
        }
    }

    // MARK: ----------------------------------------------------
    // MARK: action row (eye‑button removed)
    // MARK: ----------------------------------------------------
    private var actionRow: some View {
        HStack(spacing: 24) {
            Button(action: toggleLike) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundColor(isLiked ? .red : .primary)
            }
            Text("\(likesCount)").font(.subheadline.bold())

            Button { showComments = true } label: {
                Image(systemName: "bubble.right").font(.title2)
            }
            Text("\(commentCount)").font(.subheadline.bold())

            Button { showShareSheet = true } label: {
                Image(systemName: "paperplane").font(.title2)
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    // MARK: caption & time rows --------------------------------
    private var captionRow: some View {
        HStack(alignment: .top, spacing: 4) {
            NavigationLink(destination: ProfileView(userId: post.userId)) {
                Text(isLoadingAuthor ? "Loading…" : authorName)
                    .fontWeight(.semibold)
            }
            Text(post.caption)
        }
        .padding(.horizontal)
    }

    private var timestampRow: some View {
        Text(post.timestamp, style: .time)
            .font(.caption)
            .foregroundColor(.gray)
            .padding(.horizontal)
    }

    // MARK: avatar helper --------------------------------------
    @ViewBuilder private var avatarView: some View {
        Group {
            if let url = URL(string: authorAvatarURL),
               !authorAvatarURL.isEmpty {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                    }
                }
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }

    // MARK: like helpers ---------------------------------------
    private func toggleLike() {
        isLiked.toggle()
        likesCount += isLiked ? 1 : -1
        NetworkService.shared.toggleLike(post: post) { _ in }
    }

    private func handleDoubleTapLike() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        showHeart = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showHeart = false }
        if !isLiked { toggleLike() }
    }

    // MARK: delete / report ------------------------------------
    private func performDelete() {
        isDeleting = true
        NetworkService.shared.deletePost(id: post.id) { res in
            DispatchQueue.main.async {
                isDeleting = false
                if case .success = res { dismiss() }
            }
        }
    }

    private var toolbarDeleteButton: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if post.userId == Auth.auth().currentUser?.uid {
                Button("Delete", role: .destructive) {
                    showDeleteConfirm = true
                }
            }
        }
    }

    private var toolbarMoreButton: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if post.userId != Auth.auth().currentUser?.uid {
                Menu {
                    Button(role: .destructive) {
                        showReportSheet = true
                    } label: {
                        Label("Report", systemImage: "flag")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
    }

    @ViewBuilder private func deleteAlertButtons() -> some View {
        Button("Delete", role: .destructive, action: performDelete)
        Button("Cancel",  role: .cancel) { }
    }

    private var deletingOverlay: some View {
        ProgressView("Deleting…")
            .padding()
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: share helpers --------------------------------------
    private var shareSheet: some View {
        ShareToUserView { uid in
            showShareSheet = false
            sharePost(to: uid)
        }
    }

    private func sharePost(to uid: String) {
        guard let me = Auth.auth().currentUser?.uid else { return }
        let pair = [me, uid].sorted()
        NetworkService.shared.createChat(participants: pair) { res in
            switch res {
            case .success(let chat):
                NetworkService.shared.sendPost(chatId: chat.id,
                                               postId: post.id) { _ in }
                DispatchQueue.main.async {
                    shareChat = chat
                    navigateToChat = true
                }
            case .failure(let err):
                print("Chat creation error:", err.localizedDescription)
            }
        }
    }

    private var chatNavigationLink: some View {
        Group {
            if let chat = shareChat {
                NavigationLink(destination: ChatDetailView(chat: chat),
                               isActive: $navigateToChat) { EmptyView() }
                    .hidden()
            }
        }
    }

    // MARK: Firestore helpers ----------------------------------
    private func attachListenersAndFetch() {
        attachPostListener()
        fetchAuthor()
        fetchLocationName()
        fetchCommentCount()
        fetchFaceTags()
    }

    private func attachPostListener() {
        guard postListener == nil else { return }
        postListener = Firestore.firestore()
            .collection("posts")
            .document(post.id)
            .addSnapshotListener { snap, _ in
                guard let d = snap?.data() else { return }

                likesCount   = d["likes"]         as? Int ?? likesCount
                commentCount = d["commentsCount"] as? Int ?? commentCount

                if let likedBy = d["likedBy"] as? [String],
                   let uid = Auth.auth().currentUser?.uid {
                    isLiked = likedBy.contains(uid)
                }

                outfitItems = NetworkService.parseOutfitItems(d["scanResults"])
                outfitTags  = NetworkService.parseOutfitTags (d["outfitTags"])
            }
    }

    private func fetchAuthor() {
        Firestore.firestore().collection("users")
            .document(post.userId)
            .getDocument { snap, _ in
                isLoadingAuthor = false
                let d = snap?.data() ?? [:]
                authorName      = d["displayName"] as? String ?? "Unknown"
                authorAvatarURL = d["avatarURL"]   as? String ?? ""
            }
    }

    private func fetchLocationName() {
        guard let lat = post.latitude, let lon = post.longitude else { return }
        let loc = CLLocation(latitude: lat, longitude: lon)
        CLGeocoder().reverseGeocodeLocation(loc) { places, _ in
            guard let p = places?.first else { return }
            locationName = [p.locality, p.administrativeArea, p.country]
                .compactMap { $0 }.first ?? ""
        }
    }

    private func fetchCommentCount() {
        NetworkService.shared.fetchComments(for: post.id) { res in
            if case .success(let list) = res { commentCount = list.count }
        }
    }

    private func fetchFaceTags() {
        NetworkService.shared.fetchTags(for: post.id) { res in
            if case .success(let list) = res { faceTags = list }
        }
    }
}

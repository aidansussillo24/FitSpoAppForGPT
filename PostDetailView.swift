//
//  PostDetailView.swift
//  FitSpo
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import CoreLocation

struct PostDetailView: View {
    let post: Post
    @Environment(\.dismiss) private var dismiss

    // ── Author info ─────────────────────────
    @State private var authorName      = ""
    @State private var authorAvatarURL = ""
    @State private var isLoadingAuthor = true

    // ── Location ───────────────────────────
    @State private var locationName    = ""

    // ── Like state ─────────────────────────
    @State private var isLiked    : Bool
    @State private var likesCount : Int
    @State private var showHeartBurst = false

    // ── Comment state ──────────────────────
    @State private var commentCount : Int = 0
    @State private var showComments = false

    // ── Misc. ──────────────────────────────
    @State private var isDeleting        = false
    @State private var showDeleteConfirm = false
    @State private var showShareSheet    = false
    @State private var shareChat: Chat?
    @State private var navigateToChat = false

    // live doc listener
    @State private var postListener: ListenerRegistration?

    init(post: Post) {
        self.post = post
        _isLiked    = State(initialValue: post.isLiked)
        _likesCount = State(initialValue: post.likes)
    }

    // MARK: — Body ----------------------------------------------------------
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

            // ── Comments overlay ──
            if showComments {
                CommentsOverlay(
                    post: post,
                    isPresented: $showComments,
                    onCommentCountChange: { commentCount = $0 }   // live update
                )
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeInOut, value: showComments)
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)

        // delete button for owner
        .toolbar {
            if post.userId == Auth.auth().currentUser?.uid {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Delete", role: .destructive) { showDeleteConfirm = true }
                }
            }
        }
        .alert("Delete Post?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive, action: performDelete)
            Button("Cancel", role: .cancel) {}
        }
        .overlay {
            if isDeleting {
                ProgressView("Deleting…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareToUserView { selectedUserId in
                showShareSheet = false
                sharePost(to: selectedUserId)
            }
        }
        .background(
            Group {
                if let chat = shareChat {
                    NavigationLink(
                        destination: ChatDetailView(chat: chat),
                        isActive: $navigateToChat
                    ) { EmptyView() }
                    .hidden()
                }
            }
        )
        .onAppear {
            attachPostListener()   // live likes & commentCount
            fetchAuthor()
            fetchLocationName()
            fetchCommentCount()    // ← ensures 💬 count is right on first load
        }
        .onDisappear { postListener?.remove() }
    }

    // MARK: — Subviews ------------------------------------------------------

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            NavigationLink(destination: ProfileView(userId: post.userId)) {
                avatarView
            }
            VStack(alignment: .leading, spacing: 4) {
                NavigationLink(destination: ProfileView(userId: post.userId)) {
                    Text(isLoadingAuthor ? "Loading…" : authorName).font(.headline)
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

    private var postImage: some View {
        ZStack {
            AsyncImage(url: URL(string: post.imageURL)) { phase in
                switch phase {
                case .empty:
                    ZStack { Color.gray.opacity(0.2); ProgressView() }
                case .success(let img):
                    img.resizable().scaledToFit()
                case .failure:
                    ZStack {
                        Color.gray.opacity(0.2)
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundColor(.white.opacity(0.7))
                    }
                @unknown default: EmptyView()
                }
            }
            .contentShape(Rectangle())
            .gesture(
                TapGesture(count: 2).onEnded { handleDoubleTapLike() }
            )

            Image(systemName: "heart.fill")
                .resizable()
                .foregroundColor(.white)
                .frame(width: 100, height: 100)
                .opacity(showHeartBurst ? 1 : 0)
                .scaleEffect(showHeartBurst ? 1 : 0.3)
                .animation(.easeOut(duration: 0.35), value: showHeartBurst)
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var actionRow: some View {
        HStack(spacing: 24) {
            Button(action: toggleLike) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundColor(isLiked ? .red : .primary)
            }
            Text("\(likesCount)")
                .font(.subheadline)
                .fontWeight(.semibold)

            Button { showComments = true } label: {
                Image(systemName: "bubble.right").font(.title2)
            }
            Text("\(commentCount)")
                .font(.subheadline)
                .fontWeight(.semibold)

            Button { showShareSheet = true } label: {
                Image(systemName: "paperplane").font(.title2)
            }

            Spacer()
        }
        .padding(.horizontal)
    }

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

    @ViewBuilder
    private var avatarView: some View {
        Group {
            if let url = URL(string: authorAvatarURL), !authorAvatarURL.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty: ProgressView()
                    case .success(let img): img.resizable().scaledToFill()
                    case .failure: Image(systemName: "person.crop.circle.fill").resizable()
                    @unknown default: EmptyView()
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

    // MARK: — Live Firestore listener --------------------------------------

    private func attachPostListener() {
        guard postListener == nil else { return }
        let doc = Firestore.firestore().collection("posts").document(post.id)
        postListener = doc.addSnapshotListener { snap, _ in
            guard let d = snap?.data() else { return }
            likesCount   = d["likes"] as? Int ?? likesCount
            commentCount = d["commentsCount"] as? Int ?? commentCount
            if let likedBy = d["likedBy"] as? [String],
               let uid = Auth.auth().currentUser?.uid {
                isLiked = likedBy.contains(uid)
            }
        }
    }

    // MARK: — Actions -------------------------------------------------------

    private func toggleLike() {
        isLiked.toggle()
        likesCount += isLiked ? 1 : -1
        NetworkService.shared.toggleLike(post: post) { _ in }
    }

    private func handleDoubleTapLike() {
        showHeartBurst = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showHeartBurst = false }
        if !isLiked { toggleLike() }
    }

    private func performDelete() {
        isDeleting = true
        NetworkService.shared.deletePost(id: post.id) { result in
            DispatchQueue.main.async {
                isDeleting = false
                if case .success = result { dismiss() }
            }
        }
    }

    // MARK: — Data fetch helpers -------------------------------------------

    private func fetchAuthor() {
        Firestore.firestore()
            .collection("users").document(post.userId)
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
            var parts = [String]()
            if let city   = p.locality             { parts.append(city) }
            if let region = p.administrativeArea   { parts.append(region) }
            if parts.isEmpty, let country = p.country { parts.append(country) }
            locationName = parts.joined(separator: ", ")
        }
    }

    private func fetchCommentCount() {
        NetworkService.shared.fetchComments(for: post.id) { res in
            if case .success(let list) = res { commentCount = list.count }
        }
    }

    // MARK: — Share helper --------------------------------------------------

    private func sharePost(to userId: String) {
        guard let me = Auth.auth().currentUser?.uid else { return }
        let pair = [me, userId].sorted()
        NetworkService.shared.createChat(participants: pair) { res in
            switch res {
            case .success(let chat):
                NetworkService.shared.sendPost(chatId: chat.id, postId: post.id) { _ in }
                DispatchQueue.main.async { shareChat = chat; navigateToChat = true }
            case .failure(let err):
                print("Chat creation error:", err)
            }
        }
    }
}

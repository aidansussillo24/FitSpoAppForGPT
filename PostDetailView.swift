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

    // ─── Author Info ────────────────────────────
    @State private var authorName      = ""
    @State private var authorAvatarURL = ""
    @State private var isLoadingAuthor = true

    // ─── Location Name ──────────────────────────
    @State private var locationName    = ""

    // ─── Delete State ───────────────────────────
    @State private var isDeleting        = false
    @State private var showDeleteConfirm = false

    // ─── Like State ─────────────────────────────
    @State private var isLiked    : Bool
    @State private var likesCount : Int

    // ─── Heart burst for double-tap like ────────
    @State private var showHeartBurst = false      // ★ NEW

    // ─── Comments ───────────────────────────────
    @State private var commentCount : Int = 0
    @State private var showComments = false

    // ─── Share / DM ─────────────────────────────
    @State private var showShareSheet = false
    @State private var shareChat: Chat?
    @State private var navigateToChat = false

    // MARK: – Init
    init(post: Post) {
        self.post = post
        _isLiked    = State(initialValue: post.isLiked)
        _likesCount = State(initialValue: post.likes)
    }

    // MARK: – Body
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    postImage                // ★ contains double-tap logic
                    actionRow
                    captionRow
                    timestampRow
                    Spacer(minLength: 32)
                }
                .padding(.top)
            }

            if showComments {
                CommentsOverlay(post: post, isPresented: $showComments)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeInOut, value: showComments)
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
            fetchAuthor()
            fetchLocationName()
            fetchCommentCount()
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: – Subviews ------------------------------------------------------

    private var header: some View { /* unchanged */ HStack(alignment: .top, spacing: 12) {
            NavigationLink(destination: ProfileView(userId: post.userId)) {
                avatarView
            }
            VStack(alignment: .leading, spacing: 4) {
                NavigationLink(destination: ProfileView(userId: post.userId)) {
                    Text(isLoadingAuthor ? "Loading…" : authorName).font(.headline)
                }
                if !locationName.isEmpty {
                    Text(locationName).font(.subheadline).foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    // ★ POST IMAGE with double-tap like + heart burst
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
            .contentShape(Rectangle())                      // full-tap area
            .gesture(
                TapGesture(count: 2).onEnded { handleDoubleTapLike() }
            )

            Image(systemName: "heart.fill")                 // burst overlay
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

    private var actionRow: some View { HStack(spacing: 24) {
            Button(action: toggleLike) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundColor(isLiked ? .red : .primary)
            }
            Text("\(likesCount)").font(.subheadline).fontWeight(.semibold)

            Button { showComments = true } label: {
                Image(systemName: "bubble.right").font(.title2)
            }
            Text("\(commentCount)").font(.subheadline).fontWeight(.semibold)

            Button { showShareSheet = true } label: {
                Image(systemName: "paperplane").font(.title2)
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    private var captionRow: some View { HStack(alignment: .top, spacing: 4) {
            NavigationLink(destination: ProfileView(userId: post.userId)) {
                Text(isLoadingAuthor ? "Loading…" : authorName).fontWeight(.semibold)
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
    private var avatarView: some View { Group {
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

    // MARK: – Actions -------------------------------------------------------

    private func toggleLike() {
        isLiked.toggle()
        likesCount += isLiked ? 1 : -1
        NetworkService.shared.toggleLike(post: post) { _ in }
    }

    private func handleDoubleTapLike() {
        // visual feedback
        showHeartBurst = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            showHeartBurst = false
        }
        // only toggle if not already liked
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

    private func fetchAuthor() {
        Firestore.firestore()
            .collection("users").document(post.userId)
            .getDocument { snap, err in
                isLoadingAuthor = false
                guard err == nil, let d = snap?.data() else { authorName = "Unknown"; return }
                authorName      = d["displayName"] as? String ?? "Unknown"
                authorAvatarURL = d["avatarURL"]   as? String ?? ""
            }
    }

    private func fetchLocationName() {
        guard let lat = post.latitude, let lon = post.longitude else { return }
        let loc = CLLocation(latitude: lat, longitude: lon)
        CLGeocoder().reverseGeocodeLocation(loc) { places, _ in
            guard let place = places?.first else { return }
            var parts = [String]()
            if let city = place.locality               { parts.append(city)    }
            if let region = place.administrativeArea   { parts.append(region)  }
            if parts.isEmpty, let country = place.country { parts.append(country) }
            locationName = parts.joined(separator: ", ")
        }
    }

    private func fetchCommentCount() {
        NetworkService.shared.fetchComments(for: post.id) { result in
            if case .success(let comments) = result { commentCount = comments.count }
        }
    }

    private func sharePost(to userId: String) {
        guard let me = Auth.auth().currentUser?.uid else { return }
        let pair = [me, userId].sorted()
        NetworkService.shared.createChat(participants: pair) { result in
            switch result {
            case .success(let chat):
                NetworkService.shared.sendPost(chatId: chat.id, postId: post.id) { _ in }
                DispatchQueue.main.async { shareChat = chat; navigateToChat = true }
            case .failure(let err): print("Chat creation error:", err)
            }
        }
    }
}

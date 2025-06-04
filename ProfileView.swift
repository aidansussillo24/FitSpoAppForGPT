import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

struct ProfileView: View {
    // The user ID whose profile is shown
    let userId: String

    // MARK: – State
    @State private var displayName: String = ""
    @State private var bio: String = ""
    @State private var avatarURL: String = ""
    @State private var email: String = ""
    @State private var posts: [Post] = []
    @State private var followersCount: Int = 0
    @State private var followingCount: Int = 0
    @State private var isFollowing: Bool = false
    @State private var isLoadingPosts: Bool = false
    @State private var errorMessage: String = ""
    @State private var showingEdit: Bool = false

    // Messaging state
    @State private var activeChat: Chat?
    @State private var showChat: Bool = false

    private let db = Firestore.firestore()

    // Two-column layout for posts
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    avatarSection

                    // Name, Email & Bio
                    VStack(spacing: 4) {
                        Text(displayName)
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(email)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if !bio.isEmpty {
                            Text(bio)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }

                    // Stats Row
                    HStack(spacing: 32) {
                        NavigationLink(destination: FollowersView(userId: userId)) {
                            statView(count: followersCount, label: "Followers")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())

                        NavigationLink(destination: FollowingView(userId: userId)) {
                            statView(count: followingCount, label: "Following")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())

                        statView(count: posts.count, label: "Posts")
                    }

                    // Action Buttons
                    if userId == Auth.auth().currentUser?.uid {
                        Button("Edit Profile") {
                            showingEdit = true
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top)
                    } else {
                        Button(isFollowing ? "Unfollow" : "Follow") {
                            toggleFollow()
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top)

                        Button {
                            openChat()
                        } label: {
                            Label("Message", systemImage: "bubble.left.and.bubble.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 8)
                    }

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Divider().padding(.vertical, 8)

                    // Posts Grid
                    if isLoadingPosts {
                        ProgressView()
                            .scaleEffect(1.5)
                            .padding()
                    } else {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(posts) { post in
                                NavigationLink(destination: PostDetailView(post: post)) {
                                    PostCell(post: post)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.bottom, 16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(displayName.isEmpty ? "Profile" : displayName)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sign Out") {
                        try? Auth.auth().signOut()
                    }
                }
            }
            .sheet(isPresented: $showingEdit) {
                EditProfileView()
            }
            .background(
                Group {
                    if let chat = activeChat {
                        NavigationLink(
                            destination: ChatDetailView(chat: chat),
                            isActive: $showChat
                        ) {
                            EmptyView()
                        }
                    }
                }
            )
            .onAppear(perform: loadEverything)
        }
    }

    // MARK: – Avatar section
    private var avatarSection: some View {
        Group {
            if let url = URL(string: avatarURL), !avatarURL.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let img):
                        img
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .resizable()
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: 120, height: 120)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .frame(width: 120, height: 120)
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 120, height: 120)
        .padding(.top, 16)
    }

    // MARK: – Stat subview
    private func statView(count: Int, label: String) -> some View {
        VStack {
            Text("\(count)")
                .font(.headline)
            Text(label)
                .font(.caption)
        }
    }
}

// MARK: – Private helpers
private extension ProfileView {
    func loadEverything() {
        loadProfile()
        loadUserPosts()
        loadFollowState()
        loadFollowCounts()
    }

    func loadProfile() {
        email = Auth.auth().currentUser?.email ?? ""
        db.collection("users").document(userId).getDocument { snap, err in
            guard err == nil, let data = snap?.data() else { return }
            displayName = data["displayName"] as? String ?? ""
            bio         = data["bio"]         as? String ?? ""
            avatarURL   = data["avatarURL"]   as? String ?? ""
        }
    }

    func loadUserPosts() {
        isLoadingPosts = true
        NetworkService.shared.fetchPosts { result in
            DispatchQueue.main.async {
                isLoadingPosts = false
                if case .success(let all) = result {
                    posts = all.filter { $0.userId == userId }
                }
            }
        }
    }

    func loadFollowState() {
        NetworkService.shared.isFollowing(userId: userId) { result in
            if case .success(let f) = result {
                isFollowing = f
            }
        }
    }

    func loadFollowCounts() {
        NetworkService.shared.fetchFollowCount(userId: userId, type: "followers") { r in
            if case .success(let c) = r { followersCount = c }
        }
        NetworkService.shared.fetchFollowCount(userId: userId, type: "following") { r in
            if case .success(let c) = r { followingCount = c }
        }
    }

    func toggleFollow() {
        let action = isFollowing
            ? NetworkService.shared.unfollow
            : NetworkService.shared.follow
        action(userId) { err in
            if err == nil {
                isFollowing.toggle()
                loadFollowCounts()
            }
        }
    }

    /// Fetch or create a chat then navigate
    func openChat() {
        guard let me = Auth.auth().currentUser?.uid else { return }
        NetworkService.shared.fetchChats { result in
            switch result {
            case .success(let chats):
                if let existing = chats.first(where: {
                    $0.participants.contains(me) && $0.participants.contains(userId)
                }) {
                    activeChat = existing
                    showChat = true
                } else {
                    let pair = [me, userId]
                    NetworkService.shared.createChat(participants: pair) { res in
                        if case .success(let newChat) = res {
                            activeChat = newChat
                            showChat = true
                        }
                    }
                }
            case .failure(let err):
                print("Failed to fetch chats:", err)
            }
        }
    }
}

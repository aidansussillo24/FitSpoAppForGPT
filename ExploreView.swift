//
//  ExploreView.swift
//  FitSpo
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct ExploreView: View {

    // MARK: – Grid
    private let spacing: CGFloat = 2
    private var columns: [GridItem] { [GridItem(.adaptive(minimum: 120), spacing: spacing)] }

    // MARK: – State
    @State private var allPosts:     [Post]                = []
    @State private var posts:        [Post]                = []
    @State private var listeners:    [ListenerRegistration] = []

    @State private var lastSnapshot: DocumentSnapshot?     = nil   // for pagination
    @State private var isLoading     = false

    @State private var searchText    = ""
    @State private var selectedChip  = "All"
    private let chips = ["All", "Men", "Women", "Street", "Formal"]

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 0) {

                    // ── Chips row ───────────────────────────────
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(chips, id: \.self) { chip in
                                Text(chip)
                                    .font(.subheadline)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .background(selectedChip == chip ? Color.blue : Color(.systemGray5))
                                    .foregroundColor(selectedChip == chip ? .white : .primary)
                                    .clipShape(Capsule())
                                    .onTapGesture { selectedChip = chip }
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                    .padding(.vertical, 6)

                    // ── Grid ───────────────────────────────────
                    LazyVGrid(columns: columns, spacing: spacing) {
                        ForEach(posts) { post in
                            NavigationLink {
                                PostDetailView(post: post)
                                    .onAppear {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    }
                            } label: {
                                Tile(post: post)
                            }
                            .onAppear {
                                // infinite scroll trigger
                                if post.id == posts.last?.id {
                                    Task { await loadMoreIfNeeded() }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, spacing / 2)
                    .padding(.bottom, spacing)
                }
            }
            .navigationTitle("Explore")
            .searchable(text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .automatic))
            .onChange(of: searchText)   { _ in applyFilter() }
            .onChange(of: selectedChip) { _ in applyFilter() }
            .refreshable { await reload(clear: true) }
            .task       { await reload(clear: true) }
            .onDisappear { listeners.forEach { $0.remove() }; listeners.removeAll() }
        }
    }

    // MARK: – Data load / paging
    @MainActor
    private func reload(clear: Bool) async {
        guard !isLoading else { return }
        isLoading = true

        if clear {
            listeners.forEach { $0.remove() }; listeners.removeAll()
            allPosts.removeAll()
            lastSnapshot = nil
        }

        NetworkService.shared.fetchTrendingPosts(startAfter: lastSnapshot) { res in
            DispatchQueue.main.async {
                switch res {
                case .success(let bundle):
                    let newPosts = bundle.posts
                    lastSnapshot = bundle.lastDoc
                    allPosts.append(contentsOf: newPosts)
                    attachLikeListeners(for: newPosts)
                    applyFilter()
                case .failure(let err):
                    print("Explore fetch error:", err)
                }
                isLoading = false
            }
        }
    }

    private func loadMoreIfNeeded() async {
        guard !isLoading, lastSnapshot != nil else { return }
        await reload(clear: false)
    }

    private func attachLikeListeners(for newPosts: [Post]) {
        for post in newPosts {
            guard let idx = allPosts.firstIndex(where: { $0.id == post.id }) else { continue }
            let l = Firestore.firestore().collection("posts").document(post.id)
                .addSnapshotListener { snap, _ in
                    guard let d = snap?.data() else { return }
                    allPosts[idx].likes = d["likes"] as? Int ?? allPosts[idx].likes
                    let me = Auth.auth().currentUser?.uid ?? ""
                    let likedBy = d["likedBy"] as? [String] ?? []
                    allPosts[idx].isLiked = likedBy.contains(me)
                    applyFilter()
                }
            listeners.append(l)
        }
    }

    // MARK: – Filtering
    private func applyFilter() {
        var filtered = selectedChip == "All"
            ? allPosts
            : allPosts.filter { $0.caption.localizedCaseInsensitiveContains(selectedChip) }

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            filtered = filtered.filter {
                $0.caption.lowercased().contains(q) ||
                $0.userId.lowercased().contains(q)
            }
        }
        posts = filtered
    }
}

// MARK: – Tile with shimmer & overlay
private struct Tile: View {
    let post: Post
    @State private var avatarURL: String?
    private static var avatarCache: [String:String] = [:]

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            ZStack {
                AsyncImage(url: URL(string: post.imageURL)) { ph in
                    switch ph {
                    case .empty:
                        Color.gray.opacity(0.12).shimmering()
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure:
                        Color.gray.opacity(0.12)
                    @unknown default:
                        Color.gray.opacity(0.12)
                    }
                }
                .frame(width: side, height: side)
                .clipped()

                // avatar TOP-RIGHT
                if let url = avatarURL, let u = URL(string: url) {
                    AsyncImage(url: u) { ph in
                        if let img = ph.image { img.resizable() } else { Color.gray.opacity(0.3) }
                    }
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 1))
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }

                // likes BOTTOM-RIGHT
                HStack(spacing: 3) {
                    Image(systemName: post.isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 11))
                        .foregroundColor(post.isLiked ? .red : .white)
                    Text("\(post.likes)")
                        .font(.caption2).bold()
                        .foregroundColor(.white)
                }
                .padding(5)
                .background(.black.opacity(0.35))
                .clipShape(Capsule())
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            .frame(width: side, height: side)
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(0.15), radius: 2, y: 1)
            .onAppear(perform: loadAvatar)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func loadAvatar() {
        if let cached = Tile.avatarCache[post.userId] { avatarURL = cached; return }

        Firestore.firestore().collection("users").document(post.userId)
            .getDocument { snap, _ in
                let url = snap?.data()?["avatarURL"] as? String
                avatarURL = url
                if let url { Tile.avatarCache[post.userId] = url }
            }
    }
}

// MARK: – Shimmer modifier
fileprivate struct Shimmer: ViewModifier {
    @State private var offset: CGFloat = -200
    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [.clear, .white.opacity(0.55), .clear]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .rotationEffect(.degrees(30))
                .offset(x: offset)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    offset = 350
                }
            }
    }
}
private extension View { func shimmering() -> some View { modifier(Shimmer()) } }

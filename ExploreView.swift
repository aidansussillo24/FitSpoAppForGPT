//
//  ExploreView.swift
//  FitSpo
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct ExploreView: View {

    // MARK: – Grid config
    private let spacing: CGFloat = 2
    private var columns: [GridItem] { [GridItem(.adaptive(minimum: 120), spacing: spacing)] }

    // MARK: – State
    @State private var allPosts: [Post] = []
    @State private var posts:    [Post] = []
    @State private var isLoading = false
    @State private var listeners: [ListenerRegistration] = []
    @State private var searchText = ""

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: spacing) {
                    ForEach(posts) { post in
                        NavigationLink {
                            PostDetailView(post: post)
                                .onAppear { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                        } label: {
                            Tile(post: post)
                        }
                    }
                }
                .padding(.horizontal, spacing / 2)   // edge-to-edge
                .padding(.top, spacing)
                .refreshable { await reload() }
            }
            .navigationTitle("Explore")
            .searchable(text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .automatic))
            .onChange(of: searchText, perform: applyFilter)
            .task { await reload() }
            .onDisappear { listeners.forEach { $0.remove() }; listeners.removeAll() }
        }
    }

    // MARK: – Networking
    @MainActor
    private func reload() async {
        guard !isLoading else { return }
        isLoading = true
        listeners.forEach { $0.remove() }; listeners.removeAll()

        NetworkService.shared.fetchTrendingPosts { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let list):
                    allPosts = list
                    attachLikeListeners()
                    applyFilter()
                case .failure(let err):
                    print("Explore fetch error:", err)
                }
                isLoading = false
            }
        }
    }

    private func attachLikeListeners() {
        for idx in allPosts.indices {
            let postId = allPosts[idx].id
            let l = Firestore.firestore()
                .collection("posts").document(postId)
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

    private func applyFilter(_ _: String = "") {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        posts = q.isEmpty
            ? allPosts
            : allPosts.filter {
                $0.caption.lowercased().contains(q) ||
                $0.userId.lowercased().contains(q)   // swap for authorName when stored
            }
    }
}

// MARK: – Single tile ------------------------------------------------------

private struct Tile: View {
    let post: Post
    @State private var avatarURL: String?

    // simple in-memory cache
    private static var cache: [String:String] = [:]

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            ZStack {
                // main image
                AsyncImage(url: URL(string: post.imageURL)) { phase in
                    switch phase {
                    case .empty:  Color.gray.opacity(0.1)
                    case .success(let img): img.resizable().scaledToFill()
                    case .failure: Color.gray.opacity(0.1)
                    @unknown default: Color.gray.opacity(0.1)
                    }
                }
                .frame(width: side, height: side)
                .clipped()

                // avatar — TOP-LEFT
                if let url = avatarURL, let imgURL = URL(string: url) {
                    AsyncImage(url: imgURL) { ph in
                        if let img = ph.image { img.resizable() } else { Color.gray.opacity(0.3) }
                    }
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 1))
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }

                // likes — BOTTOM-RIGHT
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
            .shadow(color: Color.black.opacity(0.12), radius: 2, y: 1)
            .onAppear(perform: loadAvatar)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func loadAvatar() {
        if let cached = Tile.cache[post.userId] { avatarURL = cached; return }

        Firestore.firestore()
            .collection("users").document(post.userId)
            .getDocument { snap, _ in
                let url = snap?.data()?["avatarURL"] as? String
                avatarURL = url
                if let url { Tile.cache[post.userId] = url }
            }
    }
}

//
//  ExploreView.swift
//  FitSpo
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct ExploreView: View {

    // ─── Grid layout ──────────────────────────────────────────────
    private let spacing: CGFloat = 2
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 120), spacing: spacing)]
    }

    // ─── Data & UI state ──────────────────────────────────────────
    @State private var allPosts:  [Post] = []
    @State private var posts:     [Post] = []
    @State private var listeners: [ListenerRegistration] = []
    @State private var lastSnapshot: DocumentSnapshot?
    @State private var isLoading = false

    @State private var searchText   = ""
    @State private var selectedChip = "All"
    private let chips = ["All", "Men", "Women", "Street", "Formal"]

    @State private var filter      = ExploreFilter()   // season + time only
    @State private var showFilters = false

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 0) {
                    chipRow
                    grid
                }
            }
            .navigationTitle("Explore")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Image(systemName: "slider.horizontal.3")
                        .onTapGesture { showFilters = true }
                }
            }
            .searchable(text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .automatic))
            .onChange(of: searchText)   { _ in applyFilter() }
            .onChange(of: selectedChip) { _ in applyFilter() }
            .onChange(of: filter)       { _ in applyFilter() }
            .sheet(isPresented: $showFilters) {
                ExploreFilterSheet(filter: $filter)
                    .presentationDetents([.fraction(0.45)])
            }
            .refreshable { await reload(clear: true) }
            .task { await coldStart() }
            .onDisappear { listeners.forEach { $0.remove() }; listeners.removeAll() }
        }
    }

    // MARK: – Cold-start helper (waits until online then loads)
    private func coldStart() async {
        while !NetworkService.isOnline { try? await Task.sleep(for: .seconds(1)) }
        await reload(clear: true)
    }

    // MARK: – Networking & paging
    @MainActor
    private func reload(clear: Bool) async {

        // Skip proactive fetch if offline; coldStart will retry
        guard NetworkService.isOnline else {
            await coldStart(); return
        }
        guard !isLoading else { return }
        isLoading = true

        if clear {
            listeners.forEach { $0.remove() }; listeners.removeAll()
            allPosts.removeAll(); posts.removeAll()
            lastSnapshot = nil
        }

        do {
            let bundle = try await NetworkService.shared
                .fetchTrendingPosts(startAfter: lastSnapshot)
            allPosts.append(contentsOf: bundle.posts)
            lastSnapshot = bundle.lastDoc
            attachLikeListeners(for: bundle.posts)
            applyFilter()
        } catch {
            print("Explore fetch error:", error.localizedDescription)
        }

        isLoading = false
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

    // MARK: – UI sub-views -------------------------------------------------
    private var chipRow: some View {
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
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(posts) { post in
                NavigationLink { PostDetailView(post: post) } label: { Tile(post: post) }
                    .onAppear {
                        if post.id == posts.last?.id { Task { await loadMoreIfNeeded() } }
                    }
            }
        }
        .padding(.horizontal, spacing / 2)
        .padding(.bottom, spacing)
    }

    // MARK: – Filtering (no temp section) ----------------------------------
    private func applyFilter() {
        var filtered = allPosts

        // season
        if let s = filter.season {
            filtered = filtered.filter {
                let m = Calendar.current.component(.month, from: $0.timestamp)
                switch s {
                case .spring: return (3...5).contains(m)
                case .summer: return (6...8).contains(m)
                case .fall:   return (9...11).contains(m)
                case .winter: return m == 12 || m <= 2
                }
            }
        }

        // time-band
        if let t = filter.timeBand {
            filtered = filtered.filter {
                let h = Calendar.current.component(.hour, from: $0.timestamp)
                switch t {
                case .morning:   return (5..<11).contains(h)
                case .afternoon: return (11..<17).contains(h)
                case .evening:   return (17..<21).contains(h)
                case .night:     return h >= 21 || h < 5
                }
            }
        }

        // caption chip
        if selectedChip != "All" {
            filtered = filtered.filter { $0.caption.localizedCaseInsensitiveContains(selectedChip) }
        }

        // free-text search
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

// MARK: – Tile + Shimmer (unchanged) --------------------------------------

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
                    case .empty:  Color.gray.opacity(0.12).shimmering()
                    case .success(let img): img.resizable().scaledToFill()
                    case .failure: Color.gray.opacity(0.12)
                    @unknown default: Color.gray.opacity(0.12)
                    }
                }
                .frame(width: side, height: side)
                .clipped()

                // avatar
                if let url = avatarURL, let u = URL(string: url) {
                    AsyncImage(url: u) { p in
                        if let img = p.image { img.resizable() } else { Color.gray.opacity(0.3) }
                    }
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 1))
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }

                // like badge
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

fileprivate struct Shimmer: ViewModifier {
    @State private var shift: CGFloat = -200
    func body(content: Content) -> some View {
        content.overlay(
            LinearGradient(
                gradient: Gradient(colors: [.clear, .white.opacity(0.55), .clear]),
                startPoint: .top, endPoint: .bottom)
            .rotationEffect(.degrees(30))
            .offset(x: shift)
        )
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                shift = 350
            }
        }
    }
}
private extension View { func shimmering() -> some View { modifier(Shimmer()) } }

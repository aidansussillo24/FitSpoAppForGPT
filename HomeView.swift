import SwiftUI

struct HomeView: View {
    @State private var posts: [Post] = []
    @State private var isLoading = false

    // Split into two columns by alternating indices
    private var leftColumn: [Post] {
        posts.enumerated()
             .filter { $0.offset.isMultiple(of: 2) }
             .map { $0.element }
    }
    private var rightColumn: [Post] {
        posts.enumerated()
             .filter { !$0.offset.isMultiple(of: 2) }
             .map { $0.element }
    }

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header

                    HStack(alignment: .top, spacing: 8) {
                        VStack(spacing: 8) {
                            ForEach(leftColumn) { post in
                                PostCardView(post: post) {
                                    toggleLike(post)
                                }
                            }
                        }
                        VStack(spacing: 8) {
                            ForEach(rightColumn) { post in
                                PostCardView(post: post) {
                                    toggleLike(post)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .refreshable {
                await fetchPostsAsync()
            }
            .task {
                await fetchPostsAsync()
            }
            .navigationBarHidden(true)
        }
    }

    // MARK: – Header with DM button
    private var header: some View {
        ZStack {
            Text("FitSpo")
                .font(.largeTitle)
                .fontWeight(.black)

            HStack {
                Spacer()
                // 🚀 Direct Messages button
                NavigationLink(destination: MessagesView()) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.title2)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: – Async fetch
    private func fetchPostsAsync() async {
        guard !isLoading else { return }
        isLoading = true
        do {
            let fetched = try await withCheckedThrowingContinuation { cont in
                NetworkService.shared.fetchPosts { result in
                    switch result {
                    case .success(let posts): cont.resume(returning: posts)
                    case .failure(let err):    cont.resume(throwing: err)
                    }
                }
            }
            await MainActor.run {
                posts = fetched
                isLoading = false
            }
        } catch {
            print("Fetch failed:", error)
            await MainActor.run { isLoading = false }
        }
    }

    // MARK: – Like handling
    private func toggleLike(_ post: Post) {
        NetworkService.shared.toggleLike(post: post) { result in
            DispatchQueue.main.async {
                if case .success(let updated) = result,
                   let idx = posts.firstIndex(where: { $0.id == updated.id }) {
                    posts[idx] = updated
                }
            }
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
    }
}

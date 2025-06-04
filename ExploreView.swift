// ExploreView.swift
import SwiftUI

struct ExploreView: View {
    @State private var allPosts: [Post]      = []   // everything we fetched
    @State private var isLoading: Bool       = false
    @State private var errorMessage: String? = nil
    @State private var searchText: String    = ""

    // two equally flexible columns
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    // filtered & sorted by likes
    private var filteredPosts: [Post] {
        let sorted = allPosts.sorted { $0.likes > $1.likes }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter {
            $0.caption.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationView {
            Group {
                // 1) Spinner
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                // 2) Error + retry
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Text(error)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Retry") { loadPosts(force: true) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // 3) Grid
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(filteredPosts) { post in
                                NavigationLink {
                                    PostDetailView(post: post)
                                } label: {
                                    PostCell(post: post)
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                    }
                    .refreshable { loadPosts(force: true) }
                }
            }
            .navigationTitle("Explore")
        }
        // native search bar
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search captions…"
        )
        // fetch once
        .task { loadPosts() }
    }

    // MARK: - Data loading
    private func loadPosts(force: Bool = false) {
        guard !isLoading, force || allPosts.isEmpty else { return }
        isLoading     = true
        errorMessage  = nil

        NetworkService.shared.fetchPosts { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let posts):
                    allPosts = posts
                case .failure(let err):
                    errorMessage = err.localizedDescription
                }
            }
        }
    }
}

struct ExploreView_Previews: PreviewProvider {
    static var previews: some View {
        ExploreView()
    }
}

//
//  SearchResultsView.swift
//  FitSpo
//

import SwiftUI

/// Stand-alone screen shown when user taps a username / hashtag result.
struct SearchResultsView: View {
    let query: String                 // either "@sofia" or "#beach"
    @State private var users: [UserLite] = []
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if query.first == "#" {
                    // TODO: hashtag deep-dive (Phase 2.3)
                    Text("Hashtag search coming next…")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(users) { u in
                        NavigationLink(destination: ProfileView(userId: u.id)) {
                            AccountRow(user: u)
                        }
                    }
                }
            }
            .overlay { if isLoading { ProgressView() } }
            .navigationTitle(query)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) {
                Button("Close") { dismiss() }
            }}
            .task { await runSearch() }
        }
    }

    @MainActor
    private func runSearch() async {
        guard query.first != "#" else { return }
        isLoading = true
        do { users = try await NetworkService.shared.searchUsers(prefix: query) }
        catch { print("User search error:", error.localizedDescription) }
        isLoading = false
    }
}

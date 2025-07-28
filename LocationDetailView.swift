import SwiftUI

struct LocationDetailView: View {
    let location: LocationCluster
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 16) {
                    // Location info
                    HStack(spacing: 12) {
                        // Location image
                        if let firstPost = location.posts.first {
                            RemoteImage(url: firstPost.imageURL, contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                        } else {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.red)
                        }
                        
                        // Location details
                        VStack(alignment: .leading, spacing: 4) {
                            Text(location.displayName)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.primary)
                            
                            Text(location.distance)
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            
                            Text("\(location.postCount) posts")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    // Action buttons
                    HStack(spacing: 16) {
                        Button(action: {}) {
                            HStack(spacing: 6) {
                                Image(systemName: "paperplane")
                                    .font(.system(size: 14))
                                Text("Share")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray6))
                            .cornerRadius(20)
                        }
                        
                        Button(action: {}) {
                            HStack(spacing: 6) {
                                Image(systemName: "bookmark")
                                    .font(.system(size: 14))
                                Text("Save")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray6))
                            .cornerRadius(20)
                        }
                        
                        Spacer()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                // Tabs
                HStack(spacing: 0) {
                    Button(action: { selectedTab = 0 }) {
                        VStack(spacing: 8) {
                            Text("Top")
                                .font(.system(size: 16, weight: selectedTab == 0 ? .semibold : .regular))
                                .foregroundColor(selectedTab == 0 ? .primary : .secondary)
                            
                            Rectangle()
                                .fill(selectedTab == 0 ? Color.primary : Color.clear)
                                .frame(height: 2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    Button(action: { selectedTab = 1 }) {
                        VStack(spacing: 8) {
                            Text("Recent")
                                .font(.system(size: 16, weight: selectedTab == 1 ? .semibold : .regular))
                                .foregroundColor(selectedTab == 1 ? .primary : .secondary)
                            
                            Rectangle()
                                .fill(selectedTab == 1 ? Color.primary : Color.clear)
                                .frame(height: 2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                // Posts grid
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(sortedPosts) { post in
                            PostCardView(post: post) {
                                // Handle like action if needed
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 100) // Extra padding for bottom sheet
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {}) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18))
                    }
                }
            }
        }
    }
    
    private var sortedPosts: [Post] {
        switch selectedTab {
        case 0:
            // Sort by likes (top posts)
            return location.posts.sorted { $0.likes > $1.likes }
        case 1:
            // Sort by timestamp (recent posts)
            return location.posts.sorted { $0.timestamp > $1.timestamp }
        default:
            return location.posts
        }
    }
}

struct LocationDetailView_Previews: PreviewProvider {
    static var previews: some View {
        LocationDetailView(location: LocationCluster(
            id: "1",
            latitude: 37.7749,
            longitude: -122.4194,
            posts: [],
            name: "San Francisco"
        ))
    }
} 
import SwiftUI
import FirebaseFirestore

struct PostCardView: View {
    let post: Post
    let onLike: () -> Void

    @State private var authorName      = ""
    @State private var authorAvatarURL = ""
    @State private var isLoadingAuthor = true

    var body: some View {
        VStack(spacing: 0) {
            // ─── Tap Image → Post Detail ─────────────────────
            NavigationLink(destination: PostDetailView(post: post)) {
                AsyncImage(url: URL(string: post.imageURL)) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            Color.gray.opacity(0.2)
                            ProgressView()
                        }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()       // ← preserves image’s natural height
                    case .failure:
                        ZStack {
                            Color.gray.opacity(0.2)
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())

            // ─── Footer: Tap → Profile (excluding heart) ─────
            HStack(spacing: 8) {
                NavigationLink(destination: ProfileView(userId: post.userId)) {
                    HStack(spacing: 8) {
                        if let url = URL(string: authorAvatarURL),
                           !authorAvatarURL.isEmpty
                        {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:     ProgressView()
                                case .success(let img):
                                    img
                                        .resizable()
                                        .scaledToFill()
                                case .failure:
                                    Image(systemName: "person.crop.circle.fill")
                                        .resizable()
                                @unknown default: EmptyView()
                                }
                            }
                            .frame(width: 24, height: 24)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .frame(width: 24, height: 24)
                                .foregroundColor(.gray)
                        }

                        Text(isLoadingAuthor ? "Loading…" : authorName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()

                Button(action: onLike) {
                    HStack(spacing: 4) {
                        Image(systemName: post.isLiked ? "heart.fill" : "heart")
                        Text("\(post.likes)")
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(8)
            .background(Color.white)
        }
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05),
                radius: 4, x: 0, y: 2)
        .onAppear(perform: fetchAuthor)
    }

    private func fetchAuthor() {
        let db = Firestore.firestore()
        db.collection("users")
          .document(post.userId)
          .getDocument { snap, err in
            isLoadingAuthor = false
            guard err == nil, let data = snap?.data() else {
                authorName = "Unknown"
                return
            }
            authorName      = data["displayName"] as? String ?? "Unknown"
            authorAvatarURL = data["avatarURL"]   as? String ?? ""
        }
    }
}

#if DEBUG
struct PostCardView_Previews: PreviewProvider {
    static var previews: some View {
        PostCardView(
            post: Post(
                id:        "1",
                userId:    "alice",
                imageURL:  "https://via.placeholder.com/400x600",
                caption:   "",
                timestamp: Date(),
                likes:     42,
                isLiked:   false,
                latitude:  nil,
                longitude: nil
            ),
            onLike: {}
        )
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif

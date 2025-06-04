//
//  CommentsOverlay.swift
//  FitSpo
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct CommentsOverlay: View {
    let post: Post
    @Binding var isPresented: Bool

    // ─────────────────────── Keyboard helper ───────────────────────
    @StateObject private var kb = KeyboardResponder()

    // ─────────────────────── Data & state ──────────────────────────
    @State private var comments: [Comment] = []
    @State private var newCommentText = ""
    @FocusState private var isInputActive: Bool
    @State private var dragOffset: CGFloat = 0        // swipe-to-dismiss offset

    // ─────────────────────── Body ──────────────────────────────────
    var body: some View {
        VStack(spacing: 0) {
            // Handle / title
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 40, height: 4)
                .padding(.top, 8)

            Text("Comments")
                .font(.headline)
                .padding(.bottom, 8)

            Divider()

            // Comment list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(comments) { CommentRow(comment: $0) }
                }
                .padding(.horizontal)
                .padding(.top, 6)
            }
            .onTapGesture { isInputActive = false }

            // Input bar
            HStack {
                TextField("Add a comment…", text: $newCommentText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isInputActive)

                Button(action: sendComment) {
                    Image(systemName: "paperplane.fill")
                        .font(.title3)
                }
                .disabled(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .background(.thinMaterial)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: UIScreen.main.bounds.height * 0.65, alignment: .top)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .offset(y: dragOffset)
        .padding(.bottom, kb.height)            // ← keeps bar above keyboard
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 { dragOffset = value.translation.height }
                }
                .onEnded { value in
                    if value.translation.height > 100 { isPresented = false }
                    dragOffset = 0
                }
        )
        .animation(.easeInOut, value: kb.height)
        .animation(.easeInOut, value: dragOffset)
        .onAppear(perform: loadComments)
        .ignoresSafeArea(edges: .bottom)
    }

    // ─────────────────────── Networking ────────────────────────────
    private func loadComments() {
        NetworkService.shared.fetchComments(for: post.id) { result in
            if case .success(let list) = result { comments = list }
        }
    }

    private func sendComment() {
        let text = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let user = Auth.auth().currentUser else { return }

        newCommentText = ""
        isInputActive  = false

        // Pull latest display name & avatar
        Firestore.firestore()
            .collection("users")
            .document(user.uid)
            .getDocument { snap, _ in
                let d      = snap?.data() ?? [:]
                let name   = (d["displayName"] as? String) ?? user.displayName ?? "User"
                let avatar = (d["avatarURL"]   as? String) ?? user.photoURL?.absoluteString

                let comment = Comment(
                    postId: post.id,
                    userId: user.uid,
                    username: name,
                    userPhotoURL: avatar,
                    text: text
                )

                NetworkService.shared.addComment(to: post.id, comment: comment) { _ in
                    loadComments()
                }
            }
    }
}

// ─────────────────────── Single comment row ───────────────────────

private struct CommentRow: View {
    let comment: Comment

    @State private var displayName: String = ""
    @State private var avatarURL  : String?

    private static var cache: [String : (String, String?)] = [:]

    var body: some View {
        NavigationLink(destination: ProfileView(userId: comment.userId)) {
            HStack(alignment: .top, spacing: 10) {
                AsyncImage(url: URL(string: avatarURL ?? comment.userPhotoURL ?? "")) { phase in
                    if let img = phase.image { img.resizable() }
                    else { Color.gray.opacity(0.3) }
                }
                .frame(width: 34, height: 34)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName.isEmpty ? comment.username : displayName)
                        .font(.subheadline).bold()
                        .foregroundColor(.primary)

                    Text(comment.text)
                        .foregroundColor(.primary)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .onAppear(perform: ensureProfileInfo)
    }

    private func ensureProfileInfo() {
        if let cached = CommentRow.cache[comment.userId] {
            displayName = cached.0
            avatarURL   = cached.1
            return
        }

        if comment.username != "User", comment.userPhotoURL != nil {
            CommentRow.cache[comment.userId] = (comment.username, comment.userPhotoURL)
            return
        }

        Firestore.firestore()
            .collection("users")
            .document(comment.userId)
            .getDocument { snap, _ in
                let d      = snap?.data() ?? [:]
                let name   = (d["displayName"] as? String) ?? comment.username
                let avatar = (d["avatarURL"]   as? String) ?? comment.userPhotoURL

                CommentRow.cache[comment.userId] = (name, avatar)
                displayName = name
                avatarURL   = avatar
            }
    }
}

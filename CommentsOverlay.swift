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
  var onCommentCountChange: (Int) -> Void    // ← NEW

  @State private var comments: [Comment] = []
  @State private var newText = ""
  @State private var dragOffset: CGFloat = 0
  @FocusState private var isInputActive: Bool
  @State private var listener: ListenerRegistration?

  @StateObject private var kb = KeyboardResponder()       // ← keyboard helper

  var body: some View {
    VStack(spacing: 0) {
      capsuleHeader
      commentList
      inputBar
    }
    .frame(maxWidth: .infinity)
    .frame(maxHeight: UIScreen.main.bounds.height * 0.65, alignment: .top)
    .background(.ultraThinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .offset(y: dragOffset)
    .padding(.bottom, kb.height)                           // ← keep above keyboard
    .gesture(
      DragGesture()
        .onChanged { val in if val.translation.height > 0 { dragOffset = val.translation.height } }
        .onEnded   { val in if val.translation.height > 100 { isPresented = false }; dragOffset = 0 }
    )
    .onAppear  { attachListener() }
    .onDisappear { listener?.remove() }
    .ignoresSafeArea(edges: .bottom)
    .animation(.easeInOut, value: dragOffset)
  }

  // MARK: – Sub-components -------------------------------------------------

  private var capsuleHeader: some View {
    VStack(spacing: 8) {
      Capsule()
        .fill(Color.secondary.opacity(0.4))
        .frame(width: 40, height: 4)
        .padding(.top, 8)
      Text("Comments").font(.headline)
      Divider()
    }
  }

  private var commentList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
          ForEach(comments) { CommentRow(comment: $0) }
        }
        .padding(.horizontal)
        .padding(.top, 6)
      }
      .onChange(of: comments.count) { _ in
        if let last = comments.last { proxy.scrollTo(last.id, anchor: .bottom) }
      }
    }
  }

  private var inputBar: some View {
    HStack {
      TextField("Add a comment…", text: $newText)
        .textFieldStyle(.roundedBorder)
        .focused($isInputActive)
      Button {
        sendComment()
      } label: {
        Image(systemName: "paperplane.fill").font(.title3)
      }
      .disabled(newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    .padding()
    .background(.thinMaterial)
  }

  // MARK: – Firestore  listener / send ------------------------------------

  private func attachListener() {
    guard listener == nil else { return }
    listener = Firestore.firestore()
      .collection("posts").document(post.id)
      .collection("comments")
      .order(by: "timestamp")
      .addSnapshotListener { snap, _ in
        comments = snap?.documents.compactMap { Comment(from: $0.data()) } ?? []
        onCommentCountChange(comments.count)               // ← notify parent
      }
  }

  private func sendComment() {
    let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, let user = Auth.auth().currentUser else { return }

    newText = ""; isInputActive = false

    let comment = Comment(
      postId: post.id,
      userId: user.uid,
      username: user.displayName ?? "User",
      userPhotoURL: user.photoURL?.absoluteString,
      text: text
    )
    NetworkService.shared.addComment(to: post.id, comment: comment) { _ in /* live listener updates */ }
  }
}

// MARK: – Row with profile fallback
private struct CommentRow: View {
  let comment: Comment
  @State private var name: String = ""
  @State private var avatar: String?

  private static var cache: [String:(String,String?)] = [:]

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      AsyncImage(url: URL(string: avatar ?? comment.userPhotoURL ?? "")) { phase in
        if let img = phase.image { img.resizable() } else { Color.gray.opacity(0.3) }
      }
      .frame(width: 34, height: 34)
      .clipShape(Circle())

      VStack(alignment: .leading, spacing: 4) {
        Text(name.isEmpty ? comment.username : name).font(.subheadline).bold()
        Text(comment.text)
      }
      Spacer(minLength: 0)
    }
    .onAppear(perform: ensureProfileInfo)
  }

  private func ensureProfileInfo() {
    if let cached = CommentRow.cache[comment.userId] {
      name = cached.0; avatar = cached.1; return
    }
    if comment.username != "User", comment.userPhotoURL != nil {
      CommentRow.cache[comment.userId] = (comment.username, comment.userPhotoURL)
      return
    }
    Firestore.firestore().collection("users").document(comment.userId)
      .getDocument { snap, _ in
        let d = snap?.data() ?? [:]
        let n = d["displayName"] as? String ?? "User"
        let a = d["avatarURL"]   as? String
        CommentRow.cache[comment.userId] = (n, a)
        name = n; avatar = a
      }
  }
}

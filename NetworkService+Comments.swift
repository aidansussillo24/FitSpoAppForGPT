import FirebaseFirestore

extension NetworkService {

    // A local Firestore handle that’s visible from this file
    private var firestore: Firestore { Firestore.firestore() }

    // MARK: - Add a comment
    func addComment(to postId: String,
                    comment: Comment,
                    completion: @escaping (Result<Void, Error>) -> Void) {

        firestore.collection("posts")
            .document(postId)
            .collection("comments")
            .document(comment.id)
            .setData(comment.dictionary) { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
    }

    // MARK: - Fetch comments
    func fetchComments(for postId: String,
                       completion: @escaping (Result<[Comment], Error>) -> Void) {

        firestore.collection("posts")
            .document(postId)
            .collection("comments")
            .order(by: "timestamp", descending: false)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error)); return
                }
                let comments: [Comment] = snapshot?.documents.compactMap {
                    Comment(from: $0.data())
                } ?? []
                completion(.success(comments))
            }
    }
}

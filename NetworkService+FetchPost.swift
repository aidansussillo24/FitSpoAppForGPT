import Foundation
import FirebaseAuth
import FirebaseFirestore

extension NetworkService {
    /// Load a single Post by its documentID and decode it manually.
    func fetchPost(
        id: String,
        completion: @escaping (Result<Post, Error>) -> Void
    ) {
        let db = Firestore.firestore()
        db.collection("posts").document(id).getDocument { snap, err in
            if let err = err {
                return completion(.failure(err))
            }
            guard let data = snap?.data(), let snap = snap else {
                let e = NSError(
                    domain: "NetworkService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey:"No post data"]
                )
                return completion(.failure(e))
            }

            // Manually extract your Post fields:
            guard
                let userId    = data["userId"]    as? String,
                let imageURL  = data["imageURL"]  as? String,
                let caption   = data["caption"]   as? String,
                let ts        = data["timestamp"] as? Timestamp,
                let likes     = data["likes"]     as? Int
            else {
                let e = NSError(
                    domain: "NetworkService",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey:"Malformed post fields"]
                )
                return completion(.failure(e))
            }

            // Determine if the current user has liked it (optional):
            let likedBy   = data["likedBy"] as? [String] ?? []
            let isLiked   = Auth.auth().currentUser.flatMap { likedBy.contains($0.uid) } ?? false

            // Optional location:
            let lat = data["latitude"]  as? Double
            let lon = data["longitude"] as? Double

            let post = Post(
                id:        snap.documentID,
                userId:    userId,
                imageURL:  imageURL,
                caption:   caption,
                timestamp: ts.dateValue(),
                likes:     likes,
                isLiked:   isLiked,
                latitude:  lat,
                longitude: lon
            )
            completion(.success(post))
        }
    }
}

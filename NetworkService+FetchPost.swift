//
//  NetworkService+FetchPost.swift
//  FitSpo
//

import FirebaseFirestore
import FirebaseAuth

extension NetworkService {

    /// Fetch a single post document and map to `Post`
    func fetchPost(id: String,
                   completion: @escaping (Result<Post,Error>) -> Void) {

        Firestore.firestore()
            .collection("posts")
            .document(id)
            .getDocument { snap, err in

                // ── Error handling ────────────────────────────────
                if let err { completion(.failure(err)); return }
                guard let d = snap?.data() else {
                    completion(.failure(
                        NSError(domain: "FetchPost",
                                code: 0,
                                userInfo: [NSLocalizedDescriptionKey: "Post not found"])
                    ))
                    return
                }

                // ── Required fields ───────────────────────────────
                guard
                    let userId   = d["userId"]    as? String,
                    let imageURL = d["imageURL"]  as? String,
                    let caption  = d["caption"]   as? String,
                    let likes    = d["likes"]     as? Int,
                    let ts       = d["timestamp"] as? Timestamp
                else {
                    completion(.failure(
                        NSError(domain: "FetchPost",
                                code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "Malformed post data"])
                    ))
                    return
                }

                // ── Build Post object ─────────────────────────────
                let me      = Auth.auth().currentUser?.uid
                let likedBy = d["likedBy"] as? [String] ?? []
                let isLiked = me.map { likedBy.contains($0) } ?? false

                let post = Post(
                    id:        snap!.documentID,
                    userId:    userId,
                    imageURL:  imageURL,
                    caption:   caption,
                    timestamp: ts.dateValue(),
                    likes:     likes,
                    isLiked:   isLiked,
                    latitude:  d["latitude"]  as? Double,
                    longitude: d["longitude"] as? Double,
                    temp:      d["temp"]      as? Double      // ✅ new mapping
                )

                completion(.success(post))
            }
    }
}

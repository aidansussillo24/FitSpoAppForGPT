//
//  NetworkService+Explore.swift
//  FitSpo
//

import FirebaseFirestore
import FirebaseAuth

extension NetworkService {

    /// Trending first; if empty, fall back to latest.
    func fetchTrendingPosts(completion: @escaping (Result<[Post],Error>) -> Void) {

        trendingQuery(limit: 50) { trending in
            if !trending.isEmpty {
                completion(.success(trending))
            } else {
                // fallback to newest 60 posts
                Firestore.firestore()
                    .collection("posts")
                    .order(by: "timestamp", descending: true)
                    .limit(to: 60)
                    .getDocuments { snap, err in
                        if let err = err { completion(.failure(err)); return }
                        completion(.success(self.mapDocs(snap)))
                    }
            }
        }
    }

    // MARK: – Helpers
    private func trendingQuery(limit: Int,
                               done: @escaping ([Post]) -> Void) {

        let past = Calendar.current.date(byAdding: .day, value: -30, to: Date())!

        Firestore.firestore()
            .collection("posts")
            .whereField("timestamp", isGreaterThan: past)
            .order(by: "likes", descending: true)
            .limit(to: limit)
            .getDocuments { snap, err in
                if let err = err { print("Trending query error:", err) }
                done(self.mapDocs(snap))
            }
    }

    /// Map snapshot → [Post] without `Decodable` ambiguity
    private func mapDocs(_ snap: QuerySnapshot?) -> [Post] {
        let me = Auth.auth().currentUser?.uid
        return snap?.documents.compactMap { doc in
            let d = doc.data()
            guard
                let userId   = d["userId"]    as? String,
                let imageURL = d["imageURL"]  as? String,
                let caption  = d["caption"]   as? String,
                let likes    = d["likes"]     as? Int,
                let ts       = d["timestamp"] as? Timestamp
            else { return nil }

            let likedBy = d["likedBy"] as? [String] ?? []
            return Post(
                id:        doc.documentID,
                userId:    userId,
                imageURL:  imageURL,
                caption:   caption,
                timestamp: ts.dateValue(),
                likes:     likes,
                isLiked:   me.map { likedBy.contains($0) } ?? false,
                latitude:  d["latitude"]  as? Double,
                longitude: d["longitude"] as? Double
            )
        } ?? []
    }
}

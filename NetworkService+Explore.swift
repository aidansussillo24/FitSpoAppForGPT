//
//  NetworkService+Explore.swift
//  FitSpo
//

import FirebaseFirestore
import FirebaseAuth

extension NetworkService {

    struct TrendingBundle {
        let posts:   [Post]
        let lastDoc: DocumentSnapshot?   // nil = no further paging
    }

    func fetchTrendingPosts(startAfter last: DocumentSnapshot? = nil,
                            limit: Int = 50,
                            completion: @escaping (Result<TrendingBundle,Error>) -> Void) {

        trendingQuery(startAfter: last, limit: limit) { firstResult in
            switch firstResult {
            case .success(let bundle) where !bundle.posts.isEmpty:
                completion(.success(bundle))

            default:    // empty or error → fallback to newest
                self.latestQuery(startAfter: last, limit: limit) { newestResult in
                    completion(newestResult)
                }
            }
        }
    }

    // ────────── private helpers ──────────

    private func trendingQuery(startAfter last: DocumentSnapshot?,
                               limit: Int,
                               completion: @escaping (Result<TrendingBundle,Error>) -> Void) {

        let past = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        var q: Query = Firestore.firestore()
            .collection("posts")
            .whereField("timestamp", isGreaterThan: past)
            .order(by: "likes", descending: true)
            .limit(to: limit)
        if let last { q = q.start(afterDocument: last) }

        q.getDocuments { snap, err in
            completion(self.mapResult(snapshot: snap, error: err))
        }
    }

    private func latestQuery(startAfter last: DocumentSnapshot?,
                             limit: Int,
                             completion: @escaping (Result<TrendingBundle,Error>) -> Void) {

        var q: Query = Firestore.firestore()
            .collection("posts")
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
        if let last { q = q.start(afterDocument: last) }

        q.getDocuments { snap, err in
            completion(self.mapResult(snapshot: snap, error: err))
        }
    }

    // Map snapshot → bundle, but store `lastDoc` only if it has a `likes` field
    private func mapResult(snapshot snap: QuerySnapshot?, error err: Error?)
        -> Result<TrendingBundle,Error> {

        if let err { return .failure(err) }
        guard let snap = snap else {
            return .success(TrendingBundle(posts: [], lastDoc: nil))
        }

        let me = Auth.auth().currentUser?.uid
        let posts: [Post] = snap.documents.compactMap { doc in
            let d = doc.data()
            guard
                let userId   = d["userId"]    as? String,
                let imageURL = d["imageURL"]  as? String,
                let caption  = d["caption"]   as? String,
                let likes    = d["likes"]     as? Int,      // ensure field exists
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
        }

        // safe cursor: only keep if likes field exists
        let tail = snap.documents.last
        let safeLast = (tail?.data()["likes"] != nil) ? tail : nil

        return .success(TrendingBundle(posts: posts, lastDoc: safeLast))
    }
}

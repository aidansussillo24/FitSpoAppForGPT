//
//  NetworkService+Explore.swift
//  FitSpo
//

import FirebaseFirestore
import FirebaseAuth
import Network          // for reachability helper

extension NetworkService {

    // Returned bundle for paging
    struct TrendingBundle {
        let posts:   [Post]
        let lastDoc: DocumentSnapshot?
    }

    // ────────────────────────────────────────────────────────────────
    // MARK: - NEW async/await flavour (used by pull-to-refresh)
    // ────────────────────────────────────────────────────────────────
    func fetchTrendingPosts(startAfter last: DocumentSnapshot?,
                            limit: Int = 50) async throws -> TrendingBundle {

        try await withCheckedThrowingContinuation { cont in
            fetchTrendingPosts(startAfter: last, limit: limit) { res in
                cont.resume(with: res)
            }
        }
    }

    // ────────────────────────────────────────────────────────────────
    // MARK: - Original callback version (kept for other callers)
    // ────────────────────────────────────────────────────────────────
    func fetchTrendingPosts(startAfter last: DocumentSnapshot? = nil,
                            limit: Int = 50,
                            completion: @escaping (Result<TrendingBundle,Error>) -> Void) {

        trendingQuery(startAfter: last, limit: limit) { first in
            switch first {
            case .success(let b) where !b.posts.isEmpty:
                completion(.success(b))               // trending has results
            default:
                // 0 docs or error → fallback to newest
                self.latestQuery(startAfter: last, limit: limit) { newest in
                    completion(newest)
                }
            }
        }
    }

    // ────────────────────────────────────────────────────────────────
    // MARK: - Simple reachability flag (used by cold start)
    // ────────────────────────────────────────────────────────────────
    static let isOnline: Bool = {
        let monitor = NWPathMonitor()
        var online  = true
        monitor.pathUpdateHandler = { online = $0.status == .satisfied }
        monitor.start(queue: DispatchQueue(label: "reachability"))
        return online
    }()
}

// MARK: - Private helpers
private extension NetworkService {

    func trendingQuery(startAfter last: DocumentSnapshot?,
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

    func latestQuery(startAfter last: DocumentSnapshot?,
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

    // snapshot → [Post]  (includes temp mapping) + safe lastDoc
    func mapResult(snapshot snap: QuerySnapshot?, error err: Error?)
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
                longitude: d["longitude"] as? Double,
                temp:      d["temp"]      as? Double
            )
        }

        // use last doc only if it contains the 'likes' field (avoids cursor error)
        let tail = snap.documents.last
        let safeLast = (tail?.data()["likes"] != nil) ? tail : nil

        return .success(TrendingBundle(posts: posts, lastDoc: safeLast))
    }
}

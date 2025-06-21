//
//  NetworkService.swift
//  FitSpo
//
//  Core networking layer + Firestore helpers.
//  Updated 2025‑06‑23:
//  • Added support for `[OutfitTag]` (pins) – both upload & decode.
//  • Added static helpers `parseOutfitItems(…)` & `parseOutfitTags(…)`.
//  • `uploadPost` signature now: image / caption / lat / lon / face‑tags / outfitItems / outfitTags / completion.
//  • No more reference to the unavailable SF‑Symbol “hanger.circle”.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Network
import UIKit

// ─────────────────────────────────────────────────────────────
final class NetworkService {

    // MARK: – Singleton + reachability
    static let shared = NetworkService()
    private init() { startPathMonitor() }

    private let monitor = NWPathMonitor()
    private let queue   = DispatchQueue(label: "FitSpo.NetMonitor")
    private var pathStatus: NWPath.Status = .satisfied
    static var isOnline: Bool { shared.pathStatus == .satisfied }

    private func startPathMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.pathStatus = path.status
        }
        monitor.start(queue: queue)
    }

    // MARK: – Firebase handles
    let db      = Firestore.firestore()
    private let storage = Storage.storage().reference()

    // ====================================================================
    // MARK:  USER PROFILE
    // ====================================================================
    func createUserProfile(userId: String,
                           data: [String:Any]) async throws {
        var d = data
        if let username = data["username"]    as? String { d["username_lc"]    = username.lowercased() }
        if let display  = data["displayName"] as? String { d["displayName_lc"] = display.lowercased() }
        try await db.collection("users").document(userId).setData(d)
    }

    // ====================================================================
    // MARK:  OUTFIT helpers
    // ====================================================================
    static func parseOutfitItems(_ raw: Any?) -> [OutfitItem] {
        guard let arr = raw as? [[String:Any]] else { return [] }
        return arr.compactMap { dict in
            guard
                let label = dict["label"]   as? String,
                let url   = dict["shopURL"] as? String
            else { return nil }
            let brand = dict["brand"] as? String ?? ""
            let id    = dict["id"]    as? String ?? UUID().uuidString
            return OutfitItem(id: id, label: label, brand: brand, shopURL: url)
        }
    }

    static func parseOutfitTags(_ raw: Any?) -> [OutfitTag] {
        guard let arr = raw as? [[String:Any]] else { return [] }
        return arr.compactMap { dict in
            guard
                let itemId = dict["itemId"] as? String,
                let x      = dict["xNorm"]  as? Double,
                let y      = dict["yNorm"]  as? Double
            else { return nil }
            let id = dict["id"] as? String ?? UUID().uuidString
            return OutfitTag(id: id, itemId: itemId, xNorm: x, yNorm: y)
        }
    }

    // ====================================================================
    // MARK:  UPLOAD POST  (manual items + pins)
    // ====================================================================
    func uploadPost(
        image: UIImage,
        caption: String,
        latitude: Double?,
        longitude: Double?,
        tags: [UserTag],             // face‑tags
        outfitItems: [OutfitItem],
        outfitTags: [OutfitTag],
        completion: @escaping (Result<Void,Error>) -> Void
    ) {
        guard let me  = Auth.auth().currentUser else { return completion(.failure(Self.authError())) }
        guard let jpg = image.jpegData(compressionQuality: 0.8) else { return completion(.failure(Self.imageError())) }

        // 1️⃣  Upload image to Storage
        let imgID = UUID().uuidString
        let ref   = storage.child("post_images/\(imgID).jpg")
        ref.putData(jpg, metadata: nil) { [weak self] _, err in
            if let err { completion(.failure(err)); return }

            ref.downloadURL { url, err in
                if let err { completion(.failure(err)); return }
                guard let self, let url else { return completion(.failure(Self.storageURLError())) }

                // 2️⃣  Assemble Firestore payload
                var data: [String:Any] = [
                    "userId"   : me.uid,
                    "imageURL" : url.absoluteString,
                    "caption"  : caption,
                    "timestamp": Timestamp(date: Date()),
                    "likes"    : 0,
                    "isLiked"  : false,
                    "hashtags" : Self.extractHashtags(from: caption),
                    "scanResults": outfitItems.map { [
                        "id"     : $0.id,
                        "label"  : $0.label,
                        "brand"  : $0.brand,
                        "shopURL": $0.shopURL
                    ]},
                    "outfitTags": outfitTags.map { [
                        "id"    : $0.id,
                        "itemId": $0.itemId,
                        "xNorm" : $0.xNorm,
                        "yNorm" : $0.yNorm
                    ]}
                ]
                if let latitude  { data["latitude"]  = latitude  }
                if let longitude { data["longitude"] = longitude }

                // 3️⃣  Write post document
                let doc = self.db.collection("posts").document()
                doc.setData(data) { err in
                    if let err { completion(.failure(err)); return }

                    // 4️⃣  Write face‑tag sub‑collection (if any)
                    if tags.isEmpty {
                        NotificationCenter.default.post(name: .didUploadPost, object: nil)
                        completion(.success(()))
                    } else {
                        let batch = self.db.batch()
                        tags.forEach { t in
                            batch.setData([
                                "uid"        : t.id,
                                "displayName": t.displayName,
                                "xNorm"      : t.xNorm,
                                "yNorm"      : t.yNorm
                            ], forDocument: doc.collection("tags").document(t.id))
                        }
                        batch.commit { err in
                            NotificationCenter.default.post(name: .didUploadPost, object: nil)
                            err == nil ? completion(.success(()))
                                       : completion(.failure(err!))
                        }
                    }
                }
            }
        }
    }

    // ====================================================================
    // MARK:  FETCH POSTS  (home feed)
    // ====================================================================
    func fetchPosts(completion: @escaping (Result<[Post],Error>) -> Void) {
        db.collection("posts")
            .order(by: "timestamp", descending: true)
            .getDocuments { snap, err in
                if let err { completion(.failure(err)); return }
                let list = snap?.documents.compactMap(Self.decodePost) ?? []
                completion(.success(list))
            }
    }

    // ====================================================================
    // MARK:  TAGS helper  (face‑tags)
    // ====================================================================
    func fetchTags(for postId: String,
                   completion: @escaping (Result<[UserTag],Error>) -> Void) {
        db.collection("posts").document(postId)
            .collection("tags")
            .getDocuments { snap, err in
                if let err { completion(.failure(err)); return }
                let tags: [UserTag] = snap?.documents.compactMap { d in
                    guard let x = d["xNorm"] as? Double,
                          let y = d["yNorm"] as? Double,
                          let n = d["displayName"] as? String
                    else { return nil }
                    return UserTag(id: d.documentID, xNorm: x, yNorm: y, displayName: n)
                } ?? []
                completion(.success(tags))
            }
    }

    // ====================================================================
    // MARK:  Likes  / Delete / Follow …  (UNMODIFIED BELOW)
    // ====================================================================

    func toggleLike(post: Post,
                    completion: @escaping (Result<Post,Error>) -> Void) {
        let ref      = db.collection("posts").document(post.id)
        let delta    = post.isLiked ? -1 : 1
        let newLikes = post.likes + delta
        let newLiked = !post.isLiked

        ref.updateData(["likes": newLikes, "isLiked": newLiked]) { err in
            if let err { completion(.failure(err)); return }
            var updated = post
            updated.likes   = newLikes
            updated.isLiked = newLiked
            completion(.success(updated))
        }
    }

    func deletePost(id: String,
                    completion: @escaping (Result<Void,Error>) -> Void) {
        let ref = db.collection("posts").document(id)
        ref.getDocument { snap, err in
            if let err { completion(.failure(err)); return }

            if let urlStr = snap?.data()?["imageURL"] as? String,
               let url    = URL(string: urlStr) {
                Storage.storage()
                    .reference(withPath: url.path.dropFirst().description)
                    .delete { _ in }
            }
            ref.delete { err in
                err == nil ? completion(.success(()))
                           : completion(.failure(err!))
            }
        }
    }

    // ====================================================================
    // MARK: FOLLOW helpers  (unchanged)
    // ====================================================================
    func follow(userId: String, completion: @escaping (Error?) -> Void) {
        guard let me = Auth.auth().currentUser?.uid else {
            return completion(Self.authError())
        }
        let b = db.batch()
        b.setData([:], forDocument: db.collection("users").document(userId)
                                 .collection("followers").document(me))
        b.setData([:], forDocument: db.collection("users").document(me)
                                 .collection("following").document(userId))
        b.commit(completion: completion)
    }

    func unfollow(userId: String, completion: @escaping (Error?) -> Void) {
        guard let me = Auth.auth().currentUser?.uid else {
            return completion(Self.authError())
        }
        let b = db.batch()
        b.deleteDocument(db.collection("users").document(userId)
                           .collection("followers").document(me))
        b.deleteDocument(db.collection("users").document(me)
                           .collection("following").document(userId))
        b.commit(completion: completion)
    }

    func isFollowing(userId: String,
                     completion: @escaping (Result<Bool,Error>) -> Void) {
        guard let me = Auth.auth().currentUser?.uid else {
            return completion(.failure(Self.authError()))
        }
        db.collection("users").document(userId)
            .collection("followers").document(me)
            .getDocument { snap, err in
                if let err { completion(.failure(err)); return }
                completion(.success(snap?.exists == true))
            }
    }

    func fetchFollowCount(userId: String,
                          type: String,
                          completion: @escaping (Result<Int,Error>) -> Void) {
        db.collection("users").document(userId)
            .collection(type)
            .getDocuments { snap, err in
                if let err { completion(.failure(err)); return }
                completion(.success(snap?.documents.count ?? 0))
            }
    }

    // ====================================================================
    // MARK: PRIVATE helpers
    // ====================================================================
    private static func extractHashtags(from caption: String) -> [String] {
            let pattern = "(?:\\s|^)#(\\w+)"
            guard let rx = try? NSRegularExpression(pattern: pattern) else { return [] }
            let nsRange  = NSRange(caption.startIndex..., in: caption)
            let matches  = rx.matches(in: caption, range: nsRange)
            return Array(Set(matches.compactMap {
                Range($0.range(at: 1), in: caption).map { caption[$0].lowercased() }
            }))
        }

        private static func authError() -> NSError {
            NSError(domain: "Auth", code: -1,
                    userInfo: [NSLocalizedDescriptionKey:"Not signed in"])
        }
        private static func imageError() -> NSError {
            NSError(domain: "Image", code: -1,
                    userInfo: [NSLocalizedDescriptionKey:"Image conversion failed"])
        }
        private static func storageURLError() -> NSError {
            NSError(domain: "Storage", code: -1,
                    userInfo: [NSLocalizedDescriptionKey:"No download URL"])
        }

        // ====================================================================
        // MARK:  doc → Post mapper
        // ====================================================================
        fileprivate static func decodePost(doc: QueryDocumentSnapshot) -> Post? {
            let d = doc.data()
            guard
                let uid     = d["userId"]    as? String,
                let imgURL  = d["imageURL"]  as? String,
                let caption = d["caption"]   as? String,
                let ts      = d["timestamp"] as? Timestamp,
                let likes   = d["likes"]     as? Int,
                let liked   = d["isLiked"]   as? Bool
            else { return nil }

            return Post(
                id:           doc.documentID,
                userId:       uid,
                imageURL:     imgURL,
                caption:      caption,
                timestamp:    ts.dateValue(),
                likes:        likes,
                isLiked:      liked,
                latitude:     d["latitude"]  as? Double,
                longitude:    d["longitude"] as? Double,
                temp:         d["temp"]      as? Double,
                outfitItems:  parseOutfitItems(d["scanResults"]),
                outfitTags:   parseOutfitTags (d["outfitTags"]),
                hashtags:     d["hashtags"]  as? [String] ?? []
            )
        }
    }
    //  End of NetworkService.swift

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import UIKit

/// A singleton to manage all Firebase calls.
final class NetworkService {
    static let shared = NetworkService()
    private init() {}

    private let db      = Firestore.firestore()
    private let storage = Storage.storage().reference()

    // MARK: - Create User Profile

    func createUserProfile(
        userId: String,
        data: [String: Any],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        db.collection("users").document(userId).setData(data) { error in
            if let error = error { completion(.failure(error)) }
            else                 { completion(.success(()))    }
        }
    }

    // MARK: - Upload Post (with optional coords)

    func uploadPost(
        image: UIImage,
        caption: String,
        latitude: Double?,
        longitude: Double?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let user = Auth.auth().currentUser else {
            let err = NSError(
                domain: "Auth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not signed in"]
            )
            return completion(.failure(err))
        }
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            let err = NSError(
                domain: "Image",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Image conversion failed"]
            )
            return completion(.failure(err))
        }

        let id  = UUID().uuidString
        let ref = storage.child("post_images/\(id).jpg")

        ref.putData(data, metadata: nil) { _, err in
            if let err = err {
                return completion(.failure(err))
            }

            ref.downloadURL { url, err in
                if let err = err {
                    return completion(.failure(err))
                }
                guard let url = url else {
                    let err = NSError(
                        domain: "Storage",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "No download URL"]
                    )
                    return completion(.failure(err))
                }

                let postData: [String: Any] = [
                    "userId":    user.uid,
                    "imageURL":  url.absoluteString,
                    "caption":   caption,
                    "timestamp": Timestamp(date: Date()),
                    "likes":     0,
                    "isLiked":   false,
                    "latitude":  latitude as Any,
                    "longitude": longitude as Any
                ]

                self.db.collection("posts").addDocument(data: postData) { err in
                    if let err = err {
                        completion(.failure(err))
                    } else {
                        completion(.success(()))
                    }
                }
            }
        }
    }

    // MARK: - Fetch Posts

    func fetchPosts(
        completion: @escaping (Result<[Post], Error>) -> Void
    ) {
        db.collection("posts")
          .order(by: "timestamp", descending: true)
          .getDocuments { snap, err in
            if let err = err {
                return completion(.failure(err))
            }
            let posts = snap?.documents.compactMap { doc -> Post? in
                let d = doc.data()
                guard
                    let uid       = d["userId"]   as? String,
                    let imageURL  = d["imageURL"] as? String,
                    let caption   = d["caption"]  as? String,
                    let ts        = d["timestamp"] as? Timestamp,
                    let likes     = d["likes"]    as? Int,
                    let isLiked   = d["isLiked"]  as? Bool
                else { return nil }

                let latitude  = d["latitude"]  as? Double
                let longitude = d["longitude"] as? Double

                return Post(
                    id:        doc.documentID,
                    userId:    uid,
                    imageURL:  imageURL,
                    caption:   caption,
                    timestamp: ts.dateValue(),
                    likes:     likes,
                    isLiked:   isLiked,
                    latitude:  latitude,
                    longitude: longitude
                )
            } ?? []
            completion(.success(posts))
        }
    }

    // MARK: - Toggle Like (Post)

    func toggleLike(
        post: Post,
        completion: @escaping (Result<Post, Error>) -> Void
    ) {
        let docRef   = db.collection("posts").document(post.id)
        let delta    = post.isLiked ? -1 : 1
        let newLikes = post.likes + delta
        let newLiked = !post.isLiked

        docRef.updateData([
            "likes":   newLikes,
            "isLiked": newLiked
        ]) { err in
            if let err = err {
                return completion(.failure(err))
            }
            var updated = post
            updated.likes   = newLikes
            updated.isLiked = newLiked
            completion(.success(updated))
        }
    }

    // MARK: - Delete Post

    /// Deletes both the Firestore document and its image in Storage.
    func deletePost(
        id: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let docRef = db.collection("posts").document(id)
        docRef.getDocument { snap, err in
            if let err = err { return completion(.failure(err)) }
            guard
                let data = snap?.data(),
                let urlString = data["imageURL"] as? String,
                let url = URL(string: urlString)
            else {
                // No image URL? Just delete the doc
                docRef.delete { err in
                    if let err = err {
                        completion(.failure(err))
                    } else {
                        completion(.success(()))
                    }
                }
                return
            }

            // Delete the file from Storage
            let path = url.pathComponents
                .dropFirst() // leading slash
                .joined(separator: "/")
            let fileRef = Storage.storage().reference(withPath: path)
            fileRef.delete { _ in
                // Ignore storage errors; now delete the Firestore doc
                docRef.delete { err in
                    if let err = err {
                        completion(.failure(err))
                    } else {
                        completion(.success(()))
                    }
                }
            }
        }
    }

    // MARK: - Follow / Unfollow

    func follow(userId: String, completion: @escaping (Error?) -> Void) {
        guard let me = Auth.auth().currentUser?.uid else {
            return completion(NSError(
                domain: "Auth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not signed in"]
            ))
        }
        let batch = db.batch()
        let followerRef = db
            .collection("users")
            .document(userId)
            .collection("followers")
            .document(me)
        let followingRef = db
            .collection("users")
            .document(me)
            .collection("following")
            .document(userId)
        batch.setData([:], forDocument: followerRef)
        batch.setData([:], forDocument: followingRef)
        batch.commit(completion: completion)
    }

    func unfollow(userId: String, completion: @escaping (Error?) -> Void) {
        guard let me = Auth.auth().currentUser?.uid else {
            return completion(NSError(
                domain: "Auth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not signed in"]
            ))
        }
        let batch = db.batch()
        let followerRef = db
            .collection("users")
            .document(userId)
            .collection("followers")
            .document(me)
        let followingRef = db
            .collection("users")
            .document(me)
            .collection("following")
            .document(userId)
        batch.deleteDocument(followerRef)
        batch.deleteDocument(followingRef)
        batch.commit(completion: completion)
    }

    func isFollowing(
        userId: String,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let me = Auth.auth().currentUser?.uid else {
            return completion(.failure(NSError(
                domain: "Auth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not signed in"]
            )))
        }
        db
          .collection("users")
          .document(userId)
          .collection("followers")
          .document(me)
          .getDocument { snap, err in
            if let err = err {
                completion(.failure(err)); return
            }
            completion(.success(snap?.exists == true))
        }
    }

    func fetchFollowCount(
        userId: String,
        type: String, // “followers” or “following”
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        db
          .collection("users")
          .document(userId)
          .collection(type)
          .getDocuments { snap, err in
            if let err = err {
                completion(.failure(err)); return
            }
            completion(.success(snap?.documents.count ?? 0))
        }
    }
}

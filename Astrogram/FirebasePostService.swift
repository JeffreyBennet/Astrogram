import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import UIKit

final class FirebasePostService {
    static let shared = FirebasePostService()

    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private let postsCollection = "posts"

    private init() {}

    // MARK: - Upload Image

    func uploadImage(_ image: UIImage, completion: @escaping (Result<(url: String, path: String), Error>) -> Void) {
        guard let data = image.jpegData(compressionQuality: 0.7) else {
            print("[FirebasePostService] ERROR: Failed to convert image to JPEG data")
            completion(.failure(ServiceError.imageConversionFailed))
            return
        }

        let filename = "\(UUID().uuidString).jpg"
        let path = "posts/\(filename)"
        let ref = storage.reference().child(path)
        let dataSize = Double(data.count) / 1024.0
        print("[FirebasePostService] Uploading image: \(path) (\(String(format: "%.1f", dataSize)) KB)")
        print("[FirebasePostService] Storage bucket: \(storage.reference().bucket)")

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        ref.putData(data, metadata: metadata) { _, error in
            if let error = error {
                print("[FirebasePostService] ERROR uploading image: \(error.localizedDescription)")
                print("[FirebasePostService] Full error: \(error)")
                completion(.failure(error))
                return
            }
            print("[FirebasePostService] Image uploaded successfully, fetching download URL...")
            ref.downloadURL { url, error in
                if let error = error {
                    print("[FirebasePostService] ERROR getting download URL: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                guard let url = url else {
                    print("[FirebasePostService] ERROR: Download URL was nil")
                    completion(.failure(ServiceError.urlRetrievalFailed))
                    return
                }
                print("[FirebasePostService] Download URL obtained: \(url.absoluteString.prefix(80))...")
                completion(.success((url: url.absoluteString, path: path)))
            }
        }
    }

    // MARK: - Create Post

    func createPost(_ post: AstroPost, completion: @escaping (Result<String, Error>) -> Void) {
        print("[FirebasePostService] Creating Firestore document in '\(postsCollection)' for user: \(post.userId)")
        var ref: DocumentReference?
        ref = db.collection(postsCollection).addDocument(data: post.dictionary) { error in
            if let error = error {
                print("[FirebasePostService] ERROR creating post: \(error.localizedDescription)")
                print("[FirebasePostService] Full error: \(error)")
                completion(.failure(error))
            } else {
                print("[FirebasePostService] Post created successfully with ID: \(ref?.documentID ?? "unknown")")
                completion(.success(ref?.documentID ?? ""))
            }
        }
    }

    // MARK: - Fetch Posts

    func fetchPosts(filter: FeedFilter, completion: @escaping (Result<[AstroPost], Error>) -> Void) {
        var query: Query = db.collection(postsCollection)

        // Filter: camera type (server-side only if not combined with userId filter)
        if !filter.myPostsOnly, let camera = filter.camera, !camera.isEmpty {
            query = query.whereField("camera", isEqualTo: camera)
        }

        // Sort
        switch filter.sortBy {
        case .newest:
            query = query.order(by: "timestamp", descending: true)
        case .oldest:
            query = query.order(by: "timestamp", descending: false)
        }

        // Limit
        query = query.limit(to: filter.limit)

        query.getDocuments { snapshot, error in
            if let error = error {
                print("[FirebasePostService] ERROR fetching posts: \(error.localizedDescription)")
                print("[FirebasePostService] Full error: \(error)")
                completion(.failure(error))
                return
            }
            guard let documents = snapshot?.documents else {
                completion(.success([]))
                return
            }
            var posts = documents.compactMap { AstroPost.from(document: $0) }

            // Client-side: my posts only
            if filter.myPostsOnly, let uid = Auth.auth().currentUser?.uid {
                posts = posts.filter { $0.userId == uid }
            }

            // Client-side: exclude user
            if let excludeUid = filter.excludeUserId, !excludeUid.isEmpty {
                posts = posts.filter { $0.userId != excludeUid }
            }

            // Client-side: camera filter
            if let camera = filter.camera, !camera.isEmpty {
                posts = posts.filter { $0.camera == camera }
            }

            // Client-side date filtering
            if let startDate = filter.startDate {
                posts = posts.filter { $0.timestamp >= startDate }
            }
            if let endDate = filter.endDate {
                let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: endDate) ?? endDate
                posts = posts.filter { $0.timestamp < endOfDay }
            }

            // Client-side title search
            if let search = filter.searchText, !search.isEmpty {
                let lower = search.lowercased()
                posts = posts.filter {
                    $0.title.lowercased().contains(lower) ||
                    $0.description.lowercased().contains(lower) ||
                    $0.locationName.lowercased().contains(lower)
                }
            }

            completion(.success(posts))
        }
    }

    func fetchRecentPosts(limit: Int, completion: @escaping (Result<[AstroPost], Error>) -> Void) {
        var filter = FeedFilter()
        filter.limit = limit
        filter.sortBy = .newest
        fetchPosts(filter: filter, completion: completion)
    }

    // MARK: - Update Post

    func updatePost(id: String, fields: [String: Any], completion: @escaping (Result<Void, Error>) -> Void) {
        db.collection(postsCollection).document(id).updateData(fields) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    // MARK: - Delete Post

    func deletePost(_ post: AstroPost, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let id = post.id else {
            completion(.failure(ServiceError.missingDocumentId))
            return
        }

        // Delete image from storage first
        let storageRef = storage.reference().child(post.imagePath)
        storageRef.delete { _ in
            // Continue even if storage delete fails (image may already be gone)
            self.db.collection(self.postsCollection).document(id).delete { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    // MARK: - Stars

    func toggleStar(postId: String, userId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        let starRef = db.collection(postsCollection).document(postId).collection("stars").document(userId)
        let postRef = db.collection(postsCollection).document(postId)

        starRef.getDocument { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            if snapshot?.exists == true {
                // Unstar
                starRef.delete { error in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }
                    postRef.updateData(["starCount": FieldValue.increment(Int64(-1))]) { _ in
                        completion(.success(false))
                    }
                }
            } else {
                // Star
                starRef.setData(["timestamp": FieldValue.serverTimestamp()]) { error in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }
                    postRef.updateData(["starCount": FieldValue.increment(Int64(1))]) { _ in
                        completion(.success(true))
                    }
                }
            }
        }
    }

    func isStarred(postId: String, userId: String, completion: @escaping (Bool) -> Void) {
        db.collection(postsCollection).document(postId).collection("stars").document(userId).getDocument { snapshot, _ in
            completion(snapshot?.exists == true)
        }
    }

    // MARK: - Fetch distinct camera values for filter options

    func fetchCameraOptions(completion: @escaping ([String]) -> Void) {
        db.collection(postsCollection).order(by: "timestamp", descending: true).limit(to: 200).getDocuments { snapshot, _ in
            guard let docs = snapshot?.documents else {
                completion([])
                return
            }
            let cameras = Set(docs.compactMap { $0.data()["camera"] as? String }.filter { !$0.isEmpty })
            completion(Array(cameras).sorted())
        }
    }

    enum ServiceError: LocalizedError {
        case imageConversionFailed
        case urlRetrievalFailed
        case missingDocumentId

        var errorDescription: String? {
            switch self {
            case .imageConversionFailed: return "Failed to convert image to JPEG data."
            case .urlRetrievalFailed: return "Failed to retrieve download URL."
            case .missingDocumentId: return "Post is missing a document ID."
            }
        }
    }
}

// MARK: - Feed Filter

struct FeedFilter {
    var myPostsOnly: Bool = false
    var excludeUserId: String? = nil
    var camera: String? = nil
    var sortBy: SortOrder = .newest
    var startDate: Date? = nil
    var endDate: Date? = nil
    var searchText: String? = nil
    var limit: Int = 100

    enum SortOrder: Int {
        case newest = 0
        case oldest = 1
    }
}

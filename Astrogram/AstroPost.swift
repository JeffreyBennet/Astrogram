import Foundation
import FirebaseFirestore

struct AstroPost {
    var id: String?
    let userId: String
    let userEmail: String
    let imageURL: String
    let imagePath: String
    let title: String
    let description: String
    let camera: String
    let iso: String
    let exposure: String
    let focalLength: String
    let locationName: String
    let latitude: Double?
    let longitude: Double?
    let timestamp: Date

    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "userId": userId,
            "userEmail": userEmail,
            "imageURL": imageURL,
            "imagePath": imagePath,
            "title": title,
            "description": description,
            "camera": camera,
            "iso": iso,
            "exposure": exposure,
            "focalLength": focalLength,
            "locationName": locationName,
            "timestamp": Timestamp(date: timestamp)
        ]
        if let lat = latitude { dict["latitude"] = lat }
        if let lon = longitude { dict["longitude"] = lon }
        return dict
    }

    static func from(document: QueryDocumentSnapshot) -> AstroPost? {
        let data = document.data()
        guard let userId = data["userId"] as? String,
              let userEmail = data["userEmail"] as? String,
              let imageURL = data["imageURL"] as? String,
              let imagePath = data["imagePath"] as? String,
              let title = data["title"] as? String,
              let ts = data["timestamp"] as? Timestamp else {
            return nil
        }
        return AstroPost(
            id: document.documentID,
            userId: userId,
            userEmail: userEmail,
            imageURL: imageURL,
            imagePath: imagePath,
            title: title,
            description: data["description"] as? String ?? "",
            camera: data["camera"] as? String ?? "",
            iso: data["iso"] as? String ?? "",
            exposure: data["exposure"] as? String ?? "",
            focalLength: data["focalLength"] as? String ?? "",
            locationName: data["locationName"] as? String ?? "",
            latitude: data["latitude"] as? Double,
            longitude: data["longitude"] as? Double,
            timestamp: ts.dateValue()
        )
    }
}

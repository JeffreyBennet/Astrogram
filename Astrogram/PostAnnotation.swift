import Foundation
import MapKit

final class PostAnnotation: NSObject, MKAnnotation {
    let post: AstroPost
    let coordinate: CLLocationCoordinate2D

    var title: String? { post.title }
    var subtitle: String? { post.locationName }

    var postId: String {
        post.id ?? UUID().uuidString
    }

    init(post: AstroPost, coordinate: CLLocationCoordinate2D) {
        self.post = post
        self.coordinate = coordinate
        super.init()
    }
}

import Foundation
import CoreLocation

struct Post: Identifiable, Codable {
    let id: String
    let userId: String
    let imageURL: String
    let caption: String
    let timestamp: Date
    var likes: Int
    var isLiked: Bool

    // New geo fields (optional)
    let latitude: Double?
    let longitude: Double?

    /// Convenience for MapKit
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lng = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

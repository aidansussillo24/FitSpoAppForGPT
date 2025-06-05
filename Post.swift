//
//  Post.swift
//  FitSpo
//

import Foundation
import CoreLocation

/// App-wide model of a single post.
struct Post: Identifiable, Codable {

    // ── Core fields ─────────────────────────────────────────────
    let id:        String
    let userId:    String
    let imageURL:  String
    let caption:   String
    let timestamp: Date
    var likes:     Int
    var isLiked:   Bool

    // ── Optional geo + weather ─────────────────────────────────
    let latitude:  Double?
    let longitude: Double?
    var  temp:     Double?        // 🌡 new (℃)

    /// Convenience for MapKit annotation
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lng = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    // ── CodingKeys keeps Firestore ↔︎ Swift names aligned ──────
    enum CodingKeys: String, CodingKey {
        case id, userId, imageURL, caption, timestamp, likes, isLiked
        case latitude, longitude, temp
    }
}

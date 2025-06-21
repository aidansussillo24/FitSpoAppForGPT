//
//  Post.swift
//  FitSpo
//

import Foundation
import CoreLocation

struct Post: Identifiable, Codable {

    // core
    let id:        String
    let userId:    String
    let imageURL:  String
    let caption:   String
    let timestamp: Date
    var likes:     Int
    var isLiked:   Bool

    // geo / weather
    let latitude:  Double?
    let longitude: Double?
    var  temp:     Double?

    // outfit
    var outfitItems: [OutfitItem]? = nil
    var outfitTags : [OutfitTag]?  = nil        // ← NEW

    // hashtags
    var hashtags: [String]

    // convenience
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    enum CodingKeys: String, CodingKey {
        case id, userId, imageURL, caption, timestamp, likes, isLiked
        case latitude, longitude, temp, hashtags
        case outfitItems, outfitTags
    }
}

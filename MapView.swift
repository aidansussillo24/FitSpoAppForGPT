// MapView.swift
// Shows all geo-tagged posts on a tappable map.

import SwiftUI
import MapKit

struct MapView: View {
    @State private var posts: [Post] = []
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749,
                                       longitude: -122.4194),
        span:   MKCoordinateSpan(latitudeDelta:  0.2,
                                 longitudeDelta: 0.2)
    )

    var body: some View {
        // 1️⃣ Filter to only those posts with non-nil coords
        let geoPosts = posts.filter { $0.latitude != nil && $0.longitude != nil }

        return NavigationView {
            Map(
                coordinateRegion: $region,
                annotationItems: geoPosts
            ) { post -> MapAnnotation in               // ← note the explicit return type
                // 2️⃣ Now it's safe to force-unwrap
                let coord = CLLocationCoordinate2D(
                    latitude:  post.latitude!,
                    longitude: post.longitude!
                )

                // 3️⃣ **RETURN** your annotation here
                return MapAnnotation(coordinate: coord) {
                    NavigationLink(destination: PostDetailView(post: post)) {
                        AsyncImage(url: URL(string: post.imageURL)) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                            case .success(let img):
                                img
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                Color.gray
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                        .shadow(radius: 3)
                    }
                }
            }
            .navigationTitle("Map")
            .onAppear {
                NetworkService.shared.fetchPosts { result in
                    if case .success(let allPosts) = result {
                        self.posts = allPosts

                        // center on first geo-tagged post, if any
                        if let first = allPosts.first,
                           let lat   = first.latitude,
                           let lng   = first.longitude
                        {
                            region.center = CLLocationCoordinate2D(
                                latitude:  lat,
                                longitude: lng
                            )
                        }
                    }
                }
            }
        }
    }
}

struct MapView_Previews: PreviewProvider {
    static var previews: some View {
        MapView()
    }
}

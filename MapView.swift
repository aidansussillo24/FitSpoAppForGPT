// MapView.swift
// Shows all geo-tagged posts on a tappable map.

import SwiftUI
import MapKit
import CoreLocation

struct MapView: View {
    @State private var allPosts: [Post] = []
    @State private var posts:    [Post] = []
    @State private var filter    = MapFilter()
    @State private var showFilters = false
    @State private var showSearch = false
    @State private var selectedLocation: LocationCluster?
    @State private var showLocationDetail = false
    @State private var searchText = ""
    @State private var clusters: [LocationCluster] = []
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
            ZStack {
                // Map with enhanced markers
                Map(
                    coordinateRegion: $region,
                    annotationItems: clusters
                ) { cluster -> MapAnnotation in
                    let coord = CLLocationCoordinate2D(
                        latitude:  cluster.latitude,
                        longitude: cluster.longitude
                    )

                    return MapAnnotation(coordinate: coord) {
                        InstagramStyleMapMarker(
                            cluster: cluster,
                            onTap: {
                                print("Tapping cluster: \(cluster.id) with \(cluster.posts.count) posts")
                                selectedLocation = cluster
                                showLocationDetail = true
                            }
                        )
                    }
                }
                
                // Search bar overlay
                VStack {
                    HStack {
                        // Search button
                        Button(action: { showSearch = true }) {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                Text("Search locations...")
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(.systemBackground))
                            .cornerRadius(25)
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                        }
                        
                        // Filter button
                        Button(action: { showFilters = true }) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: 44, height: 44)
                                .background(Color(.systemBackground))
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    Spacer()
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                let geoPosts = posts.filter { $0.latitude != nil && $0.longitude != nil }
                let newClusters = await createLocationClusters(from: geoPosts)
                await MainActor.run {
                    clusters = newClusters
                }
            }
            .onChange(of: posts) { _ in
                Task {
                    let geoPosts = posts.filter { $0.latitude != nil && $0.longitude != nil }
                    let newClusters = await createLocationClusters(from: geoPosts)
                    await MainActor.run {
                        clusters = newClusters
                    }
                }
            }
            .sheet(isPresented: $showFilters) {
                MapFilterSheet(filter: $filter)
                    .presentationDetents([.fraction(0.45)])
            }
            .sheet(isPresented: $showSearch) {
                MapSearchView(searchText: $searchText, onLocationSelected: { location in
                    // Center map on selected location
                    region.center = CLLocationCoordinate2D(
                        latitude: location.placemark.coordinate.latitude,
                        longitude: location.placemark.coordinate.longitude
                    )
                    region.span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    showSearch = false
                })
            }
            .sheet(isPresented: $showLocationDetail) {
                if let location = selectedLocation {
                    if location.posts.isEmpty {
                        // Fallback for invalid location
                        VStack(spacing: 20) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 48))
                                .foregroundColor(.orange)
                            
                            Text("Location not available")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Text("This location has no posts or data is unavailable.")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            Button("Close") {
                                showLocationDetail = false
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .padding(40)
                        .presentationDetents([.fraction(0.4)])
                    } else {
                        LocationDetailView(location: location)
                            .presentationDetents([.fraction(0.7), .large])
                    }
                } else {
                    // This should never happen, but just in case
                    Text("No location selected")
                        .presentationDetents([.fraction(0.2)])
                }
            }
            .onChange(of: showLocationDetail) { isShowing in
                if isShowing, let location = selectedLocation {
                    print("Showing location detail for: \(location.id) with \(location.posts.count) posts")
                    print("Posts: \(location.posts.map { $0.id })")
                }
            }
            .onChange(of: filter) { _ in applyFilter() }
            .onAppear {
                loadPosts()
            }
        }
    }
    
    // MARK: - Data Loading
    private func loadPosts() {
        NetworkService.shared.fetchPosts { result in
            if case .success(let allPosts) = result {
                self.allPosts = allPosts
                applyFilter()

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
    
    // MARK: - Location Clustering
    private func createLocationClusters(from posts: [Post]) async -> [LocationCluster] {
        let clusterRadius: Double = 0.0005 // ~50m radius - even more precise
        
        var clusters: [LocationCluster] = []
        var processedPosts: Set<String> = []
        
        print("Creating clusters from \(posts.count) posts")
        
        for post in posts {
            if processedPosts.contains(post.id) { continue }
            
            let coord = CLLocationCoordinate2D(
                latitude: post.latitude!,
                longitude: post.longitude!
            )
            
            // Find nearby posts
            let nearbyPosts = posts.filter { otherPost in
                guard let otherLat = otherPost.latitude,
                      let otherLng = otherPost.longitude else { return false }
                
                let otherCoord = CLLocationCoordinate2D(
                    latitude: otherLat,
                    longitude: otherLng
                )
                
                let location1 = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                let location2 = CLLocation(latitude: otherCoord.latitude, longitude: otherCoord.longitude)
                let distance = location1.distance(from: location2)
                // Only group posts that are very close (within ~25 meters)
                // This ensures they're actually from the same location
                return distance <= 25 // 25 meters max for more precise clustering
            }
            
            // Sort nearby posts by likes to get the top post
            let sortedNearbyPosts = nearbyPosts.sorted { $0.likes > $1.likes }
            let topPost = sortedNearbyPosts.first ?? post
            
            print("Post \(post.id) at (\(String(format: "%.6f", coord.latitude)), \(String(format: "%.6f", coord.longitude))) has \(nearbyPosts.count) nearby posts")
            
            // Only create a cluster if posts are actually from the same location
            // If it's just one post, don't cluster it
            if nearbyPosts.count == 1 {
                // Single post - create individual marker
                print("Creating single post marker for post \(post.id) with \(post.likes) likes")
                let cluster = LocationCluster(
                    id: post.id,
                    latitude: coord.latitude,
                    longitude: coord.longitude,
                    posts: [post],
                    name: generateLocationName(for: coord),
                    locationName: ""
                )
                clusters.append(cluster)
                processedPosts.insert(post.id)
            } else {
                // Multiple posts - create cluster only if they're very close
                print("Creating cluster with \(nearbyPosts.count) posts")
                for (index, nearbyPost) in nearbyPosts.enumerated() {
                    let nearbyCoord = CLLocationCoordinate2D(latitude: nearbyPost.latitude!, longitude: nearbyPost.longitude!)
                    let distance = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                        .distance(from: CLLocation(latitude: nearbyCoord.latitude, longitude: nearbyCoord.longitude))
                    print("  Post \(index + 1): \(nearbyPost.id) - Distance: \(String(format: "%.1f", distance))m - Likes: \(nearbyPost.likes)")
                }
                print("  Top post selected: \(topPost.id) with \(topPost.likes) likes")
                let cluster = LocationCluster(
                    id: "cluster_\(topPost.id)", // Use a unique cluster ID
                    latitude: coord.latitude,
                    longitude: coord.longitude,
                    posts: sortedNearbyPosts,
                    name: generateLocationName(for: coord),
                    locationName: ""
                )
                clusters.append(cluster)
                
                // Mark posts as processed
                for nearbyPost in nearbyPosts {
                    processedPosts.insert(nearbyPost.id)
                }
            }
        }
        
        print("Created \(clusters.count) total clusters")
        
        // Reverse geocode all clusters to get proper location names
        await reverseGeocodeClusters(&clusters)
        
        // Small delay to ensure UI updates
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        return clusters
    }
    
    // MARK: - Reverse Geocoding
    private func reverseGeocodeClusters(_ clusters: inout [LocationCluster]) async {
        let geocoder = CLGeocoder()
        
        for i in 0..<clusters.count {
            let location = CLLocation(latitude: clusters[i].latitude, longitude: clusters[i].longitude)
            
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                if let placemark = placemarks.first {
                    // Create a more readable location name
                    var locationName = ""
                    
                    // Try to get a more specific location name
                    if let name = placemark.name, !name.isEmpty {
                        locationName = name
                    } else if let thoroughfare = placemark.thoroughfare, let subThoroughfare = placemark.subThoroughfare {
                        locationName = "\(subThoroughfare) \(thoroughfare)"
                    } else if let thoroughfare = placemark.thoroughfare {
                        locationName = thoroughfare
                    } else if let locality = placemark.locality {
                        locationName = locality
                    } else if let subLocality = placemark.subLocality {
                        locationName = subLocality
                    } else if let administrativeArea = placemark.administrativeArea {
                        locationName = administrativeArea
                    } else if let country = placemark.country {
                        locationName = country
                    }
                    
                    // Update the cluster with the proper location name
                    if !locationName.isEmpty {
                        clusters[i].locationName = locationName
                        print("Updated location \(clusters[i].id) with name: \(locationName)")
                    }
                }
            } catch {
                print("Reverse geocoding failed for cluster \(clusters[i].id): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Location Name Generation
    private func generateLocationName(for coordinate: CLLocationCoordinate2D) -> String {
        // More user-friendly fallback name
        return "Location"
    }

    private func applyFilter() {
        var filtered = allPosts

        if let season = filter.season {
            filtered = filtered.filter { p in
                let m = Calendar.current.component(.month, from: p.timestamp)
                switch season {
                case .spring: return (3...5).contains(m)
                case .summer: return (6...8).contains(m)
                case .fall:   return (9...11).contains(m)
                case .winter: return m == 12 || m <= 2
                }
            }
        }

        if let band = filter.tempBand {
            filtered = filtered.filter { p in
                guard let c = p.temp else { return false }
                let f = c * 9 / 5 + 32
                switch band {
                case .cold: return f < 40
                case .cool: return f >= 40 && f < 60
                case .warm: return f >= 60 && f < 80
                case .hot:  return f >= 80
                }
            }
        }

        if let w = filter.weather {
            filtered = filtered.filter { p in
                guard let sym = p.weatherSymbolName else { return false }
                switch w {
                case .sunny:  return sym == "sun.max" || sym == "cloud.sun"
                case .cloudy: return sym.hasPrefix("cloud")
                }
            }
        }

        posts = filtered
    }
}

// MARK: - Location Cluster Model
struct LocationCluster: Identifiable {
    let id: String
    let latitude: Double
    let longitude: Double
    let posts: [Post]
    var name: String
    var locationName: String = ""
    
    var postCount: Int { posts.count }
    var primaryImageURL: String { 
        // Return the top post's image (most likes) - ensure we always get the right one
        guard !posts.isEmpty else { return "" }
        
        let topPost = posts.max(by: { $0.likes < $1.likes }) ?? posts.first!
        print("LocationCluster \(id): Selected top post \(topPost.id) with \(topPost.likes) likes for primary image")
        return topPost.imageURL
    }
    var distance: String {
        // Calculate distance from user's location (simplified)
        return "Nearby"
    }
    
    // Display name - prefer actual location name over coordinates
    var displayName: String {
        if !locationName.isEmpty {
            return locationName
        }
        return name
    }
}

// MARK: - Instagram Style Map Marker
struct InstagramStyleMapMarker: View {
    let cluster: LocationCluster
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Background circle
                Circle()
                    .fill(Color.white)
                    .frame(width: 50, height: 50)
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                
                // Border
                Circle()
                    .stroke(Color.primary, lineWidth: 2)
                    .frame(width: 50, height: 50)
                
                // Always show the top image
                RemoteImage(url: cluster.primaryImageURL, contentMode: .fill)
                    .frame(width: 46, height: 46)
                    .clipShape(Circle())
                    .onAppear {
                        print("Map marker for cluster \(cluster.id) displaying image URL: \(cluster.primaryImageURL)")
                        print("Cluster has \(cluster.posts.count) posts: \(cluster.posts.map { "\($0.id) (\($0.likes) likes)" })")
                    }
                
                // Show post count as a small badge if multiple posts
                if cluster.postCount > 1 {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("\(cluster.postCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.7))
                                .clipShape(Capsule())
                        }
                    }
                    .frame(width: 46, height: 46)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct MapView_Previews: PreviewProvider {
    static var previews: some View {
        MapView()
    }
}

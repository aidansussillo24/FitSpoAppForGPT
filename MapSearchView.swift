import SwiftUI
import MapKit

struct MapSearchView: View {
    @Binding var searchText: String
    let onLocationSelected: (MKMapItem) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search for a location...", text: $searchText)
                        .textFieldStyle(.plain)
                        .onChange(of: searchText) { _ in
                            performSearch()
                        }
                    
                    if !searchText.isEmpty {
                        Button("Clear") {
                            searchText = ""
                            searchResults.removeAll()
                        }
                        .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                
                // Search results
                if isSearching {
                    Spacer()
                    ProgressView("Searching...")
                        .foregroundColor(.secondary)
                    Spacer()
                } else if searchResults.isEmpty && !searchText.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "location.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No locations found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Try searching for a different location")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    List(searchResults, id: \.self) { item in
                        Button(action: {
                            onLocationSelected(item)
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.red)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name ?? "Unknown Location")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.primary)
                                    
                                    if let locality = item.placemark.locality {
                                        Text(locality)
                                            .font(.system(size: 14))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func performSearch() {
        guard !searchText.isEmpty else {
            searchResults.removeAll()
            return
        }
        
        isSearching = true
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        request.resultTypes = .pointOfInterest
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            DispatchQueue.main.async {
                isSearching = false
                
                if let error = error {
                    print("Search error: \(error.localizedDescription)")
                    searchResults.removeAll()
                } else {
                    searchResults = response?.mapItems ?? []
                }
            }
        }
    }
}

struct MapSearchView_Previews: PreviewProvider {
    static var previews: some View {
        MapSearchView(searchText: .constant(""), onLocationSelected: { _ in })
    }
} 
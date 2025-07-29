import SwiftUI

struct MapFilterSheet: View {
    @Binding var filter: MapFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 20) {
                    // Handle
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color(.systemGray4))
                        .frame(width: 36, height: 5)
                        .padding(.top, 8)
                    
                    // Title
                    Text("Filter Posts")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)
                }
                .padding(.bottom, 30)
                
                // Filter options
                ScrollView {
                    VStack(spacing: 32) {
                        // Temperature filter
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Temperature")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                                ForEach(MapFilter.TempBand.allCases, id: \.self) { temp in
                                    FilterChip(
                                        title: temp.displayName,
                                        icon: temp.icon,
                                        isSelected: filter.tempBand == temp,
                                        action: {
                                            if filter.tempBand == temp {
                                                filter.tempBand = nil
                                            } else {
                                                filter.tempBand = temp
                                            }
                                        }
                                    )
                                }
                            }
                        }
                        
                        // Weather filter
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Weather")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                                ForEach(MapFilter.Weather.allCases, id: \.self) { weather in
                                    FilterChip(
                                        title: weather.displayName,
                                        icon: weather.icon,
                                        isSelected: filter.weather == weather,
                                        action: {
                                            if filter.weather == weather {
                                                filter.weather = nil
                                            } else {
                                                filter.weather = weather
                                            }
                                        }
                                    )
                                }
                            }
                        }
                        
                        // Season filter
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Season")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                                ForEach(ExploreFilter.Season.allCases, id: \.self) { season in
                                    FilterChip(
                                        title: season.displayName,
                                        icon: season.icon,
                                        isSelected: filter.season == season,
                                        action: {
                                            if filter.season == season {
                                                filter.season = nil
                                            } else {
                                                filter.season = season
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }
                
                // Action buttons
                VStack(spacing: 12) {
                    Button(action: {
                        filter = MapFilter()
                    }) {
                        Text("Clear All")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                    }
                    
                    Button(action: { dismiss() }) {
                        Text("Apply Filters")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Filter Chip Component
struct FilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                
                Spacer()
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? Color.blue : Color(.systemGray6))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Filter Extensions
extension MapFilter.TempBand {
    var displayName: String {
        switch self {
        case .cold: return "Cold"
        case .cool: return "Cool"
        case .warm: return "Warm"
        case .hot: return "Hot"
        }
    }
    
    var icon: String {
        switch self {
        case .cold: return "thermometer.snowflake"
        case .cool: return "thermometer.low"
        case .warm: return "thermometer.medium"
        case .hot: return "thermometer.sun"
        }
    }
}

extension MapFilter.Weather {
    var displayName: String {
        switch self {
        case .sunny: return "Sunny"
        case .cloudy: return "Cloudy"
        }
    }
    
    var icon: String {
        switch self {
        case .sunny: return "sun.max"
        case .cloudy: return "cloud"
        }
    }
}

extension ExploreFilter.Season {
    var displayName: String {
        switch self {
        case .spring: return "Spring"
        case .summer: return "Summer"
        case .fall: return "Fall"
        case .winter: return "Winter"
        }
    }
    
    var icon: String {
        switch self {
        case .spring: return "leaf"
        case .summer: return "sun.max"
        case .fall: return "leaf.fill"
        case .winter: return "snowflake"
        }
    }
}

struct MapFilterSheet_Previews: PreviewProvider {
    static var previews: some View {
        MapFilterSheet(filter: .constant(MapFilter()))
    }
}

import SwiftUI
import FirebaseAuth

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }

            ExploreView()
                .tabItem {
                    Label("Explore", systemImage: "magnifyingglass")
                }

            NewPostView()
                .tabItem {
                    Label("Post", systemImage: "plus.app")
                }

            MapView()
                .tabItem {
                    Label("Map", systemImage: "map")
                }

            ProfileView(userId: Auth.auth().currentUser?.uid ?? "")
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
        }
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}

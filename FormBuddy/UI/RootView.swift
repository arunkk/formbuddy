import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            SessionListView()
                .tabItem { Label("Sessions", systemImage: "list.bullet.rectangle") }
            GuidanceView()
                .tabItem { Label("Guidance", systemImage: "camera.viewfinder") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

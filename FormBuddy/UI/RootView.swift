import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            SessionListView()
                .tabItem { Label("Sessions", systemImage: "list.bullet") }
            GuidanceView()
                .tabItem { Label("Guidance", systemImage: "info.circle") }
        }
    }
}

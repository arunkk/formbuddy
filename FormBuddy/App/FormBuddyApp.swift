import SwiftUI
import SwiftData

@main
struct FormBuddyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Session.self, RepRecord.self])
    }
}

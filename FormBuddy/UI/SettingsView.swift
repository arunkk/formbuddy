import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Privacy") {
                    Text("FormBuddy does not collect any data. All processing happens on-device.")
                }
                Section("Storage") {
                    Text("Videos are stored locally and can be deleted per session.")
                }
                Section("About") {
                    Text("FormBuddy v1.0")
                    Text("On-device squat form analysis")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

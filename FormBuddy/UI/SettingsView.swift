import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var sessions: [Session]
    @State private var storageBytes: Int64 = 0
    @State private var showDeleteAllConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Video & reports") {
                        Text(byteString)
                            .foregroundStyle(.secondary)
                    }
                    if !sessions.isEmpty {
                        Button(role: .destructive) {
                            showDeleteAllConfirm = true
                        } label: {
                            Label("Delete all sessions", systemImage: "trash")
                        }
                    }
                } header: {
                    Text("Storage")
                } footer: {
                    Text("Clips are stored on this device only. Deleting a session also deletes its video.")
                }

                Section {
                    Text("FormBuddy doesn't collect any data. There's no account, no upload, and no network access — pose estimation and scoring run entirely on this device.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Privacy")
                }

                Section {
                    HStack(spacing: 12) {
                        Image("BrandMark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FormBuddy v1.0")
                                .font(.body.weight(.semibold))
                            Text("On-device squat form analysis")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .task { refreshStorage() }
            .confirmationDialog(
                "Delete all sessions?",
                isPresented: $showDeleteAllConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete all", role: .destructive, action: deleteAll)
            } message: {
                Text("Every video and report will be removed from this device. This can't be undone.")
            }
        }
    }

    private var byteString: String {
        ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file)
    }

    private func refreshStorage() {
        storageBytes = SessionStore.totalBytes()
    }

    private func deleteAll() {
        SessionStore.deleteAll()
        try? modelContext.delete(model: Session.self)
        try? modelContext.save()
        refreshStorage()
    }
}

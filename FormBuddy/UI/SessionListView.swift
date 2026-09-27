import SwiftUI
import SwiftData

struct SessionListView: View {
    @Query(sort: \Session.createdAt, order: .reverse) private var sessions: [Session]
    @State private var showCapture = false

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    VStack(spacing: 16) {
                        Text("No sessions yet")
                            .font(.title2)
                        Text("Record a squat clip to get started")
                            .foregroundColor(.secondary)
                        Button("Record") { showCapture = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(sessions) { session in
                        NavigationLink(destination: SessionDetailView(report: nil, videoURL: URL(fileURLWithPath: session.videoFilename), session: session)) {
                            VStack(alignment: .leading) {
                                Text(session.exercise.capitalized)
                                    .font(.headline)
                                Text("\(session.summary.totalReps) reps")
                                    .font(.subheadline)
                                if !session.warnings.isEmpty {
                                    Text(session.warnings.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("FormBuddy")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showCapture = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCapture) {
                CaptureView()
            }
        }
    }
}

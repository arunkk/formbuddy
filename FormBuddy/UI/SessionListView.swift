import SwiftUI
import SwiftData

struct SessionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Session.createdAt, order: .reverse) private var sessions: [Session]
    @State private var showCapture = false

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .navigationTitle("FormBuddy")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCapture = true
                    } label: {
                        Label("Record or import", systemImage: "video.badge.plus")
                    }
                    .accessibilityLabel("Record or import a clip")
                }
            }
            .sheet(isPresented: $showCapture) {
                CaptureView()
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("No sets yet")
            } icon: {
                Image("BrandMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
            }
        } description: {
            Text("Record a squat set or import a clip to get rep-by-rep form feedback — all on device.")
        } actions: {
            Button {
                showCapture = true
            } label: {
                Label("Record or import", systemImage: "video.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var sessionList: some View {
        List {
            ForEach(sessions) { session in
                NavigationLink(value: session) {
                    SessionRow(session: session)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        delete(session)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationDestination(for: Session.self) { session in
            SessionDetailView(session: session)
        }
    }

    private func delete(_ session: Session) {
        SessionStore.delete(for: session.id)
        modelContext.delete(session)
        try? modelContext.save()
    }
}

/// A row summarizes one set: exercise, date, rep count, and depth/fault badges.
private struct SessionRow: View {
    let session: Session

    private var hasFaults: Bool {
        session.reps.contains { !$0.faults.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.exercise.capitalized)
                    .font(.headline)
                Spacer()
                Text("\(session.summary.totalReps) \(session.summary.totalReps == 1 ? "rep" : "reps")")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if !badges.isEmpty {
                HStack(spacing: 6) {
                    ForEach(badges, id: \.text) { badge in
                        Chip(text: badge.text, tint: badge.tint)
                    }
                }
            }

            Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private struct Badge {
        let text: String
        let tint: Color
    }

    private var badges: [Badge] {
        var result: [Badge] = []
        if session.summary.repsBelowParallel > 0 {
            result.append(Badge(text: "\(session.summary.repsBelowParallel) below parallel", tint: .green))
        }
        if session.summary.partialReps > 0 {
            result.append(Badge(text: "\(session.summary.partialReps) partial", tint: .orange))
        }
        if hasFaults {
            result.append(Badge(text: "Form notes", tint: .red))
        }
        return result
    }

    private var accessibilitySummary: String {
        var parts = [
            session.exercise.capitalized,
            "\(session.summary.totalReps) reps",
            session.createdAt.formatted(date: .abbreviated, time: .shortened),
        ]
        if session.summary.repsBelowParallel > 0 {
            parts.append("\(session.summary.repsBelowParallel) below parallel")
        }
        if session.summary.partialReps > 0 {
            parts.append("\(session.summary.partialReps) partial")
        }
        if hasFaults { parts.append("has form notes") }
        return parts.joined(separator: ", ")
    }
}

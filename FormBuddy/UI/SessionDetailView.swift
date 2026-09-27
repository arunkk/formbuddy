import SwiftUI

struct SessionDetailView: View {
    let report: SquatReport?
    let videoURL: URL
    var session: Session?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let report = report {
                    // Summary cards
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Summary")
                            .font(.title2).bold()
                        HStack {
                            SummaryCard(title: "Total Reps", value: "\(report.summary.totalReps)")
                            SummaryCard(title: "Below Parallel", value: "\(report.summary.repsBelowParallel)")
                        }
                        HStack {
                            SummaryCard(title: "Avg Eccentric", value: String(format: "%.2fs", report.summary.avgEccentricSeconds))
                            SummaryCard(title: "Avg Concentric", value: String(format: "%.2fs", report.summary.avgConcentricSeconds))
                        }
                    }

                    // Rep list
                    Text("Reps")
                        .font(.title2).bold()
                    ForEach(report.reps, id: \.repNumber) { rep in
                        HStack {
                            Text("#\(rep.repNumber)")
                            Text(rep.depth.replacingOccurrences(of: "_", with: " "))
                            if rep.partial {
                                Text("partial")
                                    .foregroundColor(.orange)
                            }
                            Spacer()
                            if !rep.faults.isEmpty {
                                Text(rep.faults.joined(separator: ", "))
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // Knee angle chart
                    KneeAngleChart(annotations: report.frames)
                        .padding(.top)

                    // Warnings
                    if !report.warnings.isEmpty {
                        Text("Warnings")
                            .font(.title2).bold()
                        ForEach(report.warnings, id: \.self) { warning in
                            Text(warning)
                                .foregroundColor(.orange)
                        }
                    }
                } else if let session = session {
                    Text("Session: \(session.exercise.capitalized)")
                        .font(.title2).bold()
                    Text("Reps: \(session.summary.totalReps)")
                    Text("Duration: \(String(format: "%.1fs", session.duration))")
                } else {
                    Text("No data")
                }
            }
            .padding()
        }
        .navigationTitle("Session Detail")
    }
}

struct SummaryCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack {
            Text(value)
                .font(.title)
                .bold()
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

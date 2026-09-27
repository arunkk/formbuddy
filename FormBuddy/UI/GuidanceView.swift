import SwiftUI

struct GuidanceView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Filming Guidance")
                        .font(.title)
                        .bold()
                    Text("• Side view — camera perpendicular to your direction of travel")
                    Text("• Full body in frame — head to toe, with margin")
                    Text("• Good lighting — bright, even, diffuse light")
                    Text("• 30 fps or faster")
                }
                .padding()
            }
            .navigationTitle("Guidance")
        }
    }
}

import SwiftUI

struct AmbientLevelCard: View {
    let appDbfs: Double
    let micDbfs: Double
    let isActive: Bool

    private let spaceIndigo = Color(red: 0.082, green: 0.114, blue: 0.208)
    private let paleSlate   = Color(red: 0.878, green: 0.898, blue: 0.941)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ambient Levels")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(spaceIndigo)

            levelRow(label: "App Audio", dbfs: appDbfs)
            levelRow(label: "Mic", dbfs: micDbfs)
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(paleSlate, lineWidth: 1)
        )
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private func levelRow(label: String, dbfs: Double) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary)
                .frame(width: 72, alignment: .leading)

            if isActive {
                ProgressView(value: normalised(dbfs))
                    .progressViewStyle(.linear)
                    .tint(barColor(for: dbfs))
                    .frame(maxWidth: .infinity)

                Text(String(format: "%.0f dB", dbfs))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 50, alignment: .trailing)
            } else {
                Text("—")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // Maps −60 dBFS → 0.0, 0 dBFS → 1.0, clamped to [0, 1]
    private func normalised(_ dbfs: Double) -> Double {
        max(0, min(1, (dbfs + 60) / 60))
    }

    // Green below −20 dBFS, yellow below −6 dBFS, orange at or above −6 dBFS
    private func barColor(for dbfs: Double) -> Color {
        if dbfs < -20 { return .green }
        if dbfs < -6  { return .yellow }
        return .orange
    }
}

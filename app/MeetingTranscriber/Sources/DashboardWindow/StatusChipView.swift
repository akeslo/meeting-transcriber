import SwiftUI

struct StatusChipView: View {

    // MARK: - ChipColor

    enum ChipColor: Equatable {
        case green
        case peachGlow
        case red
        case slateGrey
    }

    // MARK: - Static helpers (testable)

    static func chipColor(for status: String) -> ChipColor {
        switch status {
        case "done", "transcribed", "summarized":
            return .green
        case "transcribing", "diarizing", "waiting", "generatingProtocol":
            return .peachGlow
        case "saved":
            return .slateGrey
        case "error":
            return .red
        default:
            return .slateGrey
        }
    }

    static func chipLabel(for status: String) -> String {
        switch status {
        case "done", "transcribed":    return "Transcribed"
        case "summarized":             return "Summarized"
        case "transcribing":           return "Transcribing"
        case "diarizing":              return "Diarizing"
        case "waiting":                return "Waiting"
        case "generatingProtocol":     return "Summarizing"
        case "error":                  return "Error"
        case "saved":                  return "Saved"
        default:
            return status.prefix(1).uppercased() + status.dropFirst()
        }
    }

    // MARK: - View

    let status: String

    private var resolvedColor: Color {
        switch Self.chipColor(for: status) {
        case .green:     return Color(red: 0.204, green: 0.780, blue: 0.349)
        case .peachGlow: return Color(red: 0.969, green: 0.773, blue: 0.624)
        case .red:       return Color(red: 0.906, green: 0.298, blue: 0.235)
        case .slateGrey: return Color(red: 0.780, green: 0.800, blue: 0.859)
        }
    }

    var body: some View {
        Text(Self.chipLabel(for: status))
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(resolvedColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(resolvedColor.opacity(0.15))
            .clipShape(Capsule())
    }
}

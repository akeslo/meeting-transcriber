import SwiftUI

// MARK: - SettingsSection

enum SettingsSection: String, CaseIterable, Identifiable {
    case detection    = "Detection"
    case audio        = "Audio"
    case transcription = "Transcription"
    case speakers     = "Speakers"
    case output       = "Output"
    case advanced     = "Advanced"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .detection:     return "eye"
        case .audio:         return "mic"
        case .transcription: return "waveform"
        case .speakers:      return "person.2"
        case .output:        return "doc.text"
        case .advanced:      return "gearshape.2"
        }
    }
}

// MARK: - SettingsContentView

struct SettingsContentView: View {
    let settings: AppSettings
    let whisperKitEngine: WhisperKitEngine
    let parakeetEngine: ParakeetEngine
    let qwen3Engine: (any TranscribingEngine)?
    var updateChecker: UpdateChecker?
    let recognitionStatsLog: RecognitionStatsLog
    let enrollmentDiarizerFactory: (() -> any DiarizationProvider)?
    let namingDialogActive: Bool
    let pipelineBusy: Bool
    let onSpeakerMutate: (() -> Void)?

    @State private var selectedSection: SettingsSection = .detection

    private let spaceIndigo = Color(red: 0.082, green: 0.114, blue: 0.208)
    private let subSidebarBg = Color(red: 0.118, green: 0.157, blue: 0.267)
    private let peachGlow    = Color(red: 0.969, green: 0.773, blue: 0.624)
    private let slateGrey    = Color(red: 0.780, green: 0.800, blue: 0.859)
    private let aliceBlue    = Color(red: 0.882, green: 0.898, blue: 0.933)

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            Divider()
            sectionContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Settings sidebar

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(slateGrey)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 8)

            ForEach(SettingsSection.allCases) { section in
                settingsSidebarRow(section)
            }

            Spacer()
        }
        .frame(width: 160)
        .background(subSidebarBg)
    }

    @ViewBuilder
    private func settingsSidebarRow(_ section: SettingsSection) -> some View {
        let isActive = selectedSection == section

        Button {
            selectedSection = section
        } label: {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(isActive ? peachGlow : Color.clear)
                    .frame(width: 3, height: 16)
                    .cornerRadius(1.5)

                Image(systemName: section.systemImage)
                    .font(.system(size: 13))
                    .foregroundStyle(isActive ? .white : slateGrey)
                    .frame(width: 16)

                Text(section.rawValue)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? .white : slateGrey)

                Spacer()
            }
            .padding(.trailing, 12)
            .padding(.vertical, 8)
            .background(isActive ? aliceBlue.opacity(0.12) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section content

    @ViewBuilder
    private var sectionContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch selectedSection {
                case .detection:
                    GeneralSettingsView(settings: settings, updateChecker: updateChecker)
                case .audio:
                    AudioSettingsView(settings: settings)
                case .transcription:
                    TranscriptionSettingsView(
                        settings: settings,
                        whisperKitEngine: whisperKitEngine,
                        parakeetEngine: parakeetEngine,
                        qwen3Engine: qwen3Engine,
                    )
                case .speakers:
                    SpeakersSettingsView(
                        settings: settings,
                        recognitionStatsLog: recognitionStatsLog,
                        enrollmentDiarizerFactory: enrollmentDiarizerFactory,
                        namingDialogActive: namingDialogActive,
                        pipelineBusy: pipelineBusy,
                        onSpeakerMutate: onSpeakerMutate,
                    )
                case .output:
                    OutputSettingsView(settings: settings)
                case .advanced:
                    AdvancedSettingsView(settings: settings)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

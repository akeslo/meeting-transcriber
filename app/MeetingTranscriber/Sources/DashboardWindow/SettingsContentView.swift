import SwiftUI

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

    @State private var detectionExpanded: Bool = true
    @State private var audioExpanded: Bool = true
    @State private var transcriptionExpanded: Bool = true
    @State private var speakersExpanded: Bool = true
    @State private var outputExpanded: Bool = true
    @State private var advancedExpanded: Bool = false

    private let spaceIndigo = Color(red: 0.082, green: 0.114, blue: 0.208)
    private let paleSlate   = Color(red: 0.878, green: 0.898, blue: 0.941)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionCard(
                    icon: "eye",
                    title: "Detection & Patterns",
                    isExpanded: $detectionExpanded,
                    spaceIndigo: spaceIndigo,
                    paleSlate: paleSlate,
                ) {
                    GeneralSettingsView(settings: settings, updateChecker: updateChecker)
                }
                SettingsSectionCard(
                    icon: "mic",
                    title: "Audio & Capture",
                    isExpanded: $audioExpanded,
                    spaceIndigo: spaceIndigo,
                    paleSlate: paleSlate,
                ) {
                    AudioSettingsView(settings: settings)
                }
                SettingsSectionCard(
                    icon: "waveform",
                    title: "Transcription Engine",
                    isExpanded: $transcriptionExpanded,
                    spaceIndigo: spaceIndigo,
                    paleSlate: paleSlate,
                ) {
                    TranscriptionSettingsView(
                        settings: settings,
                        whisperKitEngine: whisperKitEngine,
                        parakeetEngine: parakeetEngine,
                        qwen3Engine: qwen3Engine,
                    )
                }
                SettingsSectionCard(
                    icon: "person.2",
                    title: "Speakers & Diarization",
                    isExpanded: $speakersExpanded,
                    spaceIndigo: spaceIndigo,
                    paleSlate: paleSlate,
                ) {
                    SpeakersSettingsView(
                        settings: settings,
                        recognitionStatsLog: recognitionStatsLog,
                        enrollmentDiarizerFactory: enrollmentDiarizerFactory,
                        namingDialogActive: namingDialogActive,
                        pipelineBusy: pipelineBusy,
                        onSpeakerMutate: onSpeakerMutate,
                    )
                }
                SettingsSectionCard(
                    icon: "doc.text",
                    title: "Output & Protocol",
                    isExpanded: $outputExpanded,
                    spaceIndigo: spaceIndigo,
                    paleSlate: paleSlate,
                ) {
                    OutputSettingsView(settings: settings)
                }
                SettingsSectionCard(
                    icon: "gearshape.2",
                    title: "Advanced",
                    isExpanded: $advancedExpanded,
                    spaceIndigo: spaceIndigo,
                    paleSlate: paleSlate,
                ) {
                    AdvancedSettingsView(settings: settings)
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - SettingsSectionCard

private struct SettingsSectionCard<Content: View>: View {
    let icon: String
    let title: String
    @Binding var isExpanded: Bool
    let spaceIndigo: Color
    let paleSlate: Color
    @ViewBuilder let content: Content

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
                .padding(.top, 12)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(spaceIndigo)
                    .imageScale(.medium)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(spaceIndigo)
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(paleSlate, lineWidth: 1)
        )
    }
}

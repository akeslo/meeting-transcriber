import AVFoundation
import SwiftUI

struct AudioSettingsView: View {
    @Bindable var settings: AppSettings
    @State private var audioDevices: [(id: String, name: String)] = []

    var body: some View {
        Form {
            Section("Microphone") {
                Toggle("No Microphone (app audio only)", isOn: $settings.noMic)

                if !settings.noMic {
                    Picker("Microphone", selection: $settings.micDeviceUID) {
                        Text("System Default").tag("")
                        ForEach(audioDevices, id: \.id) { device in
                            Text(device.name).tag(device.id)
                        }
                    }
                    .onAppear { refreshAudioDevices() }
                    .onReceive(
                        NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification)
                    ) { _ in refreshAudioDevices() }
                    .onReceive(
                        NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification)
                    ) { _ in refreshAudioDevices() }
                }
            }

            Section("Voice Activity Detection") {
                Toggle("Voice Activity Detection (VAD)", isOn: $settings.vadEnabled)
                    .help("Remove silence before transcription for better results")

                if settings.vadEnabled {
                    HStack {
                        Text("Threshold:")
                        Slider(value: $settings.vadThreshold, in: 0.3 ... 0.9, step: 0.05)
                            .accessibilityLabel("Voice activity detection threshold")
                        TextField(
                            "",
                            value: $settings.vadThreshold,
                            format: .number.precision(.fractionLength(2)),
                        )
                        .monospacedDigit()
                        .frame(width: 50)
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel("VAD threshold value")
                        .onSubmit {
                            settings.vadThreshold = min(0.9, max(0.3, settings.vadThreshold))
                        }
                    }
                }
            }
            .accessibilityIdentifier("vadSection")
            .recordOnlyDisabled(settings.recordOnly)
        }
        .formStyle(.grouped)
    }

    private func refreshAudioDevices() {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified,
        )
        audioDevices = session.devices.map { (id: $0.uniqueID, name: $0.localizedName) }
    }
}

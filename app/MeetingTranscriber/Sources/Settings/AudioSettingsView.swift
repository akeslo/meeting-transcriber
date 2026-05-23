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
                }
            }

            Section("Voice Activity Detection") {
                Toggle("Voice Activity Detection (VAD)", isOn: $settings.vadEnabled)
                    .help("Remove silence before transcription for better results")

                if settings.vadEnabled {
                    Picker("Mode", selection: $settings.vadPreset) {
                        ForEach(VadPreset.allCases, id: \.self) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    .onChange(of: settings.vadPreset) { _, preset in
                        if let t = preset.threshold { settings.vadThreshold = t }
                    }

                    HStack {
                        Text("Threshold:")
                        Slider(value: $settings.vadThreshold, in: 0.1 ... 0.95, step: 0.05) { editing in
                            if !editing { settings.vadPreset = .custom }
                        }
                        Text(String(format: "%.2f", settings.vadThreshold))
                            .monospacedDigit()
                            .frame(width: 35)
                    }
                    .foregroundStyle(settings.vadPreset == .custom ? .primary : .secondary)
                }
            }
            .accessibilityIdentifier("vadSection")
            .recordOnlyDisabled(settings.recordOnly)

            PerChannelIndicatorSection(settings: settings)

            MicTestSection()
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

private struct MicTestSection: View {
    enum TestPhase { case idle, recording, playing, done }

    @State private var phase: TestPhase = .idle
    @State private var recorder: AVAudioRecorder?
    @State private var player: AVAudioPlayer?
    @State private var errorMessage: String?

    private static let testURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mic_test.wav")

    var body: some View {
        Section("Microphone Test") {
            HStack(spacing: 10) {
                Button(action: run) {
                    Label(buttonLabel, systemImage: buttonIcon)
                }
                .disabled(phase == .recording || phase == .playing)

                if phase == .recording || phase == .playing {
                    ProgressView().controlSize(.small)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            if phase == .recording {
                Text("Recording 3 s…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if phase == .playing {
                Text("Playing back…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var buttonLabel: String {
        switch phase {
        case .idle:      "Test Microphone"
        case .recording: "Recording…"
        case .playing:   "Playing Back…"
        case .done:      "Test Again"
        }
    }

    private var buttonIcon: String {
        switch phase {
        case .idle, .done: "mic"
        case .recording:   "waveform"
        case .playing:     "speaker.wave.2"
        }
    }

    private func run() {
        errorMessage = nil
        phase = .recording
        let url = Self.testURL
        let recSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            recorder = try AVAudioRecorder(url: url, settings: recSettings)
            recorder?.record()
        } catch {
            phase = .idle
            errorMessage = "Cannot start recording: \(error.localizedDescription)"
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(3))
            recorder?.stop()
            phase = .playing
            do {
                let p = try AVAudioPlayer(contentsOf: url)
                player = p
                p.play()
                try? await Task.sleep(for: .seconds(p.duration + 0.3))
                phase = .done
            } catch {
                phase = .idle
                errorMessage = "Playback failed: \(error.localizedDescription)"
            }
        }
    }
}

private struct PerChannelIndicatorSection: View {
    @Bindable var settings: AppSettings

    private static let toggleHelp =
        "Turn the menu bar red when one capture channel goes silent while the other still carries audio. " +
        "Catches asymmetric capture failures (muted mic, dropped app-audio tap) in real time."

    private static let sliderHelp =
        "Continuous asymmetric silence required before the indicator and notification fire. " +
        "Short enough to surface a dead channel during a meeting, long enough to ignore speaking pauses."

    var body: some View {
        Section("Per-Channel Indicator") {
            Toggle("Detect Silent Capture Channel", isOn: $settings.perChannelIndicatorEnabled)
                .help(Self.toggleHelp)

            if settings.perChannelIndicatorEnabled {
                HStack {
                    Text("Warn after:")
                    Slider(
                        value: $settings.asymmetricSilenceWarningSeconds,
                        in: 30 ... 300,
                        step: 10,
                    )
                    Text("\(Int(settings.asymmetricSilenceWarningSeconds))s")
                        .monospacedDigit()
                        .frame(width: 40)
                }
                .help(Self.sliderHelp)
            }
        }
        .accessibilityIdentifier("channelIndicatorSection")
    }
}

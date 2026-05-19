import AppKit
import SwiftUI

/// A running GUI application that can be selected for recording.
struct RunningApp: Identifiable, Hashable {
    let id: pid_t
    let name: String
    let bundleIdentifier: String?
    let icon: NSImage?
}

/// Provides the list of running apps. Protocol for testability.
protocol RunningAppsProvider {
    @MainActor
    func runningApps() -> [RunningApp]
}

/// Production provider that reads from NSWorkspace.
struct SystemRunningAppsProvider: RunningAppsProvider {
    @MainActor
    func runningApps() -> [RunningApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> RunningApp? in
                guard let name = app.localizedName, !name.isEmpty else { return nil }
                return RunningApp(
                    id: app.processIdentifier,
                    name: name,
                    bundleIdentifier: app.bundleIdentifier,
                    icon: app.icon,
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// View that lets the user pick a running app and start recording it.
@MainActor
struct AppPickerView: View {
    let appsProvider: any RunningAppsProvider
    let onStartRecording: (pid_t, String, String, Bool, Int) -> Void
    let onCancel: () -> Void

    @State private var apps: [RunningApp] = []
    @State private var selectedApp: RunningApp?
    @State private var meetingTitle: String = ""
    @State private var includeMic: Bool = true
    @State private var numSpeakers: Int = 2

    init(
        appsProvider: any RunningAppsProvider = SystemRunningAppsProvider(),
        initialNumSpeakers: Int = 2,
        onStartRecording: @escaping (pid_t, String, String, Bool, Int) -> Void,
        onCancel: @escaping () -> Void,
    ) {
        self.appsProvider = appsProvider
        self.onStartRecording = onStartRecording
        self.onCancel = onCancel
        _numSpeakers = State(initialValue: max(initialNumSpeakers, 0))
    }

    var body: some View {
        // swiftlint:disable:next closure_body_length
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Record App")
                    .font(.headline)
                Spacer()
                Button {
                    apps = appsProvider.runningApps()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Refresh")
            }
            .padding()

            Divider()

            // App list
            List(apps, selection: $selectedApp) { app in
                HStack(spacing: 8) {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 20, height: 20)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "app.fill")
                            .frame(width: 20, height: 20)
                            .accessibilityHidden(true)
                    }
                    Text(app.name)
                    Spacer()
                }
                .tag(app)
            }
            .frame(minHeight: 200)
            .overlay {
                if apps.isEmpty {
                    Text("No recordable apps are running.")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Title + actions
            VStack(spacing: 12) {
                TextField("Meeting title (optional)", text: $meetingTitle)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 16) {
                    Toggle("Include Mic", isOn: $includeMic)
                    Spacer()
                    Stepper(
                        numSpeakers == 0 ? "Auto" : numSpeakers == 1 ? "1 speaker (no diarization)" : "\(numSpeakers) speakers",
                        value: $numSpeakers, in: 0 ... 10,
                    )
                    .accessibilityLabel("Number of speakers")
                    .accessibilityValue(numSpeakers == 0 ? "Auto-detect" : "\(numSpeakers)")
                    .help(numSpeakers == 1 ? "Single speaker mode — diarization disabled." : "")
                }

                HStack {
                    Button("Cancel") {
                        onCancel()
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button("Start Recording") {
                        guard let app = selectedApp else { return }
                        let title = meetingTitle.isEmpty ? app.name : meetingTitle
                        onStartRecording(app.id, app.name, title, includeMic, numSpeakers)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedApp == nil)
                    .help(selectedApp == nil ? "Select an app to enable recording" : "")
                }
            }
            .padding()
        }
        .frame(width: 520, height: 460)
        .onAppear {
            apps = appsProvider.runningApps()
        }
    }
}

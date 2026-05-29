import AppKit
import CoreGraphics
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
    let onStartRecording: (pid_t, String, String) -> Void
    let onCancel: () -> Void

    @State private var apps: [RunningApp] = []
    @State private var selectedApp: RunningApp?
    @State private var meetingTitle: String = ""
    @State private var lastAutoTitle: String = ""

    init(
        appsProvider: any RunningAppsProvider = SystemRunningAppsProvider(),
        onStartRecording: @escaping (pid_t, String, String) -> Void,
        onCancel: @escaping () -> Void,
    ) {
        self.appsProvider = appsProvider
        self.onStartRecording = onStartRecording
        self.onCancel = onCancel
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
                    } else {
                        Image(systemName: "app.fill")
                            .frame(width: 20, height: 20)
                    }
                    Text(app.name)
                    Spacer()
                    Text("PID \(app.id)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(app)
            }
            .frame(minHeight: 200)
            .onChange(of: selectedApp) { _, newApp in
                guard let app = newApp else { return }
                let windowTitle = frontWindowTitle(for: app.id)
                let autoTitle = windowTitle.map { "\(app.name) \u{2014} \($0)" } ?? app.name
                if meetingTitle.isEmpty || meetingTitle == lastAutoTitle {
                    meetingTitle = autoTitle
                    lastAutoTitle = autoTitle
                }
            }

            Divider()

            // Title + actions
            VStack(spacing: 12) {
                TextField("Meeting title (optional)", text: $meetingTitle)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Cancel") {
                        onCancel()
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button("Start Recording") {
                        guard let app = selectedApp else { return }
                        let title = meetingTitle.isEmpty ? app.name : meetingTitle
                        onStartRecording(app.id, app.name, title)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedApp == nil)
                }
            }
            .padding()
        }
        .frame(width: 400, height: 400)
        .onAppear {
            apps = appsProvider.runningApps()
        }
    }

    /// Returns the title of the frontmost visible window owned by the given PID.
    private func frontWindowTitle(for pid: pid_t) -> String? {
        let options = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[CFString: Any]] else { return nil }
        return list
            .filter { ($0[kCGWindowOwnerPID] as? Int32) == pid }
            .compactMap { $0[kCGWindowName] as? String }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

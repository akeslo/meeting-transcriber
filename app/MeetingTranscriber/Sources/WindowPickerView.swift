import AppKit
import CoreGraphics
import SwiftUI

struct WindowInfo: Identifiable, Hashable {
    let id: CGWindowID
    let pid: pid_t
    let ownerName: String
    let title: String
    let icon: NSImage?

    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

protocol RunningWindowsProvider {
    @MainActor func runningWindows() -> [WindowInfo]
}

struct SystemRunningWindowsProvider: RunningWindowsProvider {
    @MainActor
    func runningWindows() -> [WindowInfo] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements], kCGNullWindowID,
        ) as? [[String: Any]] else {
            return []
        }

        var iconByPID: [pid_t: NSImage] = [:]
        for app in NSWorkspace.shared.runningApplications {
            if let icon = app.icon {
                iconByPID[app.processIdentifier] = icon
            }
        }

        return windowList.compactMap { window -> WindowInfo? in
            guard let ownerName = window["kCGWindowOwnerName"] as? String,
                  let title = window["kCGWindowName"] as? String,
                  !title.isEmpty,
                  let windowID = window["kCGWindowNumber"] as? CGWindowID,
                  let pid = window["kCGWindowOwnerPID"] as? Int32
            else { return nil }

            if let bounds = window["kCGWindowBounds"] as? [String: Any] {
                let width = bounds["Width"] as? CGFloat ?? 0
                let height = bounds["Height"] as? CGFloat ?? 0
                guard width >= 200, height >= 100 else { return nil }
            }

            return WindowInfo(
                id: windowID,
                pid: pid,
                ownerName: ownerName,
                title: title,
                icon: iconByPID[pid],
            )
        }
        .sorted {
            if $0.ownerName == $1.ownerName {
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return $0.ownerName.localizedCaseInsensitiveCompare($1.ownerName) == .orderedAscending
        }
    }
}

@MainActor
struct WindowPickerView: View {
    let windowsProvider: any RunningWindowsProvider
    let onStartRecording: (pid_t, String, String, Bool, Int) -> Void
    let onCancel: () -> Void

    @State private var windows: [WindowInfo] = []
    @State private var selectedWindow: WindowInfo?
    @State private var recordingTitle: String = ""
    @State private var includeMic: Bool = true
    @State private var numSpeakers: Int = 2

    init(
        windowsProvider: any RunningWindowsProvider = SystemRunningWindowsProvider(),
        initialNumSpeakers: Int = 2,
        onStartRecording: @escaping (pid_t, String, String, Bool, Int) -> Void,
        onCancel: @escaping () -> Void,
    ) {
        self.windowsProvider = windowsProvider
        self.onStartRecording = onStartRecording
        self.onCancel = onCancel
        _numSpeakers = State(initialValue: max(initialNumSpeakers, 0))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Record Window")
                    .font(.headline)
                Spacer()
                Button {
                    windows = windowsProvider.runningWindows()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Refresh")
            }
            .padding()

            Divider()

            List(windows, selection: $selectedWindow) { window in
                HStack(spacing: 8) {
                    if let icon = window.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 20, height: 20)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "macwindow")
                            .frame(width: 20, height: 20)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(window.title)
                            .lineLimit(1)
                        Text(window.ownerName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(window)
            }
            .frame(minHeight: 220)
            .overlay {
                if windows.isEmpty {
                    Text("No windows found. Screen Recording permission may be required.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .onChange(of: selectedWindow) { _, newWindow in
                if let w = newWindow {
                    recordingTitle = w.title
                }
            }

            Divider()

            VStack(spacing: 12) {
                TextField("Meeting title (optional)", text: $recordingTitle)
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
                    Button("Cancel") { onCancel() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Start Recording") {
                        guard let window = selectedWindow else { return }
                        let title = recordingTitle.isEmpty ? window.title : recordingTitle
                        onStartRecording(window.pid, window.ownerName, title, includeMic, numSpeakers)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedWindow == nil)
                    .help(selectedWindow == nil ? "Select a window to enable recording" : "")
                }
            }
            .padding()
        }
        .frame(width: 520, height: 460)
        .onAppear { windows = windowsProvider.runningWindows() }
    }
}

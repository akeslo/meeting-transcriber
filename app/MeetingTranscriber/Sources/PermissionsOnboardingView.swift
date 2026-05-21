import AVFoundation
import CoreGraphics
import SwiftUI
@preconcurrency import ApplicationServices

struct PermissionsOnboardingView: View {
    var onContinue: () -> Void

    @State private var screenRecording: PermissionStatus = .notDetermined
    @State private var microphone: PermissionStatus = .notDetermined
    @State private var accessibility: PermissionStatus = .notDetermined

    private let spaceIndigo = Color(red: 0.082, green: 0.114, blue: 0.208)

    private var requiredGranted: Bool {
        screenRecording == .healthy && microphone == .healthy
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: app icon + title + subtitle
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                Text("Welcome to Meeting Transcriber")
                    .font(.system(size: 20, weight: .bold))
                Text("A few permissions are needed before you get started.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)
            .padding(.horizontal, 24)

            // Permission rows
            VStack(spacing: 0) {
                permissionRow(
                    systemImage: "rectangle.on.rectangle",
                    name: "Screen Recording",
                    detail: "Required for meeting detection and app audio capture",
                    status: screenRecording,
                    optional: false,
                ) {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
                    )
                }
                Divider().padding(.leading, 56)
                permissionRow(
                    systemImage: "mic",
                    name: "Microphone",
                    detail: "Required to record your voice during meetings",
                    status: microphone,
                    optional: false,
                ) {
                    Task {
                        await AVCaptureDevice.requestAccess(for: .audio)
                        await refreshAll()
                    }
                }
                Divider().padding(.leading, 56)
                permissionRow(
                    systemImage: "accessibility",
                    name: "Accessibility",
                    detail: "Optional — enables mute detection and meeting naming",
                    status: accessibility,
                    optional: true,
                ) {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    )
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 24)

            // Continue
            Button(action: onContinue) {
                Text("Continue")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(requiredGranted ? spaceIndigo : Color.secondary)
            .disabled(!requiredGranted)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .frame(width: 460)
        .task { await refreshAll() }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            Task { await refreshAll() }
        }
    }

    // MARK: - Permission row

    @ViewBuilder
    private func permissionRow(
        systemImage: String,
        name: String,
        detail: String,
        status: PermissionStatus,
        optional: Bool,
        onGrant: @escaping () -> Void,
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(rowIconBg(status, optional: optional))
                    .frame(width: 36, height: 36)
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 13, weight: .medium))
                    if optional {
                        Text("Optional")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            rowAction(status: status, optional: optional, onGrant: onGrant)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func rowAction(
        status: PermissionStatus,
        optional: Bool,
        onGrant: @escaping () -> Void,
    ) -> some View {
        switch status {
        case .healthy:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 22))
        case .notDetermined, .denied, .broken:
            Button(status == .broken ? "Fix" : "Grant", action: onGrant)
                .buttonStyle(.borderedProminent)
                .tint(optional ? .orange : spaceIndigo)
                .controlSize(.small)
        }
    }

    private func rowIconBg(_ status: PermissionStatus, optional: Bool) -> Color {
        switch status {
        case .healthy:       return .green
        case .broken:        return .orange
        case .denied:        return optional ? .orange : .red
        case .notDetermined: return Color.secondary.opacity(0.6)
        }
    }

    // MARK: - Permission refresh

    @MainActor
    private func refreshAll() async {
        // Screen recording: synchronous, no dialog
        screenRecording = PermissionHealthCheck.checkScreenRecordingLive()

        // Microphone: sync status check only (requestAccess handled by Grant button)
        let micAuth = AVCaptureDevice.authorizationStatus(for: .audio)
        microphone = PermissionHealthCheck.checkMicrophone(
            authStatus: micAuth,
            probeSucceeds: micAuth == .authorized,
        )

        // Accessibility: synchronous
        accessibility = AXIsProcessTrusted() ? .healthy : .denied
    }
}

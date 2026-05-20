import Foundation

/// Filename constants for all files produced in a session folder.
enum RecordingFileSuffix {
    // Audio files
    static let mix = "audio_mix.wav"
    static let app = "audio_app.wav"
    static let mic = "audio_mic.wav"

    // Document files
    static let transcript = "transcript.md"
    static let protocol_ = "protocol.md"

    static let allAudio: [String] = [mix, app, mic]

    /// Strip a known audio suffix from a filename, returning (stem, suffix).
    /// Returns nil if filename doesn't match any known audio suffix.
    static func stripSuffix(from filename: String) -> (stem: String, suffix: String)? {
        for suffix in allAudio where filename == suffix || filename.hasSuffix("_\(suffix)") {
            if filename == suffix { return ("", suffix) }
            return (String(filename.dropLast(suffix.count + 1)), suffix)
        }
        return nil
    }
}

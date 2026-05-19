#if !APPSTORE

    import Foundation
    import os.log

    private let logger = Logger(subsystem: AppPaths.logSubsystem, category: "ClaudeCLIProtocolGenerator")

    /// Claude CLI implementation that generates protocols via subprocess.
    struct ClaudeCLIProtocolGenerator: ProtocolGenerating {
        let claudeBin: String
        let language: String

        static let timeoutSeconds: TimeInterval = 600

        /// Search paths for Claude CLI binaries.
        /// System-managed paths are listed first to prevent PATH hijacking via
        /// user-writable directories. ~/.local/bin and ~/.npm-global/bin are
        /// checked last as common Claude CLI install locations.
        static let searchPaths = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "\(NSHomeDirectory())/.local/bin",
            "\(NSHomeDirectory())/.npm-global/bin",
        ]

        // MARK: - ProtocolGenerating

        func generate(transcript: String, title _: String, diarized: Bool) async throws -> String {
            // The meeting transcript is wrapped in <transcript> tags so the LLM
            // can treat its content as untrusted user input distinct from the
            // system instructions. This reduces prompt-injection risk from
            // instruction-like phrasing in meeting content.
            let prompt = ProtocolGenerator.buildSystemPrompt(diarized: diarized, language: language)
                + "<transcript>\n" + transcript + "\n</transcript>"

            let process = Process()
            let resolvedBin = Self.resolveClaudePath(claudeBin)
            process.executableURL = URL(fileURLWithPath: resolvedBin)
            process.arguments = Self.buildSubprocessArgs(claudeBin: claudeBin, resolvedBin: resolvedBin)
            process.environment = Self.buildEnvironment(
                baseEnvironment: ProcessInfo.processInfo.environment,
                searchPaths: Self.searchPaths,
                resolvedBin: resolvedBin,
            )

            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // C5 fix: Set terminationHandler BEFORE process.run() to avoid race
            // where the process exits before the handler is installed.
            // AsyncStream buffers the yield, so even if the process exits before
            // we iterate, the value is not lost.
            let exitStream = AsyncStream<Void> { continuation in
                process.terminationHandler = { _ in
                    continuation.yield()
                    continuation.finish()
                }
            }

            do {
                try process.run()
            } catch {
                logger.error(
                    "claude_cli_not_found bin=\(self.claudeBin, privacy: .public) resolvedPath=\(resolvedBin, privacy: .public) error=\(error.localizedDescription, privacy: .public)",
                )
                throw ProtocolError.cliNotFound(claudeBin)
            }

            // C5 fix: Guard against process having already exited before we awaited.
            // If the process already exited, terminationHandler may have already fired,
            // but AsyncStream buffers the yield so we won't miss it.
            // No additional check needed — AsyncStream handles the race.

            // C6 fix: Write stdin in a detached task to avoid deadlock on large transcripts.
            // The pipe buffer is finite (~64KB); if the prompt exceeds it, a synchronous
            // write blocks until the reader drains — but we haven't started reading yet.
            let promptData = Data(prompt.utf8)
            logger.info("claude_cli_subprocess_start prompt_bytes=\(promptData.count, privacy: .public)")
            let stdinWriteTask = Task.detached {
                stdinPipe.fileHandleForWriting.write(promptData)
                stdinPipe.fileHandleForWriting.closeFile()
            }

            // Read stream-json output concurrently with stdin write
            let text = try await Self.readStreamJSON(from: stdoutPipe, process: process)

            // Ensure stdin write completes (should be done by now)
            _ = await stdinWriteTask.value

            // Read stderr in background to prevent pipe buffer issues
            async let stderrRead = Task.detached {
                stderrPipe.fileHandleForReading.readDataToEndOfFile()
            }.value

            // Await process exit via the stream installed before launch
            for await _ in exitStream {
                break
            }

            if process.terminationStatus != 0 {
                let stderrData = await stderrRead
                let stderrText = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                logger.error(
                    "claude_cli_failed exit=\(process.terminationStatus, privacy: .public) stderr=\(stderrText, privacy: .public)",
                )
                throw ProtocolError.cliFailed(Int(process.terminationStatus), stderrText)
            }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                logger.error("claude_cli_empty_response — subprocess exited 0 with empty output")
                throw ProtocolError.emptyProtocol
            }

            return trimmed
        }

        // MARK: - Stream JSON

        /// Parse Claude CLI stream-json output and accumulate text.
        private static func readStreamJSON(from pipe: Pipe, process: Process) async throws -> String {
            let handle = pipe.fileHandleForReading
            var parts: [String] = []
            let startTime = ProcessInfo.processInfo.systemUptime

            // Read line-by-line from stdout
            var buffer = Data()
            while true {
                // I1 fix: Wrap blocking availableData in Task.detached to avoid
                // blocking Swift's cooperative thread pool. availableData blocks
                // until data is available or EOF, which would starve other tasks.
                let chunk = await Task.detached { handle.availableData }.value
                if chunk.isEmpty { break } // EOF

                // Check timeout AFTER the blocking read returns so that a
                // stalled process can still be terminated (checking before
                // the read means process.terminate() is never reached when
                // availableData blocks indefinitely).
                if ProcessInfo.processInfo.systemUptime - startTime > timeoutSeconds {
                    let elapsed = ProcessInfo.processInfo.systemUptime - startTime
                    let elapsedStr = String(format: "%.1f", elapsed)
                    logger.error(
                        "claude_cli_timeout elapsed=\(elapsedStr, privacy: .public)s parts_received=\(parts.count, privacy: .public)",
                    )
                    process.terminate()
                    throw ProtocolError.timeout
                }

                buffer.append(chunk)

                // Process complete lines
                while let newlineRange = buffer.range(of: Data([0x0A])) {
                    let lineData = buffer[buffer.startIndex ..< newlineRange.lowerBound]
                    buffer.removeSubrange(buffer.startIndex ... newlineRange.lowerBound)

                    guard var line = String(data: lineData, encoding: .utf8) else { continue }
                    // Strip a leading \r so \r\n line endings don't corrupt JSON parsing.
                    if line.hasPrefix("\r") { line = String(line.dropFirst()) }
                    line = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !line.isEmpty else { continue }

                    if let text = parseStreamJSONLine(line) {
                        parts.append(text)
                    }
                }
            }

            return parts.joined()
        }

        /// Parse a single stream-json line and extract text content.
        static func parseStreamJSONLine(_ line: String) -> String? {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            // content_block_delta carries streaming text chunks
            if obj["type"] as? String == "content_block_delta",
               let delta = obj["delta"] as? [String: Any],
               delta["type"] as? String == "text_delta",
               let text = delta["text"] as? String {
                return text
            }

            // assistant message carries the final full text
            if obj["type"] as? String == "assistant",
               let message = obj["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for block in content {
                    if block["type"] as? String == "text",
                       let text = block["text"] as? String {
                        return text
                    }
                }
            }

            return nil
        }

        // MARK: - CLI Resolution

        /// Scan known install locations for executables starting with "claude".
        /// Always includes "claude" as a fallback even if not found.
        static func availableClaudeBinaries() -> [String] {
            let fm = FileManager.default
            var names = Set<String>()

            for dir in searchPaths {
                guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
                for entry in entries where entry.hasPrefix("claude") {
                    let full = "\(dir)/\(entry)"
                    if fm.isExecutableFile(atPath: full) {
                        names.insert(entry)
                    }
                }
            }

            names.insert("claude")
            return names.sorted()
        }

        /// Trusted prefixes for absolute-path resolution.
        /// Accepting arbitrary absolute paths verbatim would let a user
        /// (or a compromised settings store) point at any executable on disk.
        private static let trustedAbsolutePrefixes: [String] = [
            "/usr/local/bin/",
            "/opt/homebrew/bin/",
            "\(NSHomeDirectory())/.local/bin/",
            "\(NSHomeDirectory())/.npm-global/bin/",
            "/usr/bin/",
        ]

        /// Resolve the claude CLI binary path.
        /// App bundles have a restricted PATH, so check common install locations.
        static func resolveClaudePath(_ bin: String) -> String {
            // If already an absolute path, validate it against trusted prefixes.
            if bin.hasPrefix("/") {
                // Use resolvingSymlinksInPath() rather than standardizingPath so that
                // paths like `/opt/homebrew/bin/../../../tmp/evil` are fully resolved
                // before the prefix check, not just syntactically normalized.
                let canonical = URL(fileURLWithPath: bin).resolvingSymlinksInPath().path
                let isTrusted = trustedAbsolutePrefixes.contains(where: { canonical.hasPrefix($0) })
                guard isTrusted else {
                    logger.warning("Absolute claudeBin path '\(bin, privacy: .public)' is not under a trusted prefix — falling back to search paths")
                    // Fall through to search paths below
                    return searchPaths.map({ "\($0)/claude" })
                        .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
                        ?? "/usr/bin/env"
                }
                return canonical
            }

            for path in searchPaths.map({ "\($0)/\(bin)" })
                where FileManager.default.isExecutableFile(atPath: path) {
                let isNonStandard = !path.hasPrefix("/usr/") && !path.hasPrefix("/opt/homebrew/")
                if isNonStandard {
                    logger.warning("Claude CLI resolved from non-standard path: \(path, privacy: .public) — ensure only trusted binaries exist there")
                }
                return path
            }
            // Fallback: hope it's in PATH — only allowed for simple filenames
            // (no path separators, no spaces) so env(1) can't be used to run an
            // arbitrary path by injecting a slash-prefixed component into claudeBin.
            let isSafeFilename = !bin.contains("/") && !bin.contains(" ")
            if isSafeFilename {
                return "/usr/bin/env"
            }
            logger.warning("claudeBin '\(bin, privacy: .public)' contains path separators or spaces — not passing to env fallback")
            return searchPaths.map({ "\($0)/claude" })
                .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
                ?? "/usr/bin/env"
        }

        // MARK: - Pure subprocess builders

        /// Build the CLI argument vector. When `resolvedBin` is the
        /// `/usr/bin/env` fallback, prepend `claudeBin` so env can resolve
        /// it from PATH.
        static func buildSubprocessArgs(claudeBin: String, resolvedBin: String) -> [String] {
            var args = ["-p", "-", "--output-format", "stream-json", "--verbose", "--model", "sonnet"]
            if resolvedBin == "/usr/bin/env" {
                // Only insert claudeBin if it is a safe, simple filename — the
                // resolution guard above already prevents reaching this branch with
                // a path-separator-containing value, but guard again for clarity.
                let isSafeFilename = !claudeBin.contains("/") && !claudeBin.contains(" ")
                if isSafeFilename {
                    args.insert(claudeBin, at: 0)
                }
            }
            return args
        }

        /// Strip `CLAUDECODE` (avoid nested-session detection by the child
        /// CLI) and construct a minimal subprocess PATH consisting of
        /// well-known system directories plus the directory of the resolved
        /// binary only. User-writable directories (e.g. ~/.local/bin,
        /// ~/.npm-global/bin) are excluded to prevent PATH hijacking by
        /// child processes spawned by the Claude CLI.
        static func buildEnvironment(
            baseEnvironment: [String: String],
            searchPaths: [String],
            resolvedBin: String? = nil,
        ) -> [String: String] {
            var env = baseEnvironment
            env.removeValue(forKey: "CLAUDECODE")
            var pathComponents = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
            if let resolvedBin, resolvedBin != "/usr/bin/env" {
                let binDir = (resolvedBin as NSString).deletingLastPathComponent
                if !binDir.isEmpty, !pathComponents.contains(binDir) {
                    pathComponents.insert(binDir, at: 0)
                }
            }
            env["PATH"] = pathComponents.joined(separator: ":")
            return env
        }
    }

#endif

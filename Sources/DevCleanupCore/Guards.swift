import Foundation

/// Decides whether a finding must be left alone: recent, newer than `--older-than`, open files, or its owning app is running.
public struct Guards: Sendable {
    /// Anything modified within this many seconds of `now` is skipped.
    public static let recentWindow: TimeInterval = 3 * 3600

    /// The moment "recent" is measured against.
    public var now: Date
    /// Seconds from `--older-than`; `nil` means no filter.
    public var olderThan: TimeInterval?
    /// Names of currently running processes, e.g. "Xcode", "node".
    public var runningProcesses: Set<String>
    /// Absolute paths of files currently open.
    public var pathsWithOpenFiles: Set<String>

    /// Creates guards from the scan moment, the `--older-than` filter, and snapshots of live process and open-file state.
    public init(now: Date, olderThan: TimeInterval?, runningProcesses: Set<String>, pathsWithOpenFiles: Set<String>) {
        self.now = now
        self.olderThan = olderThan
        self.runningProcesses = runningProcesses
        self.pathsWithOpenFiles = pathsWithOpenFiles
    }

    /// First reason that applies, checked in this order: processRunning, recentlyModified, tooNew, openFiles. `nil` = safe.
    public func skipReason(path: String, lastModified: Date?, blockedBy: [String]) -> SkipReason? {
        if blockedBy.contains(where: { runningProcesses.contains($0) }) {
            return .processRunning
        }
        if let lastModified, now.timeIntervalSince(lastModified) < Self.recentWindow {
            return .recentlyModified
        }
        if let olderThan, let lastModified, now.timeIntervalSince(lastModified) < olderThan {
            return .tooNew
        }
        if pathsWithOpenFiles.contains(where: { $0 == path || $0.hasPrefix(path + "/") }) {
            return .openFiles
        }
        return nil
    }

    /// Names of running processes (`/bin/ps -axco comm`), trimmed, header line dropped. Empty set when `ps` fails.
    public static func runningProcessNames() -> Set<String> {
        parsePS(run("/bin/ps", arguments: ["-axco", "comm"]))
    }

    /// Absolute paths of open regular files under `roots` from one `/usr/sbin/lsof -nP -Fn -w` run. Empty set if lsof fails.
    public static func openFiles(under roots: [String]) -> Set<String> {
        parseLsof(run("/usr/sbin/lsof", arguments: ["-nP", "-Fn", "-w"], allowedExit: [0, 1]), roots: roots)
    }

    /// Parses "7d", "2w", "12h" into seconds; `nil` on bad input.
    public static func parseAge(_ text: String) -> TimeInterval? {
        guard text.count >= 2, let unit = text.last,
              let amount = Double(String(text.dropLast())), amount.isFinite, amount >= 0
        else { return nil }
        switch unit {
        case "h": return amount * 3600
        case "d": return amount * 86400
        case "w": return amount * 604800
        default: return nil
        }
    }

    /// One name per line of `ps -axco comm` output, first (header) line dropped.
    static func parsePS(_ text: String) -> Set<String> {
        var lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        lines.removeAll { $0.isEmpty }
        guard !lines.isEmpty else { return [] }
        lines.removeFirst()
        return Set(lines)
    }

    /// Paths from `lsof -Fn` output: each line starting with "n" carries one path, kept only when it is `root` itself or lies under it.
    static func parseLsof(_ text: String, roots: [String]) -> Set<String> {
        var open = Set<String>()
        for line in text.split(separator: "\n") {
            guard line.hasPrefix("n") else { continue }
            let file = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            guard !file.isEmpty else { continue }
            if roots.contains(where: { $0 == file || file.hasPrefix($0 + "/") }) {
                open.insert(file)
            }
        }
        return open
    }

    /// Runs `path` with `arguments` and returns its stdout, or an empty string when the launch fails or the exit status is not allowed.
    static func run(_ path: String, arguments: [String], allowedExit: Set<Int32> = [0]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ""
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard allowedExit.contains(process.terminationStatus) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

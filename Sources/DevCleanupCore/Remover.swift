import Foundation

/// One line of the deletion log.
public struct Removal: Codable, Sendable, Equatable {
    /// When the attempt happened.
    public var date: Date
    /// The `ruleID` of the finding that was freed.
    public var ruleID: String
    /// The path of the finding, exactly as it was found.
    public var path: String
    /// The bytes the finding claimed deleting it frees.
    public var bytes: Int64
    /// Whether the attempt succeeded.
    public var ok: Bool
    /// Why the attempt failed; nil when it succeeded.
    public var error: String?

    /// Creates one log line; `error` is nil for a successful attempt.
    public init(date: Date, ruleID: String, path: String, bytes: Int64, ok: Bool, error: String?) {
        self.date = date
        self.ruleID = ruleID
        self.path = path
        self.bytes = bytes
        self.ok = ok
        self.error = error
    }
}

/// Why `Remover.remove` refused or failed.
public enum RemoveError: Error, Equatable {
    /// The finding carries a skip reason and was never touched.
    case skipped
    /// The target does not live under the home directory.
    case outsideHome
    /// The target is fewer than two levels below home, too risky to delete.
    case tooShallow
    /// The finding's command exited with a non-zero status.
    case commandFailed(Int32)
    /// A file operation failed; the payload is its localized description.
    case io(String)
}

/// Frees one finding per its `Action`, refuses unsafe targets, and appends one JSON line per attempt to the log.
public final class Remover {
    /// Runs a command (argv) and returns its exit status; the default calls `/usr/bin/env`.
    public typealias Runner = ([String]) -> Int32

    /// The log file every attempt is appended to as one JSON line.
    public let logURL: URL

    /// The home directory every target must live under.
    private let env: Env
    /// Runs the commands of `.command` findings.
    private let runner: Runner
    /// Exit status of every argv this instance has already run, so each runs once.
    private var ranCommands: [[String]: Int32] = [:]

    /// Creates a remover; the default log is `home`/Library/Logs/mac-dev-cleanup/deletions.log.
    public init(env: Env, logURL: URL? = nil, runner: Runner? = nil) {
        self.env = env
        self.logURL = logURL ?? env.home.appendingPathComponent("Library/Logs/mac-dev-cleanup/deletions.log")
        self.runner = runner ?? Self.defaultRunner
    }

    /// Frees `finding` and returns the Removal that was logged.
    /// Refusals (.skipped, .outsideHome, .tooShallow) throw unlogged; failures log ok = false first, then throw.
    @discardableResult
    public func remove(_ finding: Finding) throws -> Removal {
        guard finding.skipped == nil else { throw RemoveError.skipped }
        guard finding.path.hasPrefix("/") else { throw RemoveError.outsideHome }
        // Resolve symlinks in home and in every folder above the target, so a linked folder
        // cannot lead outside home; the last component stays as is, so a symlink is removed as a link.
        let homePath = Self.withoutTrailingSlash(Self.resolved(env.home.path))
        let given = URL(fileURLWithPath: finding.path).standardizedFileURL
        let target = URL(fileURLWithPath: Self.resolved(given.deletingLastPathComponent().path))
            .appendingPathComponent(given.lastPathComponent)
        let path = Self.withoutTrailingSlash(target.path)
        guard path.hasPrefix(homePath + "/") else { throw RemoveError.outsideHome }
        if !Self.isCommand(finding.action) {
            let belowHome = path.dropFirst(homePath.count + 1)
            guard belowHome.split(separator: "/").count >= 2 else { throw RemoveError.tooShallow }
        }
        if case .command(let argv) = finding.action, argv.isEmpty { throw RemoveError.commandFailed(127) }
        // Product rule 5: nothing is deleted unless its log line can be written.
        try prepareLog()
        switch finding.action {
        case .remove:
            try deleting(finding) { try FileManager.default.removeItem(at: target) }
        case .removeContents:
            try deleting(finding) {
                for child in try FileManager.default.contentsOfDirectory(at: target, includingPropertiesForKeys: nil) {
                    try FileManager.default.removeItem(at: child)
                }
            }
        case .command(let argv):
            let status = ranCommands[argv] ?? runner(argv)
            ranCommands[argv] = status
            if status != 0 {
                try logged(finding, ok: false, error: "command exited with status \(status)")
                throw RemoveError.commandFailed(status)
            }
        }
        return try logged(finding, ok: true, error: nil)
    }

    /// Performs one file operation; when it throws, logs a failed attempt and throws `.io`.
    private func deleting(_ finding: Finding, _ operation: () throws -> Void) throws {
        do {
            try operation()
        } catch {
            let message = error.localizedDescription
            try logged(finding, ok: false, error: message)
            throw RemoveError.io(message)
        }
    }

    /// Writes the log line describing `finding`'s outcome and returns it.
    @discardableResult
    private func logged(_ finding: Finding, ok: Bool, error: String?) throws -> Removal {
        let line = Removal(date: Date(), ruleID: finding.ruleID, path: finding.path,
                           bytes: finding.bytes, ok: ok, error: error)
        try append(line)
        return line
    }

    /// Creates the log folder and file when missing and checks the file opens for writing.
    private func prepareLog() throws {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw RemoveError.io(error.localizedDescription)
        }
        if !fm.fileExists(atPath: logURL.path), !fm.createFile(atPath: logURL.path, contents: nil) {
            throw RemoveError.io("cannot create log file at \(logURL.path)")
        }
        guard fm.isWritableFile(atPath: logURL.path) else {
            throw RemoveError.io("cannot write log file at \(logURL.path)")
        }
    }

    /// Appends `line` to `logURL` as one JSON line; `prepareLog` has created the file.
    private func append(_ line: Removal) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        do {
            var data = try encoder.encode(line)
            data.append(0x0A)
            let fd = open(logURL.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
            guard fd >= 0 else { throw RemoveError.io("cannot open log file at \(logURL.path)") }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            try handle.write(contentsOf: data)
        } catch let error as RemoveError {
            throw error
        } catch {
            throw RemoveError.io(error.localizedDescription)
        }
    }

    /// `path` with every symlink resolved; the deepest existing folder is resolved and
    /// the missing rest is appended unchanged.
    private static func resolved(_ path: String) -> String {
        var existing = URL(fileURLWithPath: path)
        var missing: [String] = []
        while existing.path != "/" {
            if let real = realpath(existing.path, nil) {
                defer { free(real) }
                return missing.reversed().reduce(URL(fileURLWithPath: String(cString: real))) {
                    $0.appendingPathComponent($1)
                }.path
            }
            missing.append(existing.lastPathComponent)
            existing.deleteLastPathComponent()
        }
        return path
    }

    /// True when `action` runs a command instead of deleting files.
    private static func isCommand(_ action: Action) -> Bool {
        if case .command = action { return true }
        return false
    }

    /// `path` without trailing slashes; a lone "/" stays as it is.
    private static func withoutTrailingSlash(_ path: String) -> String {
        var trimmed = path
        while trimmed.count > 1 && trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed
    }

    /// Runs `/usr/bin/env` + argv, discarding stdout and stderr; a launch failure reports 127.
    private static func defaultRunner(_ argv: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = argv
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return 127
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

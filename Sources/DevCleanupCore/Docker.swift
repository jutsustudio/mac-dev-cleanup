import Darwin
import Foundation

/// Reports what `docker system prune -af` would free on this machine.
public enum Docker {
    /// Runs argv and returns (exit status, stdout); a parameter so tests can fake docker.
    public typealias Runner = @Sendable ([String]) -> (Int32, String)

    /// Builds a Runner: `/usr/bin/env` + argv, stdin/stderr discarded, stdout to
    /// a temp file. After `timeout` seconds: SIGTERM, 1 s grace, then SIGKILL; status is then -1.
    public static func makeRunner(timeout: TimeInterval) -> Runner {
        { argv in
            let out = FileManager.default.temporaryDirectory
                .appendingPathComponent("mdc-docker-\(UUID().uuidString)")
            guard FileManager.default.createFile(atPath: out.path, contents: nil),
                  let handle = try? FileHandle(forWritingTo: out)
            else { return (-1, "") }
            defer { try? FileManager.default.removeItem(at: out) }
            defer { try? handle.close() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = argv
            process.standardOutput = handle
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return (-1, "")
            }
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            let timedOut = process.isRunning
            if timedOut {
                process.terminate()
                let killDeadline = Date().addingTimeInterval(1)
                while process.isRunning, Date() < killDeadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
            process.waitUntilExit()
            let text = (try? String(contentsOf: out, encoding: .utf8)) ?? ""
            if timedOut || process.terminationReason == .uncaughtSignal {
                return (-1, text)
            }
            return (process.terminationStatus, text)
        }
    }

    /// The runner `finding` uses by default; same behavior with a 10-second timeout.
    public static let defaultRunner: Runner = makeRunner(timeout: 10)

    /// One Finding with the bytes `docker system prune -af` would free, or nil
    /// when docker is absent, not running, or reports nothing reclaimable.
    public static func finding(env: Env, runner: Runner = defaultRunner) -> Finding? {
        let (status, output) = runner(["docker", "system", "df", "--format", "{{json .}}"])
        guard status == 0 else { return nil }
        let counted: Set<String> = ["Images", "Containers", "Build Cache"]
        // Docker's own reclaimable estimate: `prune -af` can free more (images
        // used only by stopped containers) or less (shared layers), and Docker
        // Desktop's disk image shrinks only after Docker trims it.
        var total: Int64 = 0
        for line in output.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty,
                  let data = text.data(using: .utf8),
                  let fields = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let type = fields["Type"],
                  counted.contains(type),
                  let reclaimable = fields["Reclaimable"],
                  let bytes = parseSize(reclaimable)
            else { continue }
            total += bytes
        }
        guard total > 0 else { return nil }
        return Finding(
            ruleID: "docker-prune",
            title: "Docker unused images, stopped containers, build cache",
            group: .docker,
            path: env.inHome(".docker").path,
            bytes: total,
            lastModified: nil,
            cost: .lost("stopped containers' data is deleted; local images rebuild, others pull again"),
            action: .command(["docker", "system", "prune", "-af"])
        )
    }

    /// "1.234GB" → 1_234_000_000 in docker's decimal units; a "(40%)" suffix
    /// is ignored. nil on anything but a number followed by B, kB, MB, GB, TB or PB.
    static func parseSize(_ text: String) -> Int64? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let openParen = trimmed.firstIndex(of: "(") {
            trimmed = String(trimmed[..<openParen]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let factors: [(String, Double)] = [
            ("PB", 1_000_000_000_000_000),
            ("TB", 1_000_000_000_000),
            ("GB", 1_000_000_000),
            ("MB", 1_000_000),
            ("kB", 1_000),
            ("B", 1),
        ]
        for (unit, factor) in factors where trimmed.hasSuffix(unit) {
            let number = String(trimmed.dropLast(unit.count)).trimmingCharacters(in: .whitespaces)
            guard let value = Double(number), value.isFinite, value >= 0 else { return nil }
            return Int64(exactly: (value * factor).rounded())
        }
        return nil
    }
}

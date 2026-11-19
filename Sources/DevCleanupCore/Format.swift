import Foundation

/// Turns findings into a readable table and stable JSON.
public enum Format {

    /// Decimal units like Finder: 0 B, 999 B, 1.2 kB, 34.5 MB, 1.23 GB (ByteCountFormatter .file-style rounding).
    public static func bytes(_ n: Int64) -> String {
        guard n >= 1_000 else { return "\(n) B" }
        let units = ["kB", "MB", "GB", "TB", "PB", "EB"]
        var divisor = 1_000.0
        var unitIndex = 0
        while Double(n) / divisor >= 1_000 && unitIndex < units.count - 1 {
            divisor *= 1_000
            unitIndex += 1
        }
        var value = Double(n) / divisor
        var rounded = roundedForDisplay(value)
        while rounded >= 1_000 && unitIndex < units.count - 1 {
            value /= 1_000
            unitIndex += 1
            rounded = roundedForDisplay(value)
        }
        var text = String(format: value < 10 ? "%.2f" : "%.1f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return "\(text) \(units[unitIndex])"
    }

    /// Path with the home prefix replaced by "~".
    public static func shortPath(_ path: String, home: String) -> String {
        guard path.hasPrefix(home) else { return path }
        let rest = path.dropFirst(home.count)
        guard rest.isEmpty || rest.hasPrefix("/") else { return path }
        return "~" + rest
    }

    /// Text table sorted by bytes descending, then path; columns SIZE (right-aligned), WHAT, PATH and COST.
    /// Skipped rows end with "  [skipped: <reason>]"; the last line is "Total: <non-skipped bytes> in <n> items (<m> skipped)"; empty input returns "Nothing to clean.\n".
    public static func table(_ findings: [Finding], home: String) -> String {
        guard !findings.isEmpty else { return "Nothing to clean.\n" }
        let rows = sorted(collapsed(findings))
        let sizes = rows.map { bytes($0.finding.bytes) }
        let paths = rows.map { row in
            let path = clipped(shortPath(row.finding.path, home: home))
            return row.count > 1 ? "\(path)  (\(row.count) items)" : path
        }
        let sizeWidth = max("SIZE".count, sizes.map(\.count).max() ?? 0)
        let whatWidth = max("WHAT".count, rows.map { $0.finding.title.count }.max() ?? 0)
        let pathWidth = max("PATH".count, paths.map(\.count).max() ?? 0)
        var lines = [padLeft("SIZE", sizeWidth) + "  " + padRight("WHAT", whatWidth)
                        + "  " + padRight("PATH", pathWidth) + "  COST"]
        for (index, group) in rows.enumerated() {
            let row = group.finding
            var line = padLeft(sizes[index], sizeWidth) + "  " + padRight(row.title, whatWidth)
                + "  " + padRight(paths[index], pathWidth) + "  " + costText(row)
            if let reason = row.skipped {
                line += "  [skipped: \(reason.rawValue)]"
            }
            lines.append(line)
        }
        let cleaned = findings.filter { $0.skipped == nil }
        lines.append("Total: \(bytes(cleanableBytes(findings))) in \(cleaned.count) items "
            + "(\(findings.count - cleaned.count) skipped)")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Pretty-printed, sorted-keys JSON: {"findings":[...], "totalBytes": <non-skipped sum>}, dates ISO 8601, same sort as table.
    public static func json(_ findings: [Finding]) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(Payload(findings: sorted(findings), totalBytes: cleanableBytes(findings)))
        return String(decoding: data, as: UTF8.self)
    }

    /// The JSON envelope: every finding, plus the bytes cleaning would actually free.
    private struct Payload: Codable {
        var findings: [Finding]
        var totalBytes: Int64
    }

    /// Findings under this size are merged per rule in the table, so hundreds of tiny items fit on one line.
    public static let smallItemBytes: Int64 = 10_000_000

    /// Small findings of one rule (and one skip reason) merged into a single row: summed bytes,
    /// the folder they share as the path, and how many there were. Larger findings stay one row each.
    private static func collapsed(_ findings: [Finding]) -> [(finding: Finding, count: Int)] {
        var rows: [(finding: Finding, count: Int)] = []
        var small: [String: [Finding]] = [:]
        for finding in findings {
            if finding.bytes < smallItemBytes {
                small[finding.ruleID + "|" + (finding.skipped?.rawValue ?? ""), default: []].append(finding)
            } else {
                rows.append((finding, 1))
            }
        }
        for members in small.values {
            guard members.count > 1 else { rows.append((members[0], 1)); continue }
            var merged = members[0]
            merged.bytes = members.reduce(0) { $0 + $1.bytes }
            merged.path = commonFolder(members.map(\.path))
            rows.append((merged, members.count))
        }
        return rows
    }

    /// The deepest folder that contains every path.
    private static func commonFolder(_ paths: [String]) -> String {
        var common = paths[0].split(separator: "/", omittingEmptySubsequences: false).dropLast()
        for path in paths.dropFirst() {
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            var shared = 0
            while shared < common.count && shared < parts.count - 1 && common[common.startIndex + shared] == parts[shared] {
                shared += 1
            }
            common = common.prefix(shared)
        }
        let folder = common.joined(separator: "/")
        return folder.isEmpty ? "/" : folder
    }

    /// Bytes descending, then path ascending — the order shared by `table` and `json`.
    private static func sorted(_ findings: [Finding]) -> [Finding] {
        findings.sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.path < $1.path }
    }

    private static func sorted(_ rows: [(finding: Finding, count: Int)]) -> [(finding: Finding, count: Int)] {
        rows.sorted { $0.finding.bytes != $1.finding.bytes ? $0.finding.bytes > $1.finding.bytes : $0.finding.path < $1.finding.path }
    }

    /// Sum of the bytes of the non-skipped findings: what cleaning would actually free.
    private static func cleanableBytes(_ findings: [Finding]) -> Int64 {
        findings.filter { $0.skipped == nil }.reduce(0) { $0 + $1.bytes }
    }

    /// "…" plus the last 59 characters, so a path cell never exceeds 60 characters.
    private static func clipped(_ path: String) -> String {
        path.count > 60 ? "…" + path.suffix(59) : path
    }

    /// The cost with its kind prefixed, e.g. "rebuild: next Xcode build is slower".
    private static func costText(_ finding: Finding) -> String {
        switch finding.cost {
        case .rebuild(let text): "rebuild: \(text)"
        case .redownload(let text): "re-download: \(text)"
        case .lost(let text): "lost: \(text)"
        }
    }

    /// `value` as the table shows it: two decimals below 10, one above.
    private static func roundedForDisplay(_ value: Double) -> Double {
        let scale = value < 10 ? 100.0 : 10.0
        return (value * scale).rounded() / scale
    }

    /// `text` right-aligned to `width` characters.
    private static func padLeft(_ text: String, _ width: Int) -> String {
        String(repeating: " ", count: max(0, width - text.count)) + text
    }

    /// `text` left-aligned to `width` characters.
    private static func padRight(_ text: String, _ width: Int) -> String {
        text + String(repeating: " ", count: max(0, width - text.count))
    }
}

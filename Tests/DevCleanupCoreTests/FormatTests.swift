import Foundation
import Testing
@testable import DevCleanupCore

@Suite struct FormatTests {

    @Test func bytesFormatsLikeFinder() {
        #expect(Format.bytes(0) == "0 B")
        #expect(Format.bytes(999) == "999 B")
        #expect(Format.bytes(1_200) == "1.2 kB")
        #expect(Format.bytes(34_500_000) == "34.5 MB")
        #expect(Format.bytes(1_230_000_000) == "1.23 GB")
    }

    @Test func shortPathReplacesTheHomePrefix() throws {
        let home = try makeHome([])
        defer { try? FileManager.default.removeItem(atPath: home) }
        #expect(Format.shortPath(home + "/Library/Caches/pnpm", home: home) == "~/Library/Caches/pnpm")
        #expect(Format.shortPath(home, home: home) == "~")
        #expect(Format.shortPath("/Applications/Xcode.app", home: home) == "/Applications/Xcode.app")
        #expect(Format.shortPath(home + "y/Caches", home: home) == home + "y/Caches")
    }

    @Test func tableIsEmptyWithoutFindings() {
        #expect(Format.table([], home: "/Users/nobody") == "Nothing to clean.\n")
    }

    @Test func tableSortsByBytesThenPath() throws {
        let home = try makeHome(["Library/Caches/pnpm", "Library/Developer/Xcode/DerivedData", "Library/Logs"])
        defer { try? FileManager.default.removeItem(atPath: home) }
        let derived = finding("derived", group: .xcode, path: home + "/Library/Developer/Xcode/DerivedData",
                               bytes: 2_000, cost: .rebuild("next Xcode build is slower"))
        let pnpm = finding("pnpm", group: .node, path: home + "/Library/Caches/pnpm", bytes: 2_000,
                           cost: .redownload("re-downloaded on next `npm install`"))
        let logs = finding("logs", group: .xcode, path: home + "/Library/Logs", bytes: 34_500_000,
                           cost: .lost("old diagnostic logs"))
        let lines = Format.table([derived, pnpm, logs], home: home).split(separator: "\n").map(String.init)
        #expect(lines[0].hasSuffix("COST"))
        #expect(lines[1].contains("~/Library/Logs"))
        #expect(lines[2].contains("~/Library/Caches/pnpm"))
        #expect(lines[3].contains("~/Library/Developer/Xcode/DerivedData"))
    }

    @Test func tableMarksSkippedAndExcludesThemFromTheTotal() throws {
        let home = try makeHome([".gradle/caches", "Library/Caches/pnpm", "Library/Developer/Xcode/DerivedData"])
        defer { try? FileManager.default.removeItem(atPath: home) }
        let derived = finding("derived", group: .xcode, path: home + "/Library/Developer/Xcode/DerivedData",
                              bytes: 34_500_000, cost: .rebuild("next Xcode build is slower"),
                              skipped: .recentlyModified)
        let pnpm = finding("pnpm", group: .node, path: home + "/Library/Caches/pnpm", bytes: 2_000,
                           cost: .redownload("re-downloaded on next `npm install`"))
        let gradle = finding("gradle", group: .jvm, path: home + "/.gradle/caches", bytes: 1_200,
                             cost: .redownload("re-downloaded on next `gradle` build"))
        let lines = Format.table([pnpm, derived, gradle], home: home).split(separator: "\n").map(String.init)
        #expect(lines[1].hasSuffix("  [skipped: modified in the last 3 hours]"))
        #expect(!lines[2].contains("[skipped"))
        #expect(!lines[3].contains("[skipped"))
        #expect(lines[4] == "Total: \(Format.bytes(3_200)) in 2 items (1 skipped)")
    }

    @Test func tableTruncatesPathsLongerThan60Characters() throws {
        let sixty = String(repeating: "d", count: 43)  // "~" + "/Library/Caches/" + 43 = 60 characters, kept whole
        let seventy = String(repeating: "d", count: 70)  // truncated to "…" plus the last 59 characters
        let home = try makeHome(["Library/Caches/\(sixty)", "Library/Logs/\(seventy)"])
        defer { try? FileManager.default.removeItem(atPath: home) }
        let table = Format.table([finding("sixty", group: .editors, path: home + "/Library/Caches/\(sixty)",
                                          bytes: 1, cost: .lost("nothing worth keeping")),
                                  finding("seventy", group: .editors, path: home + "/Library/Logs/\(seventy)",
                                          bytes: 2, cost: .lost("nothing worth keeping"))],
                                 home: home)
        #expect(table.contains("…" + String(repeating: "d", count: 59)))
        #expect(!table.contains(String(repeating: "d", count: 60)))
        #expect(table.contains("~/Library/Caches/\(sixty)"))
    }

    @Test func jsonRoundTripsThroughTheDecoder() throws {
        let home = try makeHome([".npm", "Library/Caches/pnpm", "Library/Developer/Xcode/DerivedData"])
        defer { try? FileManager.default.removeItem(atPath: home) }
        let pnpm = finding("pnpm", group: .node, path: home + "/Library/Caches/pnpm", bytes: 1_200,
                           cost: .redownload("re-downloaded on next `npm install`"), action: .removeContents,
                           lastModified: Date(timeIntervalSince1970: 1_700_000_123))
        let derived = finding("derived", group: .xcode, path: home + "/Library/Developer/Xcode/DerivedData",
                              bytes: 1_200, cost: .rebuild("next Xcode build is slower"),
                              action: .command(["xcrun", "simctl", "delete", "unavailable"]), lastModified: nil,
                              skipped: .processRunning)
        let npm = finding("npm", group: .node, path: home + "/.npm", bytes: 34_500_000,
                          cost: .lost("old npm cache contents"))
        let text = try Format.json([pnpm, derived, npm])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(Payload.self, from: Data(text.utf8))
        #expect(payload.findings == [npm, pnpm, derived])
        #expect(payload.totalBytes == 34_500_000 + 1_200)
        #expect(text.contains("\n"))
        if let findingsKey = text.range(of: "\"findings\""), let totalKey = text.range(of: "\"totalBytes\"") {
            #expect(findingsKey.lowerBound < totalKey.lowerBound)
        } else {
            Issue.record("json is missing the findings or totalBytes key")
        }
    }
}

/// The JSON envelope `Format.json` produces, decoded back.
private struct Payload: Codable {
    var findings: [Finding]
    var totalBytes: Int64
}

/// A finding under test; `id` doubles as the rule ID.
private func finding(_ id: String, group: Group, path: String, bytes: Int64, cost: Cost,
                     action: Action = .remove, lastModified: Date? = Date(timeIntervalSince1970: 1_700_000_000),
                     skipped: SkipReason? = nil) -> Finding {
    Finding(ruleID: id, title: "\(id) cache", group: group, path: path, bytes: bytes,
            lastModified: lastModified, cost: cost, action: action, skipped: skipped)
}

/// Creates a throwaway fake home folder with `subdirs` inside and returns its path; the caller deletes it.
private func makeHome(_ subdirs: [String]) throws -> String {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    for sub in subdirs {
        try FileManager.default.createDirectory(atPath: root.path + "/" + sub, withIntermediateDirectories: true)
    }
    return root.path
}

@Test func tableAndJSONSpellOutCostsAndDates() throws {
    func item(_ path: String, _ bytes: Int64, _ cost: Cost) -> Finding {
        Finding(ruleID: path, title: "t", group: .node, path: "/Users/al/" + path, bytes: bytes,
                lastModified: Date(timeIntervalSince1970: 1_700_000_123), cost: cost, action: .remove)
    }
    let findings = [item("a", 3_000, .rebuild("slower build")), item("b", 2_000, .redownload("fetched again")),
                    item("c", 1_000, .lost("gone"))]
    let rows = Format.table(findings, home: "/Users/al").split(separator: "\n").map(String.init)
    #expect(rows[1].hasSuffix("  rebuild: slower build"))
    #expect(rows[2].hasSuffix("  re-download: fetched again"))
    #expect(rows[3].hasSuffix("  lost: gone"))
    #expect(rows[1].contains("~/a"))
    #expect(Format.shortPath("/Users/alice/x", home: "/Users/al") == "/Users/alice/x")
    let json = try Format.json(findings)
    #expect(json.contains("\"lastModified\" : \"2023-11-14T22:15:23Z\""))
}

@Test func smallItemsOfOneRuleShareOneRow() {
    func small(_ name: String, _ bytes: Int64, skipped: SkipReason? = nil) -> Finding {
        Finding(ruleID: "history", title: "File history", group: .agents, path: "/Users/al/.claude/history/" + name,
                bytes: bytes, lastModified: nil, cost: .lost("undo"), action: .remove, skipped: skipped)
    }
    let big = Finding(ruleID: "history", title: "File history", group: .agents, path: "/Users/al/.claude/history/big",
                      bytes: 50_000_000, lastModified: nil, cost: .lost("undo"), action: .remove)
    let rows = Format.table([small("a", 4_000), small("b", 6_000), small("c", 1_000, skipped: .openFiles), big],
                            home: "/Users/al").split(separator: "\n").map(String.init)
    #expect(rows.count == 5)
    #expect(rows[1].contains("~/.claude/history/big"))
    #expect(rows[2].contains("10 kB") && rows[2].contains("~/.claude/history  (2 items)"))
    #expect(rows[3].contains("~/.claude/history/c") && rows[3].contains("[skipped: files are open]"))
    #expect(rows[4] == "Total: 50 MB in 3 items (1 skipped)")
}

@Test func jsonUsesFlatCostAndActionObjects() throws {
    let finding = Finding(ruleID: "sim", title: "Simulators", group: .xcode, path: "/Users/al/x", bytes: 1,
                          lastModified: nil, cost: .lost("gone"), action: .command(["xcrun", "simctl"]))
    let json = try Format.json([finding])
    #expect(json.contains("\"kind\" : \"lost\""))
    #expect(json.contains("\"note\" : \"gone\""))
    #expect(json.contains("\"kind\" : \"command\""))
    #expect(!json.contains("_0"))
}

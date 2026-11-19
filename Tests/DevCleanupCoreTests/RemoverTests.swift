import Foundation
import Testing
@testable import DevCleanupCore

@Suite struct RemoverTests {
    @Test func removeDeletesAFolder() throws {
        let root = try makeRemoverFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let cache = home.appendingPathComponent(".npm/_cacache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: cache.appendingPathComponent("entry.json"))
        let remover = Remover(env: Env(home: home), logURL: root.appendingPathComponent("deletions.log"))
        let line = try remover.remove(makeFinding(cache.path))
        #expect(!FileManager.default.fileExists(atPath: cache.path))
        #expect(line.ok)
        #expect(line.ruleID == "rule")
        #expect(line.path == cache.path)
        #expect(line.bytes == 123)
        #expect(line.error == nil)
    }

    @Test func removeContentsEmptiesTheFolderButKeepsIt() throws {
        let root = try makeRemoverFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let cache = home.appendingPathComponent(".npm/_cacache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache.appendingPathComponent("content-v2", isDirectory: true),
                                               withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: cache.appendingPathComponent("index.json"))
        try Data("{}".utf8).write(to: cache.appendingPathComponent(".hidden.json"))
        let remover = Remover(env: Env(home: home), logURL: root.appendingPathComponent("deletions.log"))
        try remover.remove(makeFinding(cache.path, action: .removeContents))
        #expect(FileManager.default.fileExists(atPath: cache.path))
        #expect(try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil).isEmpty)
    }

    @Test func skippedFindingThrowsAndTouchesNothing() throws {
        let root = try makeRemoverFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let cache = home.appendingPathComponent(".npm/_cacache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let log = root.appendingPathComponent("deletions.log")
        let remover = Remover(env: Env(home: home), logURL: log)
        #expect(throws: RemoveError.skipped) {
            try remover.remove(makeFinding(cache.path, skipped: .recentlyModified))
        }
        #expect(FileManager.default.fileExists(atPath: cache.path))
        #expect(!FileManager.default.fileExists(atPath: log.path))
    }

    @Test func outsideHomeThrowsAndTouchesNothing() throws {
        let root = try makeRemoverFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let log = root.appendingPathComponent("deletions.log")
        let remover = Remover(env: Env(home: home), logURL: log)
        #expect(throws: RemoveError.outsideHome) { try remover.remove(makeFinding("/tmp/x")) }
        #expect(throws: RemoveError.outsideHome) {
            try remover.remove(makeFinding("/tmp/x", action: .command(["tool", "clean"])))
        }
        #expect(!FileManager.default.fileExists(atPath: log.path))
    }

    @Test func dotDotEscapeOutsideHomeLeavesTargetIntact() throws {
        let root = try makeRemoverFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let etc = root.appendingPathComponent("etc", isDirectory: true)
        try FileManager.default.createDirectory(at: etc, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: etc.appendingPathComponent("config"))
        let log = root.appendingPathComponent("deletions.log")
        let remover = Remover(env: Env(home: home), logURL: log)
        #expect(throws: RemoveError.outsideHome) {
            try remover.remove(makeFinding(home.path + "/a/../../etc"))
        }
        #expect(FileManager.default.fileExists(atPath: etc.appendingPathComponent("config").path))
        #expect(!FileManager.default.fileExists(atPath: log.path))
    }

    @Test func tooShallowThrowsAndTouchesNothing() throws {
        let root = try makeRemoverFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let npm = home.appendingPathComponent(".npm", isDirectory: true)
        try FileManager.default.createDirectory(at: npm, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: npm.appendingPathComponent("package.json"))
        let log = root.appendingPathComponent("deletions.log")
        let remover = Remover(env: Env(home: home), logURL: log)
        #expect(throws: RemoveError.tooShallow) { try remover.remove(makeFinding(npm.path)) }
        #expect(FileManager.default.fileExists(atPath: npm.path))
        #expect(FileManager.default.fileExists(atPath: npm.appendingPathComponent("package.json").path))
        #expect(!FileManager.default.fileExists(atPath: log.path))
    }

    @Test func commandRunsOncePerDistinctArgvPerRemover() throws {
        let root = try makeRemoverFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let log = root.appendingPathComponent("deletions.log")
        let runs = Counter()
        let target = home.appendingPathComponent("Library/Developer/CoreSimulator", isDirectory: true)
        let simctl = ["xcrun", "simctl", "delete", "unavailable"]
        let remover = Remover(env: Env(home: home), logURL: log, runner: { _ in runs.count += 1; return 0 })
        try remover.remove(makeFinding(target.path, action: .command(simctl)))
        try remover.remove(makeFinding(target.path, action: .command(simctl)))
        #expect(runs.count == 1)
        try remover.remove(makeFinding(target.path, action: .command(["brew", "cleanup"])))
        #expect(runs.count == 2)
        let secondRemover = Remover(env: Env(home: home), logURL: log, runner: { _ in runs.count += 1; return 0 })
        try secondRemover.remove(makeFinding(target.path, action: .command(simctl)))
        #expect(runs.count == 3)
        let lines = try readRemovalLog(log)
        #expect(lines.count == 4)
        #expect(lines.allSatisfy { $0.ok })
    }

    @Test func commandSkipsTheDepthCheck() throws {
        let root = try makeRemoverFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let log = root.appendingPathComponent("deletions.log")
        let remover = Remover(env: Env(home: home), logURL: log, runner: { _ in 0 })
        try remover.remove(makeFinding(home.path + "/Library", action: .command(["tool", "clean"])))
        let lines = try readRemovalLog(log)
        #expect(lines.count == 1)
        #expect(lines[0].ok)
    }

    @Test func commandFailureThrowsAndLogsNotOk() throws {
        let root = try makeRemoverFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let log = root.appendingPathComponent("deletions.log")
        let remover = Remover(env: Env(home: home), logURL: log, runner: { _ in 3 })
        let target = home.appendingPathComponent("Library/Developer/CoreSimulator", isDirectory: true)
        #expect(throws: RemoveError.commandFailed(3)) {
            try remover.remove(makeFinding(target.path, action: .command(["xcrun", "simctl", "delete", "unavailable"])))
        }
        let lines = try readRemovalLog(log)
        #expect(lines.count == 1)
        #expect(!lines[0].ok)
        #expect(lines[0].error != nil)
    }

    @Test func removeMissingTargetThrowsIOAndLogsNotOk() throws {
        let root = try makeRemoverFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let log = root.appendingPathComponent("deletions.log")
        let remover = Remover(env: Env(home: home), logURL: log)
        let missing = home.appendingPathComponent("Library/Caches/ghost", isDirectory: true).path
        #expect(throws: RemoveError.self) { try remover.remove(makeFinding(missing)) }
        let lines = try readRemovalLog(log)
        #expect(lines.count == 1)
        #expect(!lines[0].ok)
        #expect(lines[0].error != nil)
    }

    @Test func logHoldsOneDecodableLinePerAttempt() throws {
        let root = try makeRemoverFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let cache = home.appendingPathComponent(".npm/_cacache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let log = root.appendingPathComponent("logs/nested/deletions.log")
        let remover = Remover(env: Env(home: home), logURL: log, runner: { _ in 0 })
        try remover.remove(makeFinding(cache.path))
        #expect(throws: RemoveError.self) {
            try remover.remove(makeFinding(cache.path, action: .removeContents))
        }
        try remover.remove(makeFinding(cache.path, action: .command(["tool", "go"])))
        let lines = try readRemovalLog(log)
        #expect(lines.count == 3)
        #expect(lines.map(\.ok) == [true, false, true])
        #expect(lines[1].error != nil)
    }

    @Test func defaultLogLivesUnderHome() {
        let env = Env(home: URL(fileURLWithPath: "/Users/dev/home"))
        #expect(Remover(env: env).logURL.path == "/Users/dev/home/Library/Logs/mac-dev-cleanup/deletions.log")
    }
}

/// Call counter for fake runners; Remover runs synchronously, so no locking is needed.
private final class Counter {
    var count = 0
}

/// Creates a throwaway fixture root (with `home` inside) under the system temp folder.
private func makeRemoverFixture() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("remover-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("home", isDirectory: true),
                                            withIntermediateDirectories: true)
    return root
}

/// A minimal finding pointing at `path`.
private func makeFinding(_ path: String, action: Action = .remove, skipped: SkipReason? = nil) -> Finding {
    Finding(ruleID: "rule", title: "Rule", group: .xcode, path: path, bytes: 123,
            lastModified: nil, cost: .rebuild("rebuild"), action: action, skipped: skipped)
}

/// Decodes every JSON line currently written to the log at `url`.
private func readRemovalLog(_ url: URL) throws -> [Removal] {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try String(decoding: Data(contentsOf: url), as: UTF8.self)
        .split(separator: "\n")
        .map { try decoder.decode(Removal.self, from: Data($0.utf8)) }
}

@Suite struct RemoverSafetyTests {
    @Test func symlinkedFolderCannotLeadOutsideHome() throws {
        let root = try makeRemoverFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        let home = root.appendingPathComponent("home", isDirectory: true)
        let outside = root.appendingPathComponent("outside/data", isDirectory: true)
        try fm.createDirectory(at: outside.appendingPathComponent("x"), withIntermediateDirectories: true)
        let caches = home.appendingPathComponent("Library/Caches", isDirectory: true)
        try fm.createDirectory(at: caches, withIntermediateDirectories: true)
        let link = caches.appendingPathComponent("link")
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)
        let remover = Remover(env: Env(home: home), logURL: root.appendingPathComponent("deletions.log"))
        #expect(throws: RemoveError.outsideHome) {
            try remover.remove(makeFinding(link.appendingPathComponent("x").path))
        }
        #expect(fm.fileExists(atPath: outside.appendingPathComponent("x").path))
    }

    @Test func symlinkTargetIsRemovedAsALinkOnly() throws {
        let root = try makeRemoverFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        let home = root.appendingPathComponent("home", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: outside.appendingPathComponent("file"))
        let caches = home.appendingPathComponent("Library/Caches", isDirectory: true)
        try fm.createDirectory(at: caches, withIntermediateDirectories: true)
        let link = caches.appendingPathComponent("link")
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)
        let remover = Remover(env: Env(home: home), logURL: root.appendingPathComponent("deletions.log"))
        try remover.remove(makeFinding(link.path))
        #expect((try? fm.destinationOfSymbolicLink(atPath: link.path)) == nil)
        #expect(fm.fileExists(atPath: outside.appendingPathComponent("file").path))
    }

    @Test func siblingOfHomeWithSamePrefixIsOutside() throws {
        let root = try makeRemoverFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let sibling = root.appendingPathComponent("home-other/a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        let remover = Remover(env: Env(home: home), logURL: root.appendingPathComponent("deletions.log"))
        #expect(throws: RemoveError.outsideHome) { try remover.remove(makeFinding(sibling.path)) }
        #expect(throws: RemoveError.outsideHome) { try remover.remove(makeFinding("a/b/c")) }
        #expect(throws: RemoveError.outsideHome) { try remover.remove(makeFinding(home.path + "/")) }
        #expect(FileManager.default.fileExists(atPath: sibling.path))
    }

    @Test func failedCommandStaysFailedForTheSameArgv() throws {
        let root = try makeRemoverFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let log = root.appendingPathComponent("deletions.log")
        let runs = Counter()
        let remover = Remover(env: Env(home: home), logURL: log, runner: { _ in runs.count += 1; return 2 })
        let finding = makeFinding(home.appendingPathComponent("a/b").path, action: .command(["brew", "cleanup"]))
        #expect(throws: RemoveError.commandFailed(2)) { try remover.remove(finding) }
        #expect(throws: RemoveError.commandFailed(2)) { try remover.remove(finding) }
        #expect(runs.count == 1)
        #expect(try readRemovalLog(log).map(\.ok) == [false, false])
    }

    @Test func unwritableLogDeletesNothing() throws {
        let root = try makeRemoverFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        let home = root.appendingPathComponent("home", isDirectory: true)
        let cache = home.appendingPathComponent(".npm/_cacache", isDirectory: true)
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        // A regular file where the log folder should be makes the log impossible to create.
        let blocker = root.appendingPathComponent("logs")
        try Data().write(to: blocker)
        let remover = Remover(env: Env(home: home), logURL: blocker.appendingPathComponent("deletions.log"))
        #expect(throws: RemoveError.self) { try remover.remove(makeFinding(cache.path)) }
        #expect(fm.fileExists(atPath: cache.path))
    }

    @Test func defaultRunnerPassesArgvWithoutAShell() throws {
        let root = try makeRemoverFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let marker = root.appendingPathComponent("marker")
        let remover = Remover(env: Env(home: home), logURL: root.appendingPathComponent("deletions.log"))
        let target = home.appendingPathComponent("a/b").path
        try remover.remove(makeFinding(target, action: .command(["echo", "; touch \(marker.path)"])))
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        #expect(throws: RemoveError.commandFailed(1)) {
            try remover.remove(makeFinding(target, action: .command(["false"])))
        }
    }
}

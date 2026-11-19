import Foundation
import Testing
@testable import DevCleanupCore

/// One fixed instant every guard decision is measured against.
let guardsNow = Date(timeIntervalSince1970: 1_000_000_000)

func makeGuards(running: Set<String> = [], open: Set<String> = [], olderThan: TimeInterval? = nil) -> Guards {
    Guards(now: guardsNow, olderThan: olderThan, runningProcesses: running, pathsWithOpenFiles: open)
}

@Test func processRunningSkipsWhenBlockedAppRuns() {
    let g = makeGuards(running: ["Xcode", "node"])
    #expect(g.skipReason(path: "/h/D", lastModified: nil, blockedBy: ["Xcode"]) == .processRunning)
}

@Test func processRunningRequiresExactNameMatch() {
    let g = makeGuards(running: ["Xcode-beta", "xcode"])
    #expect(g.skipReason(path: "/h/D", lastModified: nil, blockedBy: ["Xcode"]) == nil)
}

@Test func emptyBlockedByNeverSkipsForProcess() {
    let g = makeGuards(running: ["Xcode"])
    #expect(g.skipReason(path: "/h/D", lastModified: nil, blockedBy: []) == nil)
}

@Test func recentlyModifiedSkipsInsideWindow() {
    let g = makeGuards()
    #expect(g.skipReason(path: "/h/D", lastModified: guardsNow.addingTimeInterval(-600), blockedBy: []) == .recentlyModified)
}

@Test func recentlyModifiedBoundaryIsExclusive() {
    let g = makeGuards()
    let exactlyWindowOld = guardsNow.addingTimeInterval(-Guards.recentWindow)
    #expect(g.skipReason(path: "/h/D", lastModified: exactlyWindowOld, blockedBy: []) == nil)
}

@Test func recentlyModifiedDoesNotApplyToOldPaths() {
    let g = makeGuards()
    #expect(g.skipReason(path: "/h/D", lastModified: guardsNow.addingTimeInterval(-4 * 3600), blockedBy: []) == nil)
}

@Test func tooNewSkipsWhenOlderThanFilterApplies() {
    let g = makeGuards(olderThan: 86400)
    #expect(g.skipReason(path: "/h/D", lastModified: guardsNow.addingTimeInterval(-4 * 3600), blockedBy: []) == .tooNew)
    #expect(g.skipReason(path: "/h/D", lastModified: guardsNow.addingTimeInterval(-2 * 86400), blockedBy: []) == nil)
}

@Test func tooNewIgnoredWithoutOlderThanFilter() {
    let g = makeGuards(olderThan: nil)
    #expect(g.skipReason(path: "/h/D", lastModified: guardsNow.addingTimeInterval(-4 * 3600), blockedBy: []) == nil)
}

@Test func nilLastModifiedIsNeitherRecentNorTooNew() {
    let g = makeGuards(olderThan: 86400)
    #expect(g.skipReason(path: "/h/D", lastModified: nil, blockedBy: []) == nil)
}

@Test func openFilesSkipsWhenAFileInsidePathIsOpen() {
    let g = makeGuards(open: ["/h/D/App-dxdwdygnymzbcewyjccpgrhmlhvq/Index.openidx"])
    #expect(g.skipReason(path: "/h/D", lastModified: guardsNow.addingTimeInterval(-48 * 3600), blockedBy: []) == .openFiles)
}

@Test func openFilesSkipsWhenThePathItselfIsOpen() {
    let g = makeGuards(open: ["/h/log.txt"])
    #expect(g.skipReason(path: "/h/log.txt", lastModified: guardsNow.addingTimeInterval(-48 * 3600), blockedBy: []) == .openFiles)
}

@Test func openFilesIgnoresSiblingDirectories() {
    let g = makeGuards(open: ["/h/D2/App/Index.openidx"])
    #expect(g.skipReason(path: "/h/D", lastModified: guardsNow.addingTimeInterval(-48 * 3600), blockedBy: []) == nil)
}

@Test func nothingAppliesMeansSafe() {
    let g = makeGuards(running: ["Finder"], open: ["/elsewhere/file"])
    #expect(g.skipReason(path: "/h/D", lastModified: guardsNow.addingTimeInterval(-48 * 3600), blockedBy: []) == nil)
}

@Test func processRunningBeatsAllOtherReasons() {
    let g = makeGuards(running: ["Xcode"],
                       open: ["/h/D/App/Index.openidx"],
                       olderThan: 86400)
    #expect(g.skipReason(path: "/h/D", lastModified: guardsNow.addingTimeInterval(-600), blockedBy: ["Xcode"]) == .processRunning)
}

@Test func recentlyModifiedBeatsTooNewAndOpenFiles() {
    let g = makeGuards(open: ["/h/D/App/Index.openidx"], olderThan: 86400)
    #expect(g.skipReason(path: "/h/D", lastModified: guardsNow.addingTimeInterval(-600), blockedBy: []) == .recentlyModified)
}

@Test func tooNewBeatsOpenFiles() {
    let g = makeGuards(open: ["/h/D/App/Index.openidx"], olderThan: 86400)
    #expect(g.skipReason(path: "/h/D", lastModified: guardsNow.addingTimeInterval(-4 * 3600), blockedBy: []) == .tooNew)
}

@Test func parseAgeSupportsDaysWeeksHours() {
    #expect(Guards.parseAge("7d") == 604800)
    #expect(Guards.parseAge("2w") == 1209600)
    #expect(Guards.parseAge("12h") == 43200)
}

@Test func parseAgeRejectsBadInput() {
    #expect(Guards.parseAge("x") == nil)
    #expect(Guards.parseAge("") == nil)
    #expect(Guards.parseAge("7") == nil)
    #expect(Guards.parseAge("-1d") == nil)
}

@Test func parseAgeAcceptsZero() {
    #expect(Guards.parseAge("0d") == 0)
}

@Test func parsePSDropsHeaderAndTrimsNames() {
    let text = "COMMAND\nlaunchd\n  node  \nXcode\nnode\n"
    #expect(Guards.parsePS(text) == ["launchd", "node", "Xcode"])
}

@Test func parsePSEmptyOutputYieldsNoNames() {
    #expect(Guards.parsePS("") == [])
    #expect(Guards.parsePS("\n") == [])
}

@Test func parseLsofKeepsOnlyPathsUnderRoots() {
    let text = "p123\nf32\nn/private/tmp/fx/a.txt\nf33\nn/private/tmp/other.log\n"
        + "p456\nf1\nn/private/tmp/fx/sub/b.txt\ntREG\n\n"
    let roots = ["/private/tmp/fx"]
    #expect(Guards.parseLsof(text, roots: roots) == ["/private/tmp/fx/a.txt", "/private/tmp/fx/sub/b.txt"])
}

@Test func parseLsofPrefixMustNotSwallowSiblingPaths() {
    let text = "n/a/b\nn/a/b/c.txt\nn/a/bc\nn/elsewhere/e.txt\n"
    let roots = ["/a/b"]
    #expect(Guards.parseLsof(text, roots: roots) == ["/a/b", "/a/b/c.txt"])
}

@Test func parseLsofWithNoRootsKeepsNothing() {
    #expect(Guards.parseLsof("n/private/tmp/a.txt\n", roots: []) == [])
}

@Test func runningProcessNamesIsNonEmpty() {
    #expect(!Guards.runningProcessNames().isEmpty)
}

@Test func openFilesFindsAFileThisProcessHoldsOpen() throws {
    let made = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
    // lsof reports /private/var/...; realpath matches it, resolvingSymlinksInPath strips /private.
    let dir = URL(fileURLWithPath: try #require(realpath(made.path, nil).map { String(cString: $0) }))
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("held.txt")
    try Data("x".utf8).write(to: file)
    let handle = try #require(FileHandle(forReadingAtPath: file.path))
    defer { try? handle.close() }
    #expect(Guards.openFiles(under: [dir.path]).contains(file.path))
}

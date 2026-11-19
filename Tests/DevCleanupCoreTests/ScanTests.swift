import Foundation
import Testing
@testable import DevCleanupCore

/// Fixture path string built from components under `root`.
private func path(_ root: URL, _ components: String...) -> String {
    components.reduce(root) { $0.appendingPathComponent($1) }.path
}

/// Fresh fixture home under the system temporary directory, resolved through realpath so
/// paths match what folder enumeration returns; delete it with `defer`.
private func makeHome() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    guard let resolved = realpath(url.path, nil) else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                      userInfo: [NSLocalizedDescriptionKey: "realpath failed: \(url.path)"])
    }
    defer { free(resolved) }
    return URL(fileURLWithPath: String(cString: resolved))
}

/// A file of `byteCount` varying bytes plus every missing parent folder.
private func writeFile(_ url: URL, byteCount: Int) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data((0..<byteCount).map { UInt8($0 % 251) }).write(to: url)
}

/// Backdates the modification date of one file or folder by `days` days.
private func age(_ url: URL, days: Double = 30) throws {
    try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSinceNow: -days * 86400)], ofItemAtPath: url.path)
}

/// The finding the docker probe would return; never skipped by the guards.
private func dockerFinding() -> Finding {
    Finding(ruleID: "docker-images", title: "Docker images", group: .docker,
            path: "/var/lib/docker", bytes: 500, lastModified: nil,
            cost: .rebuild("docker system prune rebuilds them"),
            action: .command(["docker", "system", "prune"]))
}

@Suite struct ScanTests {
    /// Runs a scan over the fixture home with fixed guard snapshots and the given docker probe.
    private func runScan(home: URL, rules: [Rule], groups: Set<Group>? = nil,
                         olderThan: TimeInterval? = nil, runningProcesses: Set<String> = [],
                         docker: @escaping () -> Finding? = { nil }) -> [Finding] {
        let options = ScanOptions(groups: groups, olderThan: olderThan, projectRoots: [home])
        return Scan(env: Env(home: home), options: options, rules: rules,
                    runningProcesses: { runningProcesses }, openFiles: { _ in [] }, docker: docker).run()
    }

    @Test func oldFolderIsReportedUnskipped() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = URL(fileURLWithPath: path(home, "junk", "derived", "big.bin"))
        try writeFile(file, byteCount: 100_000)
        try age(URL(fileURLWithPath: path(home, "junk", "derived")))
        try age(file)
        let rule = Rule(id: "test-derived", title: "DerivedData", group: .xcode,
                        cost: .rebuild("next build is slower"),
                        locate: { [$0.inHome("junk/derived")] })
        let findings = runScan(home: home, rules: [rule])
        #expect(findings.count == 1)
        let finding = findings[0]
        #expect(finding.ruleID == "test-derived")
        #expect(finding.title == "DerivedData")
        #expect(finding.group == .xcode)
        #expect(finding.path == path(home, "junk", "derived"))
        #expect(finding.bytes > 0)
        #expect(finding.cost == .rebuild("next build is slower"))
        #expect(finding.action == .remove)
        #expect(finding.skipped == nil)
        guard let modified = finding.lastModified else {
            Issue.record("expected a lastModified date")
            return
        }
        #expect(Date().timeIntervalSince(modified) > 29 * 86400)
    }

    @Test func freshlyModifiedFolderIsSkipped() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try writeFile(URL(fileURLWithPath: path(home, "junk", "cache", "now.bin")), byteCount: 4096)
        let rule = Rule(id: "test-cache", title: "Cache", group: .node,
                        cost: .redownload("re-downloaded"), locate: { [$0.inHome("junk/cache")] })
        let findings = runScan(home: home, rules: [rule])
        #expect(findings.count == 1)
        #expect(findings[0].skipped == .recentlyModified)
    }

    @Test func runningBlockedProcessSkipsTheRule() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = URL(fileURLWithPath: path(home, "junk", "device-support", "old.dSYM"))
        try writeFile(file, byteCount: 4096)
        try age(URL(fileURLWithPath: path(home, "junk", "device-support")))
        try age(file)
        let rule = Rule(id: "test-devices", title: "DeviceSupport", group: .xcode,
                        cost: .rebuild("re-downloaded from Xcode"), blockedBy: ["Xcode"],
                        locate: { [$0.inHome("junk/device-support")] })
        let findings = runScan(home: home, rules: [rule], runningProcesses: ["Xcode"])
        #expect(findings.count == 1)
        #expect(findings[0].skipped == .processRunning)
    }

    @Test func olderThanSkipsNewerItems() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = URL(fileURLWithPath: path(home, "junk", "weeks", "file.bin"))
        try writeFile(file, byteCount: 4096)
        try age(URL(fileURLWithPath: path(home, "junk", "weeks")), days: 3)
        try age(file, days: 3)
        let rule = Rule(id: "test-weeks", title: "Weeks", group: .brew,
                        cost: .lost("gone"), locate: { [$0.inHome("junk/weeks")] })
        let findings = runScan(home: home, rules: [rule], olderThan: 7 * 86400)
        #expect(findings.count == 1)
        #expect(findings[0].skipped == .tooNew)
    }

    @Test func emptyFolderYieldsNoFinding() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: path(home, "junk", "empty")),
                                                withIntermediateDirectories: true)
        let rule = Rule(id: "test-empty", title: "Empty", group: .go,
                        cost: .rebuild("rebuild"), locate: { [$0.inHome("junk/empty")] })
        #expect(runScan(home: home, rules: [rule]).isEmpty)
    }

    @Test func projectNodeModulesIsReported() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let app = URL(fileURLWithPath: path(home, "code", "app"))
        let modules = app.appendingPathComponent("node_modules")
        let index = URL(fileURLWithPath: path(home, "code", "app", "node_modules", "x", "index.js"))
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: app.appendingPathComponent("package.json"))
        try writeFile(index, byteCount: 50_000)
        try age(modules)
        try age(URL(fileURLWithPath: path(home, "code", "app", "node_modules", "x")))
        try age(index)

        let findings = runScan(home: home, rules: [])
        #expect(findings.count == 1)
        let finding = findings[0]
        #expect(finding.ruleID == "project-node-modules")
        #expect(finding.title == "node_modules")
        #expect(finding.group == .node)
        #expect(finding.path == modules.path)
        #expect(finding.bytes > 0)
        #expect(finding.skipped == nil)
        #expect(finding.cost == .redownload("npm/pnpm/yarn install brings it back"))
        #expect(finding.action == .remove)
    }

    @Test func groupFilterHidesOtherGroupsAndSkipsDocker() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let xcodeFolder = URL(fileURLWithPath: path(home, "junk", "archives"))
        try writeFile(xcodeFolder.appendingPathComponent("a.xcarchive"), byteCount: 20_000)
        try age(xcodeFolder)
        try age(xcodeFolder.appendingPathComponent("a.xcarchive"))
        let nodeFolder = URL(fileURLWithPath: path(home, "junk", "npm-cache"))
        try writeFile(nodeFolder.appendingPathComponent("pack.tgz"), byteCount: 20_000)
        try age(nodeFolder)
        try age(nodeFolder.appendingPathComponent("pack.tgz"))
        // A node_modules project folder that must be filtered out with the rest of the node group.
        let app = URL(fileURLWithPath: path(home, "code", "app"))
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: app.appendingPathComponent("package.json"))
        let index = URL(fileURLWithPath: path(home, "code", "app", "node_modules", "x", "index.js"))
        try writeFile(index, byteCount: 20_000)
        try age(URL(fileURLWithPath: path(home, "code", "app", "node_modules")))
        try age(URL(fileURLWithPath: path(home, "code", "app", "node_modules", "x")))
        try age(index)

        let xcodeRule = Rule(id: "test-archives", title: "Archives", group: .xcode,
                             cost: .rebuild("rebuilt"), locate: { [$0.inHome("junk/archives")] })
        let nodeRule = Rule(id: "test-npm", title: "npm cache", group: .node,
                            cost: .redownload("re-downloaded"), locate: { [$0.inHome("junk/npm-cache")] })

        var dockerUsed = false
        let findings = runScan(home: home, rules: [xcodeRule, nodeRule], groups: [.xcode],
                               docker: { dockerUsed = true; return nil })
        #expect(findings.count == 1)
        #expect(findings[0].ruleID == "test-archives")
        #expect(findings.map(\.group) == [.xcode])
        #expect(!dockerUsed)
    }

    @Test func dockerFindingAppearsWhenGroupsNil() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let findings = runScan(home: home, rules: [], docker: { dockerFinding() })
        #expect(findings.count == 1)
        #expect(findings[0].ruleID == "docker-images")
        #expect(findings[0].group == .docker)
        #expect(findings[0].bytes == 500)
        #expect(findings[0].skipped == nil)
    }

    @Test func olderThanLeavesDockerOut() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        var dockerUsed = false
        let findings = runScan(home: home, rules: [], olderThan: 7 * 86400,
                               docker: { dockerUsed = true; return dockerFinding() })
        #expect(findings.isEmpty)
        #expect(!dockerUsed)
    }

    @Test func findingsSortByBytesThenPath() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        // Two equally sized folders (their tie is broken by path) and one smaller folder.
        let items: [(name: String, bytes: Int)] = [("alpha", 40_000), ("zzeta", 40_000), ("mid", 1_000)]
        for item in items {
            let file = URL(fileURLWithPath: path(home, "junk", item.name, "blob.bin"))
            try writeFile(file, byteCount: item.bytes)
            try age(URL(fileURLWithPath: path(home, "junk", item.name)))
            try age(file)
        }
        let rules = items.map { item in
            Rule(id: "test-\(item.name)", title: item.name, group: .editors,
                 cost: .rebuild("rebuilt"), locate: { [$0.inHome("junk/\(item.name)")] })
        }
        let findings = runScan(home: home, rules: rules)
        #expect(findings.map(\.path) == items.map { path(home, "junk", $0.name) })
        #expect(findings[0].bytes == findings[1].bytes)
        #expect(findings[2].bytes < findings[0].bytes)
    }

    @Test func cleanableDropsSkippedAndOptInGroups() {
        func finding(_ id: String, _ group: Group, skipped: SkipReason? = nil) -> Finding {
            Finding(ruleID: id, title: id, group: group, path: "/home/\(id)", bytes: 10,
                    lastModified: nil, cost: .lost("gone"), action: .remove, skipped: skipped)
        }
        let xcode = finding("xcode", .xcode)
        let skippedXcode = finding("skipped", .xcode, skipped: .recentlyModified)
        let agents = finding("agents", .agents)
        let models = finding("models", .models)
        let archives = finding("archives", .archives)
        let all = [xcode, skippedXcode, agents, models, archives]

        #expect(Scan.cleanable(all, only: nil) == [xcode])
        #expect(Scan.cleanable(all, only: [.archives]) == [xcode, archives])
        #expect(Scan.cleanable(all, only: [.agents]) == [xcode, agents])
        #expect(Scan.cleanable(all, only: [.agents, .models]) == [xcode, agents, models])
        // A skip reason still wins once the group is allowed.
        #expect(Scan.cleanable([skippedXcode], only: nil).isEmpty)
    }
}

import Foundation
import Testing
@testable import DevCleanupCore

@Suite
struct AIRulesTests {
    private let fm = FileManager.default

    /// Folders each rule is expected to locate once created under the fake home.
    private struct Fixture {
        let claudeCodeProjects: [URL]
        let claudeCodeFileHistory: [URL]
        let claudeCodeOldVersions: [URL]
        let claudeDesktopCache: [URL]
        let codexSessions: [URL]
        let opencodeLogs: [URL]
        let cursorCache: [URL]
        let vscodeCache: [URL]
        let ollamaModels: [URL]
        let lmstudioModels: [URL]
        let huggingfaceHub: [URL]
    }

    @Test func emptyHomeLocatesNothing() throws {
        let home = try makeHome()
        defer { try? fm.removeItem(at: home) }
        let env = Env(home: home)

        for rule in AIRules.all {
            let located = rule.locate(env)
            #expect(located.isEmpty, "\(rule.id) should locate nothing in an empty home, found \(located)")
        }
    }

    @Test func populatedHomeLocatesExpectedPaths() throws {
        let home = try makeHome()
        defer { try? fm.removeItem(at: home) }
        let fixture = try makeFixture(in: home)
        let env = Env(home: home)

        expectLocates("claude-code-projects", in: env, expected: fixture.claudeCodeProjects)
        expectLocates("claude-code-file-history", in: env, expected: fixture.claudeCodeFileHistory)
        expectLocates("claude-code-old-versions", in: env, expected: fixture.claudeCodeOldVersions)
        expectLocates("claude-desktop-cache", in: env, expected: fixture.claudeDesktopCache)
        expectLocates("codex-sessions", in: env, expected: fixture.codexSessions)
        expectLocates("opencode-logs", in: env, expected: fixture.opencodeLogs)
        expectLocates("cursor-cache", in: env, expected: fixture.cursorCache)
        expectLocates("vscode-cache", in: env, expected: fixture.vscodeCache)
        expectLocates("ollama-models", in: env, expected: fixture.ollamaModels)
        expectLocates("lmstudio-models", in: env, expected: fixture.lmstudioModels)
        expectLocates("huggingface-hub", in: env, expected: fixture.huggingfaceHub)
    }

    @Test func locatedPathsStayInsideTheFakeHome() throws {
        let home = try makeHome()
        defer { try? fm.removeItem(at: home) }
        _ = try makeFixture(in: home)
        let env = Env(home: home)
        let homePath = home.resolvingSymlinksInPath().path + "/"

        for rule in AIRules.all {
            let located = rule.locate(env)
            #expect(located.allSatisfy { $0.resolvingSymlinksInPath().path.hasPrefix(homePath) },
                    "\(rule.id) located paths outside the fake home: \(located)")
        }
    }

    @Test func ruleIDsAreUniqueAndUseTheCatalogedGroups() {
        let expectedGroups: [String: Group] = [
            "claude-code-projects": .agents,
            "claude-code-file-history": .agents,
            "claude-code-old-versions": .agents,
            "claude-desktop-cache": .agents,
            "codex-sessions": .agents,
            "opencode-logs": .agents,
            "cursor-cache": .editors,
            "vscode-cache": .editors,
            "ollama-models": .models,
            "lmstudio-models": .models,
            "huggingface-hub": .models,
        ]

        let ids = AIRules.all.map(\.id)
        #expect(Set(ids).count == ids.count, "rule ids must be unique: \(ids)")
        #expect(ids.count == expectedGroups.count, "AIRules.all must contain exactly the cataloged rules: \(ids)")

        for rule in AIRules.all {
            #expect(rule.group == expectedGroups[rule.id],
                    "\(rule.id) must be in group \(expectedGroups[rule.id].map(\.rawValue) ?? "unknown")")
        }
    }

    @Test func singleVersionEntryLocatesNothing() throws {
        let home = try makeHome()
        defer { try? fm.removeItem(at: home) }
        let env = Env(home: home)

        _ = try versionFile("only", agedDays: 1, in: home)

        #expect(locate("claude-code-old-versions", in: env).isEmpty)
    }

    @Test func plainVersionFilesOlderThanTheNewestAreLocated() throws {
        let home = try makeHome()
        defer { try? fm.removeItem(at: home) }
        let env = Env(home: home)

        let oldVersion = try versionFile("old", agedDays: 3, in: home)
        let midVersion = try versionFile("mid", agedDays: 2, in: home)
        _ = try versionFile("new", agedDays: 1, in: home)

        expectLocates("claude-code-old-versions", in: env, expected: [oldVersion, midVersion])
    }

    @Test func currentlyRunningVersionIsNeverLocated() throws {
        let home = try makeHome()
        defer { try? fm.removeItem(at: home) }
        let env = Env(home: home)

        let oldVersion = try versionFile("old", agedDays: 3, in: home)
        let midVersion = try versionFile("mid", agedDays: 2, in: home)
        _ = try versionFile("new", agedDays: 1, in: home)

        try fm.createDirectory(at: env.inHome(".local/bin"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: env.inHome(".local/bin/claude"), withDestinationURL: oldVersion)

        expectLocates("claude-code-old-versions", in: env, expected: [midVersion])
    }

    @Test func blockedByNamesMatchRunningProcessNames() {
        #expect(blockedBy("opencode-logs") == ["opencode", "opencode-cli", "OpenCode"])
        #expect(blockedBy("codex-sessions") == ["codex", "Codex"])
        #expect(blockedBy("ollama-models") == ["ollama", "Ollama"])
    }

    // MARK: - Helpers

    private func makeHome() throws -> URL {
        let home = fm.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func makeFixture(in home: URL) throws -> Fixture {
        func folder(_ relativePath: String) throws -> URL {
            let url = home.appendingPathComponent(relativePath, isDirectory: true)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        let claudeCodeProjects = try [
            folder(".claude/projects/alpha"),
            folder(".claude/projects/beta"),
        ]
        let claudeCodeFileHistory = try [
            folder(".claude/file-history/charlie"),
            folder(".claude/file-history/delta"),
        ]

        let oldVersion = try folder(".local/share/claude/versions/old")
        let midVersion = try folder(".local/share/claude/versions/mid")
        let currentVersion = try folder(".local/share/claude/versions/new")
        try setModificationDate(Date(timeIntervalSinceNow: -3 * 86_400), of: oldVersion)
        try setModificationDate(Date(timeIntervalSinceNow: -2 * 86_400), of: midVersion)
        try setModificationDate(Date(timeIntervalSinceNow: -86_400), of: currentVersion)

        let claudeDesktopCache = try [
            folder("Library/Application Support/Claude/Cache"),
            folder("Library/Application Support/Claude/Code Cache"),
            folder("Library/Application Support/Claude/GPUCache"),
        ]
        let codexSessions = try [
            folder(".codex/sessions/2026/10"),
            folder(".codex/sessions/2026/11"),
        ]
        let opencodeLogs = try [folder(".local/share/opencode/log")]
        let cursorCache = try [
            folder("Library/Application Support/Cursor/Cache"),
            folder("Library/Application Support/Cursor/CachedData"),
            folder("Library/Application Support/Cursor/Code Cache"),
            folder("Library/Application Support/Cursor/GPUCache"),
            folder("Library/Application Support/Cursor/CachedExtensionVSIXs"),
        ]
        let vscodeCache = try [
            folder("Library/Application Support/Code/Cache"),
            folder("Library/Application Support/Code/CachedData"),
            folder("Library/Application Support/Code/Code Cache"),
            folder("Library/Application Support/Code/GPUCache"),
            folder("Library/Application Support/Code/CachedExtensionVSIXs"),
        ]
        let ollamaModels = try [folder(".ollama/models")]
        let lmstudioModels = try [
            folder(".lmstudio/models"),
            folder(".cache/lm-studio/models"),
        ]
        let huggingfaceHub = try [folder(".cache/huggingface/hub")]

        return Fixture(
            claudeCodeProjects: claudeCodeProjects,
            claudeCodeFileHistory: claudeCodeFileHistory,
            claudeCodeOldVersions: [oldVersion, midVersion],
            claudeDesktopCache: claudeDesktopCache,
            codexSessions: codexSessions,
            opencodeLogs: opencodeLogs,
            cursorCache: cursorCache,
            vscodeCache: vscodeCache,
            ollamaModels: ollamaModels,
            lmstudioModels: lmstudioModels,
            huggingfaceHub: huggingfaceHub
        )
    }

    private func setModificationDate(_ date: Date, of url: URL) throws {
        try fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    /// Creates `.local/share/claude/versions/<name>` as a plain file aged `agedDays` days.
    private func versionFile(_ name: String, agedDays: Double, in home: URL) throws -> URL {
        let versions = home.appendingPathComponent(".local/share/claude/versions", isDirectory: true)
        try fm.createDirectory(at: versions, withIntermediateDirectories: true)
        let url = versions.appendingPathComponent(name)
        guard fm.createFile(atPath: url.path, contents: Data("claude".utf8)) else {
            throw NSError(domain: "AIRulesTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "could not create \(url.path)"])
        }
        try setModificationDate(Date(timeIntervalSinceNow: -agedDays * 86_400), of: url)
        return url
    }

    private func blockedBy(_ id: String) -> [String] {
        guard let rule = AIRules.all.first(where: { $0.id == id }) else {
            Issue.record("AIRules.all is missing the \"\(id)\" rule")
            return []
        }
        return rule.blockedBy
    }

    private func expectLocates(_ id: String, in env: Env, expected: [URL]) {
        let located = locate(id, in: env).map { $0.resolvingSymlinksInPath().path }
        let wanted = expected.map { $0.resolvingSymlinksInPath().path }
        #expect(located == wanted, "\(id) located \(located), expected \(wanted)")
    }

    private func locate(_ id: String, in env: Env) -> [URL] {
        guard let rule = AIRules.all.first(where: { $0.id == id }) else {
            Issue.record("AIRules.all is missing the \"\(id)\" rule")
            return []
        }
        return rule.locate(env)
    }
}

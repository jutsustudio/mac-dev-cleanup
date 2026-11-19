import Foundation
import Testing
@testable import DevCleanupCore

/// The relative paths each rule must locate, straight from the rule table.
private let expectedPaths: [String: [String]] = [
    "npm-cache": [".npm/_cacache"],
    "pnpm-store": ["Library/pnpm/store", ".local/share/pnpm/store"],
    "yarn-cache": ["Library/Caches/Yarn", ".yarn/berry/cache"],
    "bun-cache": [".bun/install/cache"],
    "deno-cache": ["Library/Caches/deno"],
    "playwright-browsers": ["Library/Caches/ms-playwright"],
    "pip-cache": ["Library/Caches/pip"],
    "uv-cache": [".cache/uv"],
    "poetry-cache": ["Library/Caches/pypoetry/cache", "Library/Caches/pypoetry/artifacts"],
    "cargo-registry": [".cargo/registry/cache", ".cargo/registry/src", ".cargo/git/checkouts"],
    "go-build-cache": ["Library/Caches/go-build"],
    "go-mod-cache": ["go/pkg/mod"],
    "gradle-cache": [".gradle/caches", ".gradle/wrapper/dists"],
    "maven-repo": [".m2/repository"],
    "android-cache": [".android/cache"],
    "brew-cache": ["Library/Caches/Homebrew"],
]

/// The group the table assigns to each rule id.
private let expectedGroups: [String: Group] = [
    "npm-cache": .node,
    "pnpm-store": .node,
    "yarn-cache": .node,
    "bun-cache": .node,
    "deno-cache": .node,
    "playwright-browsers": .node,
    "pip-cache": .python,
    "uv-cache": .python,
    "poetry-cache": .python,
    "cargo-registry": .rust,
    "go-build-cache": .go,
    "go-mod-cache": .go,
    "gradle-cache": .jvm,
    "maven-repo": .jvm,
    "android-cache": .android,
    "brew-cache": .brew,
]

/// The action and blockedBy the table assigns to each rule id.
private let expectedActionsAndBlockers: [String: (Action, [String])] = [
    "npm-cache": (.remove, []),
    "pnpm-store": (.remove, []),
    "yarn-cache": (.removeContents, []),
    "bun-cache": (.removeContents, ["bun"]),
    "deno-cache": (.removeContents, ["deno"]),
    "playwright-browsers": (.removeContents, []),
    "pip-cache": (.removeContents, []),
    "uv-cache": (.removeContents, ["uv"]),
    "poetry-cache": (.removeContents, []),
    "cargo-registry": (.removeContents, ["cargo"]),
    "go-build-cache": (.removeContents, ["go"]),
    "go-mod-cache": (.command(["go", "clean", "-modcache"]), ["go"]),
    "gradle-cache": (.removeContents, ["java"]),
    "maven-repo": (.removeContents, ["java"]),
    "android-cache": (.removeContents, ["studio"]),
    "brew-cache": (.removeContents, []),
]

/// Every relative path the table lists, deduplicated and sorted.
private var allListedPaths: [String] {
    Set(expectedPaths.values.flatMap { $0 }).sorted()
}

/// True when GOMODCACHE or GOPATH is set, so go-mod-cache reports nothing.
private var goModCacheOverridden: Bool {
    let vars = ProcessInfo.processInfo.environment
    return vars["GOMODCACHE"] != nil || vars["GOPATH"] != nil
}

/// The rules keyed by id; with duplicate ids the first wins and the uniqueness test fails.
private var rulesByID: [String: Rule] {
    Dictionary(ToolchainRules.all.map { ($0.id, $0) },
               uniquingKeysWith: { first, _ in first })
}

/// A fresh empty folder standing in for `$HOME`.
private func makeFakeHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home
}

/// Creates each relative path, missing parents included.
private func createFolders(_ relatives: [String], under home: URL) throws {
    for relative in relatives {
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(relative, isDirectory: true),
            withIntermediateDirectories: true)
    }
}

@Test func emptyHomeLocatesNothing() throws {
    let home = try makeFakeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let env = Env(home: home)
    for rule in ToolchainRules.all {
        #expect(rule.locate(env).isEmpty, "\(rule.id) located paths in an empty home")
    }
}

@Test func populatedHomeLocatesExactlyTheListedPaths() throws {
    let home = try makeFakeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try createFolders(allListedPaths, under: home)
    let env = Env(home: home)
    for (id, relatives) in expectedPaths.sorted(by: { $0.key < $1.key }) {
        let located = rulesByID[id]?.locate(env) ?? []
        let expected: [URL]
        if id == "go-mod-cache", goModCacheOverridden {
            expected = []
        } else {
            expected = relatives.map { env.inHome($0) }
        }
        #expect(located == expected, "\(id) located \(located.map(\.path))")
    }
}

@Test func ruleIDsAreUniqueAndGroupsMatchTheTable() {
    let ids = ToolchainRules.all.map(\.id)
    #expect(Set(ids).count == ids.count)
    #expect(Set(ids) == Set(expectedPaths.keys))
    for rule in ToolchainRules.all {
        #expect(rule.group == expectedGroups[rule.id],
                "\(rule.id) has group \(rule.group)")
    }
}

@Test func actionsAndBlockersMatchTheTable() {
    for (id, (action, blockedBy)) in expectedActionsAndBlockers.sorted(by: { $0.key < $1.key }) {
        let rule = rulesByID[id]
        #expect(rule?.action == action && rule?.blockedBy == blockedBy,
                "\(id) does not match the table")
    }
}

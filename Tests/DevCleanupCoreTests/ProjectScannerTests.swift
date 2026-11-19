import Foundation
import Testing
@testable import DevCleanupCore

/// Fixture URL built from path components; no trailing slash, so paths match scanner output.
private func fixtureURL(_ root: URL, _ components: String...) -> URL {
    components.reduce(root) { $0.appendingPathComponent($1) }
}

/// Creates `url` and every missing folder on the way to it.
private func makeFolder(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
}

/// Creates an empty file plus any missing parent folders.
private func makeFile(_ url: URL) throws {
    try makeFolder(url.deletingLastPathComponent())
    try Data().write(to: url)
}

/// Fresh fixture folder under the system temporary directory; delete it with `defer`.
/// Symlinks are resolved because folder enumeration returns canonical `/private/...` URLs.
private func makeScannerFixture() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try makeFolder(url)
    guard let resolved = realpath(url.path, nil) else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                      userInfo: [NSLocalizedDescriptionKey: "realpath failed: \(url.path)"])
    }
    defer { free(resolved) }
    return URL(fileURLWithPath: String(cString: resolved))
}

@Suite struct ProjectScannerTests {
    @Test func nodeModulesWithPackageJSONIsAHit() throws {
        let fx = try makeScannerFixture()
        defer { try? FileManager.default.removeItem(at: fx) }
        try makeFile(fixtureURL(fx, "app", "package.json"))
        try makeFolder(fixtureURL(fx, "app", "node_modules"))
        let hits = ProjectScanner(roots: [fx]).scan()
        let expected = ProjectHit(
            kindID: "project-node-modules",
            url: fixtureURL(fx, "app").appendingPathComponent("node_modules", isDirectory: true))
        #expect(hits == [expected])
    }

    @Test func nestedNodeModulesIsReportedOnce() throws {
        let fx = try makeScannerFixture()
        defer { try? FileManager.default.removeItem(at: fx) }
        try makeFile(fixtureURL(fx, "app", "package.json"))
        try makeFolder(fixtureURL(fx, "app", "node_modules"))
        try makeFile(fixtureURL(fx, "app", "node_modules", "dep", "package.json"))
        try makeFolder(fixtureURL(fx, "app", "node_modules", "dep", "node_modules"))
        let hits = ProjectScanner(roots: [fx]).scan()
        #expect(hits.map(\.url.path) == [fixtureURL(fx, "app", "node_modules").path])
    }

    @Test func rustAndMavenTargetsAreToldApartByMarker() throws {
        let fx = try makeScannerFixture()
        defer { try? FileManager.default.removeItem(at: fx) }
        try makeFile(fixtureURL(fx, "rust", "Cargo.toml"))
        try makeFolder(fixtureURL(fx, "rust", "target"))
        try makeFile(fixtureURL(fx, "java", "pom.xml"))
        try makeFolder(fixtureURL(fx, "java", "target"))
        let hits = ProjectScanner(roots: [fx]).scan()
        #expect(hits.map(\.kindID) == ["project-maven-target", "project-rust-target"])
        #expect(hits.map(\.url.path) == [
            fixtureURL(fx, "java", "target").path,
            fixtureURL(fx, "rust", "target").path,
        ])
    }

    @Test func unmarkedTargetIsNotAHitAndIsDescended() throws {
        let fx = try makeScannerFixture()
        defer { try? FileManager.default.removeItem(at: fx) }
        try makeFile(fixtureURL(fx, "plain", "target", "nested", "package.json"))
        try makeFolder(fixtureURL(fx, "plain", "target", "nested", "node_modules"))
        let hits = ProjectScanner(roots: [fx]).scan()
        #expect(hits.map(\.url.path) == [fixtureURL(fx, "plain", "target", "nested", "node_modules").path])
    }

    @Test func venvQualifiesOnlyWithPyvenvCfg() throws {
        let fx = try makeScannerFixture()
        defer { try? FileManager.default.removeItem(at: fx) }
        try makeFile(fixtureURL(fx, "good", "venv", "pyvenv.cfg"))
        try makeFolder(fixtureURL(fx, "bad", ".venv"))
        let hits = ProjectScanner(roots: [fx]).scan()
        #expect(hits.map(\.kindID) == ["project-venv-plain"])
        #expect(hits.map(\.url.path) == [fixtureURL(fx, "good", "venv").path])
    }

    @Test func gradleBuildAndCacheAreHits() throws {
        let fx = try makeScannerFixture()
        defer { try? FileManager.default.removeItem(at: fx) }
        try makeFile(fixtureURL(fx, "groovy", "build.gradle"))
        try makeFile(fixtureURL(fx, "groovy", "settings.gradle"))
        try makeFolder(fixtureURL(fx, "groovy", "build"))
        try makeFolder(fixtureURL(fx, "groovy", ".gradle"))
        try makeFile(fixtureURL(fx, "kts", "build.gradle.kts"))
        try makeFolder(fixtureURL(fx, "kts", "build"))
        try makeFolder(fixtureURL(fx, "kts", ".gradle"))
        let hits = ProjectScanner(roots: [fx]).scan()
        #expect(hits.map(\.url.path) == [
            fixtureURL(fx, "groovy", ".gradle").path,
            fixtureURL(fx, "groovy", "build").path,
            fixtureURL(fx, "kts", ".gradle").path,
            fixtureURL(fx, "kts", "build").path,
        ])
        #expect(hits.map(\.kindID) == [
            "project-gradle-cache", "project-gradle", "project-gradle-cache", "project-gradle",
        ])
    }

    @Test func hiddenFoldersAreNotDescendedInto() throws {
        let fx = try makeScannerFixture()
        defer { try? FileManager.default.removeItem(at: fx) }
        try makeFile(fixtureURL(fx, ".cache", "project", "package.json"))
        try makeFolder(fixtureURL(fx, ".cache", "project", "node_modules"))
        try makeFile(fixtureURL(fx, "visible", "package.json"))
        try makeFolder(fixtureURL(fx, "visible", "node_modules"))
        let hits = ProjectScanner(roots: [fx]).scan()
        #expect(hits.map(\.url.path) == [fixtureURL(fx, "visible", "node_modules").path])
    }

    @Test func symlinkToAProjectIsNotFollowed() throws {
        let fx = try makeScannerFixture()
        defer { try? FileManager.default.removeItem(at: fx) }
        try makeFile(fixtureURL(fx, "real", "app", "package.json"))
        try makeFolder(fixtureURL(fx, "real", "app", "node_modules"))
        try FileManager.default.createSymbolicLink(
            atPath: fixtureURL(fx, "link").path,
            withDestinationPath: fixtureURL(fx, "real").path)
        let hits = ProjectScanner(roots: [fx]).scan()
        #expect(hits.map(\.url.path) == [fixtureURL(fx, "real", "app", "node_modules").path])
    }

    @Test func maxDepthLimitsTheWalk() throws {
        let fx = try makeScannerFixture()
        defer { try? FileManager.default.removeItem(at: fx) }
        try makeFile(fixtureURL(fx, "a", "package.json"))
        try makeFolder(fixtureURL(fx, "a", "node_modules"))
        try makeFile(fixtureURL(fx, "a", "b", "package.json"))
        try makeFolder(fixtureURL(fx, "a", "b", "node_modules"))
        let hits = ProjectScanner(roots: [fx], maxDepth: 2).scan()
        #expect(hits.map(\.url.path) == [fixtureURL(fx, "a", "node_modules").path])
    }

    @Test func overlappingAndDuplicateRootsYieldSortedUniqueHits() throws {
        let fx = try makeScannerFixture()
        defer { try? FileManager.default.removeItem(at: fx) }
        try makeFile(fixtureURL(fx, "z", "package.json"))
        try makeFolder(fixtureURL(fx, "z", "node_modules"))
        try makeFile(fixtureURL(fx, "inside", "m", "package.json"))
        try makeFolder(fixtureURL(fx, "inside", "m", "node_modules"))
        let inside = fixtureURL(fx, "inside")
        let hits = ProjectScanner(roots: [fx, inside, fx]).scan()
        #expect(hits.map(\.url.path) == [
            fixtureURL(fx, "inside", "m", "node_modules").path,
            fixtureURL(fx, "z", "node_modules").path,
        ])
        #expect(hits.map(\.kindID) == ["project-node-modules", "project-node-modules"])
    }

    @Test func unqualifiedGradleCacheIsNotDescendedInto() throws {
        let fx = try makeScannerFixture()
        defer { try? FileManager.default.removeItem(at: fx) }
        try makeFile(fixtureURL(fx, "p", ".gradle", "caches", "x", "proj", "build.gradle"))
        try makeFolder(fixtureURL(fx, "p", ".gradle", "caches", "x", "proj", "build"))
        try makeFile(fixtureURL(fx, "real", "package.json"))
        try makeFolder(fixtureURL(fx, "real", "node_modules"))
        let hits = ProjectScanner(roots: [fx]).scan()
        #expect(hits.map(\.url.path) == [fixtureURL(fx, "real", "node_modules").path])
    }

    @Test func libraryUnderHomeIsSkippedAtAnyDepth() throws {
        let fx = try makeScannerFixture()
        defer { try? FileManager.default.removeItem(at: fx) }
        try makeFile(fixtureURL(fx, "home", "Library", "proj", "package.json"))
        try makeFolder(fixtureURL(fx, "home", "Library", "proj", "node_modules"))
        try makeFile(fixtureURL(fx, "home", "app", "package.json"))
        try makeFolder(fixtureURL(fx, "home", "app", "node_modules"))
        let hits = ProjectScanner(roots: [fx], home: fixtureURL(fx, "home")).scan()
        #expect(hits.map(\.url.path) == [fixtureURL(fx, "home", "app", "node_modules").path])
    }

    @Test func targetWithRustAndMavenMarkersYieldsOneHit() throws {
        let fx = try makeScannerFixture()
        defer { try? FileManager.default.removeItem(at: fx) }
        try makeFile(fixtureURL(fx, "both", "Cargo.toml"))
        try makeFile(fixtureURL(fx, "both", "pom.xml"))
        try makeFolder(fixtureURL(fx, "both", "target"))
        let hits = ProjectScanner(roots: [fx]).scan()
        #expect(hits.map(\.kindID) == ["project-rust-target"])
        #expect(hits.map(\.url.path) == [fixtureURL(fx, "both", "target").path])
    }

    @Test func foldersWithoutTheirMarkersYieldNoHits() throws {
        let fx = try makeScannerFixture()
        defer { try? FileManager.default.removeItem(at: fx) }
        try makeFolder(fixtureURL(fx, "n", "venv"))
        try makeFolder(fixtureURL(fx, "n", "build"))
        try makeFolder(fixtureURL(fx, "n", ".build"))
        let hits = ProjectScanner(roots: [fx]).scan()
        #expect(hits.isEmpty)
    }

    @Test func podsSwiftPMAndNodeBuildFoldersAreHits() throws {
        let fx = try makeScannerFixture()
        defer { try? FileManager.default.removeItem(at: fx) }
        try makeFile(fixtureURL(fx, "ios", "Podfile"))
        try makeFolder(fixtureURL(fx, "ios", "Pods"))
        try makeFile(fixtureURL(fx, "swift", "Package.swift"))
        try makeFolder(fixtureURL(fx, "swift", ".build"))
        try makeFile(fixtureURL(fx, "web", "package.json"))
        try makeFolder(fixtureURL(fx, "web", ".next"))
        try makeFolder(fixtureURL(fx, "web", ".turbo"))
        try makeFolder(fixtureURL(fx, "web", ".nuxt"))
        let hits = ProjectScanner(roots: [fx]).scan()
        #expect(hits.map(\.url.path) == [
            fixtureURL(fx, "ios", "Pods").path,
            fixtureURL(fx, "swift", ".build").path,
            fixtureURL(fx, "web", ".next").path,
            fixtureURL(fx, "web", ".nuxt").path,
            fixtureURL(fx, "web", ".turbo").path,
        ])
        #expect(hits.map(\.kindID) == [
            "project-pods", "project-swiftpm", "project-next", "project-nuxt", "project-turbo",
        ])
    }

    @Test func gitAndTrashFoldersAreNeverWalked() throws {
        let fx = try makeScannerFixture()
        defer { try? FileManager.default.removeItem(at: fx) }
        try makeFile(fixtureURL(fx, "g", ".git", "pkg", "package.json"))
        try makeFolder(fixtureURL(fx, "g", ".git", "pkg", "node_modules"))
        try makeFile(fixtureURL(fx, "g", ".Trash", "app", "package.json"))
        try makeFolder(fixtureURL(fx, "g", ".Trash", "app", "node_modules"))
        try makeFile(fixtureURL(fx, "g", "real", "package.json"))
        try makeFolder(fixtureURL(fx, "g", "real", "node_modules"))
        let hits = ProjectScanner(roots: [fx]).scan()
        #expect(hits.map(\.url.path) == [fixtureURL(fx, "g", "real", "node_modules").path])
    }

    @Test func symlinkedNodeModulesIsNotReported() throws {
        let fx = try makeScannerFixture()
        defer { try? FileManager.default.removeItem(at: fx) }
        try makeFile(fixtureURL(fx, "app", "package.json"))
        try makeFolder(fixtureURL(fx, "app", "real_modules"))
        try FileManager.default.createSymbolicLink(
            atPath: fixtureURL(fx, "app", "node_modules").path,
            withDestinationPath: fixtureURL(fx, "app", "real_modules").path)
        try makeFile(fixtureURL(fx, "control", "package.json"))
        try makeFolder(fixtureURL(fx, "control", "node_modules"))
        let hits = ProjectScanner(roots: [fx]).scan()
        #expect(hits.map(\.url.path) == [fixtureURL(fx, "control", "node_modules").path])
    }
}

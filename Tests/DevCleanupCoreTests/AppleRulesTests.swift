import Foundation
import Testing
@testable import DevCleanupCore

private let appleFolders: [String] = [
    "Library/Developer/Xcode/DerivedData",
    "Library/Developer/Xcode/UserData/Previews",
    "Library/Developer/Xcode/Archives/2026-01-01",
    "Library/Developer/Xcode/Archives/2026-01-02",
    "Library/Developer/Xcode/iOS DeviceSupport",
    "Library/Developer/Xcode/watchOS DeviceSupport",
    "Library/Developer/Xcode/tvOS DeviceSupport",
    "Library/Developer/Xcode/visionOS DeviceSupport",
    "Library/Caches/com.apple.dt.Xcode",
    "Library/Developer/CoreSimulator/Caches",
    "Library/Caches/org.swift.swiftpm",
    "Library/Caches/CocoaPods",
    "Library/Caches/org.carthage.CarthageKit",
]

private func makeFakeHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    // Directory enumeration reports firmlink-resolved physical paths (/private/var/...
    // on macOS), and `subfolders(of:)` inherits that spelling; use the same base for
    // the fake home so located URLs compare exactly.
    let probe = home.appendingPathComponent("probe")
    try FileManager.default.createDirectory(at: probe, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: probe) }
    let children = try FileManager.default.contentsOfDirectory(
        at: home, includingPropertiesForKeys: nil)
    return children.first?.deletingLastPathComponent() ?? home
}

private func createAppleFolders(in home: URL) throws {
    for folder in appleFolders {
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(folder),
            withIntermediateDirectories: true)
    }
}

@Suite
struct AppleRulesTests {

    @Test
    func emptyHomeLocatesNothing() throws {
        let home = try makeFakeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let env = Env(home: home)
        for rule in AppleRules.all {
            #expect(rule.locate(env).isEmpty)
        }
    }

    @Test
    func unavailableSimulatorsLocateNothingWithoutDevicesFolder() throws {
        let home = try makeFakeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try createAppleFolders(in: home)
        let env = Env(home: home)
        let located = AppleRules.all
            .filter { $0.id == "simulators-unavailable" }
            .flatMap { $0.locate(env) }
        #expect(located.isEmpty)
    }

    @Test
    func populatedHomeLocatesExpectedPaths() throws {
        let home = try makeFakeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try createAppleFolders(in: home)
        let env = Env(home: home)
        func located(by id: String) -> [URL] {
            AppleRules.all.filter { $0.id == id }.flatMap { $0.locate(env) }
        }

        #expect(located(by: "xcode-derived-data")
            == [env.inHome("Library/Developer/Xcode/DerivedData")])
        #expect(located(by: "xcode-previews")
            == [env.inHome("Library/Developer/Xcode/UserData/Previews")])
        #expect(located(by: "xcode-archives")
            == [env.inHome("Library/Developer/Xcode/Archives/2026-01-01"),
                env.inHome("Library/Developer/Xcode/Archives/2026-01-02")])
        #expect(located(by: "xcode-device-support")
            == [env.inHome("Library/Developer/Xcode/iOS DeviceSupport"),
                env.inHome("Library/Developer/Xcode/watchOS DeviceSupport"),
                env.inHome("Library/Developer/Xcode/tvOS DeviceSupport"),
                env.inHome("Library/Developer/Xcode/visionOS DeviceSupport")])
        #expect(located(by: "xcode-cache")
            == [env.inHome("Library/Caches/com.apple.dt.Xcode")])
        #expect(located(by: "simulator-caches")
            == [env.inHome("Library/Developer/CoreSimulator/Caches")])
        #expect(located(by: "swiftpm-cache")
            == [env.inHome("Library/Caches/org.swift.swiftpm")])
        #expect(located(by: "cocoapods-cache")
            == [env.inHome("Library/Caches/CocoaPods")])
        #expect(located(by: "carthage-cache")
            == [env.inHome("Library/Caches/org.carthage.CarthageKit")])
    }

    @Test
    func locatedPathsStayInsideHome() throws {
        let home = try makeFakeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try createAppleFolders(in: home)
        let env = Env(home: home)
        for rule in AppleRules.all {
            for url in rule.locate(env) {
                #expect(url.path.hasPrefix(home.path))
            }
        }
    }

    @Test
    func ruleIDsAreUniqueAndArchivesAreTheirOwnGroup() {
        let ids = AppleRules.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for rule in AppleRules.all {
            #expect(rule.group == (rule.id == "xcode-archives" ? .archives : .xcode))
        }
    }

    @Test
    func blockedByListsBlockingProcesses() {
        let expected: [String: [String]] = [
            "xcode-derived-data": ["Xcode", "xcodebuild"],
            "xcode-previews": ["Xcode", "xcodebuild"],
            "xcode-archives": ["Xcode", "xcodebuild"],
            "xcode-device-support": ["Xcode", "xcodebuild"],
            "xcode-cache": ["Xcode", "xcodebuild"],
            "simulator-caches": ["Simulator", "Xcode", "xcodebuild"],
            "simulators-unavailable": ["Simulator", "Xcode", "xcodebuild"],
            "swiftpm-cache": ["xcodebuild", "swift-build"],
            "cocoapods-cache": ["pod", "ruby"],
            "carthage-cache": ["carthage"],
        ]
        #expect(Set(AppleRules.all.map(\.id)) == Set(expected.keys))
        for rule in AppleRules.all {
            #expect(rule.blockedBy == expected[rule.id])
        }
    }

    @Test
    func parseUnavailableDecodesSampleJSON() {
        let sample = """
        {"devices": {"iOS 17.0": [{"isAvailable": false, "name": "iPhone 15", "state": "Shutdown", "udid": "11111111-1111-1111-1111-111111111111"}], "watchOS 10.0": [{"udid": "22222222-2222-2222-2222-222222222222"}]}}
        """
        #expect(Set(AppleRules.parseUnavailable(Data(sample.utf8)))
            == ["11111111-1111-1111-1111-111111111111",
                "22222222-2222-2222-2222-222222222222"])
        #expect(AppleRules.parseUnavailable(Data("not JSON".utf8)) == [])
    }
}

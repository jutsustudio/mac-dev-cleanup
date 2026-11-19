import Foundation

enum AppleRules {
    static let all: [Rule] = [
        Rule(id: "xcode-derived-data", title: "Xcode DerivedData", group: .xcode,
             cost: .rebuild("next Xcode build is slower"),
             action: .removeContents,
             blockedBy: ["Xcode", "xcodebuild"],
             locate: { existing([$0.inHome("Library/Developer/Xcode/DerivedData")]) }),
        Rule(id: "xcode-previews", title: "SwiftUI Previews data", group: .xcode,
             cost: .rebuild("previews rebuild on next use"),
             action: .removeContents,
             blockedBy: ["Xcode", "xcodebuild"],
             locate: { existing([$0.inHome("Library/Developer/Xcode/UserData/Previews")]) }),
        Rule(id: "xcode-archives", title: "Xcode Archives", group: .archives,
             cost: .lost("archived builds and their dSYMs"),
             blockedBy: ["Xcode", "xcodebuild"],
             locate: { subfolders(of: $0.inHome("Library/Developer/Xcode/Archives")) }),
        Rule(id: "xcode-device-support", title: "Device support files", group: .xcode,
             cost: .redownload("copied again when a device connects"),
             action: .removeContents,
             blockedBy: ["Xcode", "xcodebuild"],
             locate: { existing([
                 $0.inHome("Library/Developer/Xcode/iOS DeviceSupport"),
                 $0.inHome("Library/Developer/Xcode/watchOS DeviceSupport"),
                 $0.inHome("Library/Developer/Xcode/tvOS DeviceSupport"),
                 $0.inHome("Library/Developer/Xcode/visionOS DeviceSupport"),
             ]) }),
        Rule(id: "xcode-cache", title: "Xcode caches", group: .xcode,
             cost: .rebuild("recreated by Xcode"),
             action: .removeContents,
             blockedBy: ["Xcode", "xcodebuild"],
             locate: { existing([$0.inHome("Library/Caches/com.apple.dt.Xcode")]) }),
        Rule(id: "simulator-caches", title: "Simulator caches", group: .xcode,
             cost: .rebuild("recreated by Simulator"),
             action: .removeContents,
             blockedBy: ["Simulator", "Xcode", "xcodebuild"],
             locate: { existing([$0.inHome("Library/Developer/CoreSimulator/Caches")]) }),
        Rule(id: "simulators-unavailable", title: "Unavailable simulators", group: .xcode,
             cost: .lost("simulators for runtimes no longer installed"),
             action: .command(["xcrun", "simctl", "delete", "unavailable"]),
             blockedBy: ["Simulator", "Xcode", "xcodebuild"],
             locate: { env in
                 existing(unavailableSimulatorUDIDs(env)
                     .map { env.inHome("Library/Developer/CoreSimulator/Devices/\($0)") })
             }),
        Rule(id: "swiftpm-cache", title: "SwiftPM cache", group: .xcode,
             cost: .redownload("packages download again on next resolve"),
             action: .removeContents,
             blockedBy: ["xcodebuild", "swift-build"],
             locate: { existing([$0.inHome("Library/Caches/org.swift.swiftpm")]) }),
        Rule(id: "cocoapods-cache", title: "CocoaPods cache", group: .xcode,
             cost: .redownload("pods download again on next pod install"),
             action: .removeContents,
             blockedBy: ["pod", "ruby"],
             locate: { existing([$0.inHome("Library/Caches/CocoaPods")]) }),
        Rule(id: "carthage-cache", title: "Carthage cache", group: .xcode,
             cost: .redownload("frameworks download again"),
             action: .removeContents,
             blockedBy: ["carthage"],
             locate: { existing([$0.inHome("Library/Caches/org.carthage.CarthageKit")]) }),
    ]

    static func parseUnavailable(_ data: Data) -> [String] {
        struct Payload: Decodable {
            struct Device: Decodable {
                let udid: String
            }

            let devices: [String: [Device]]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return [] }
        return payload.devices.values.joined().map(\.udid)
    }

    fileprivate static func unavailableSimulatorUDIDs(_ env: Env) -> [String] {
        let devices = env.inHome("Library/Developer/CoreSimulator/Devices")
        guard FileManager.default.fileExists(atPath: devices.path),
            FileManager.default.fileExists(atPath: "/usr/bin/xcrun") else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "list", "devices", "unavailable", "-j"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        return parseUnavailable(data)
    }
}

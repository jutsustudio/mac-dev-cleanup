import Foundation

/// Where the scan runs. Tests point `home` at a temporary folder.
public struct Env: Sendable {
    public var home: URL
    public var tmp: URL
    public var now: Date

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                tmp: URL = URL(fileURLWithPath: "/private/tmp"),
                now: Date = Date()) {
        self.home = home
        self.tmp = tmp
        self.now = now
    }

    /// `home` joined with a relative path such as "Library/Developer/Xcode/DerivedData".
    public func inHome(_ relative: String) -> URL {
        home.appendingPathComponent(relative, isDirectory: true)
    }
}

/// The `--only` filter names these.
public enum Group: String, CaseIterable, Codable, Sendable {
    case xcode, archives, node, python, rust, go, jvm, android, docker, models, agents, editors, brew

    /// Groups whose data can't be brought back: `clean` deletes them only when `--only` names them.
    public var isOptIn: Bool { self == .archives || self == .agents || self == .models }
}

/// What deleting an item costs the user, shown next to its size.
public enum Cost: Codable, Sendable, Equatable {
    /// Rebuilt on the next build, e.g. "next Xcode build is slower".
    case rebuild(String)
    /// Downloaded again when needed, e.g. "re-downloaded on next `npm install`".
    case redownload(String)
    /// Gone for good, e.g. "old Claude Code conversations".
    case lost(String)

    public var text: String {
        switch self {
        case .rebuild(let s), .redownload(let s), .lost(let s): return s
        }
    }

    /// "rebuild", "redownload" or "lost".
    public var kind: String {
        switch self {
        case .rebuild: "rebuild"
        case .redownload: "redownload"
        case .lost: "lost"
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, note }

    /// Flat JSON for scripts: {"kind": "lost", "note": "..."}.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(text, forKey: .note)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let note = try container.decode(String.self, forKey: .note)
        switch try container.decode(String.self, forKey: .kind) {
        case "rebuild": self = .rebuild(note)
        case "redownload": self = .redownload(note)
        case "lost": self = .lost(note)
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "unknown cost kind \(other)")
        }
    }
}

/// How `clean` frees the space.
public enum Action: Codable, Sendable, Equatable {
    /// Delete the located folder or file itself.
    case remove
    /// Delete what is inside the located folder, keep the folder.
    case removeContents
    /// Run a tool that owns the data, e.g. ["xcrun", "simctl", "delete", "unavailable"].
    case command([String])

    private enum CodingKeys: String, CodingKey { case kind, argv }

    /// Flat JSON for scripts: {"kind": "remove"}, {"kind": "removeContents"} or {"kind": "command", "argv": [...]}.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .remove: try container.encode("remove", forKey: .kind)
        case .removeContents: try container.encode("removeContents", forKey: .kind)
        case .command(let argv):
            try container.encode("command", forKey: .kind)
            try container.encode(argv, forKey: .argv)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "remove": self = .remove
        case "removeContents": self = .removeContents
        case "command": self = .command(try container.decode([String].self, forKey: .argv))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "unknown action kind \(other)")
        }
    }
}

/// One kind of developer junk in a fixed place, e.g. Xcode DerivedData.
public struct Rule: Sendable {
    public let id: String
    public let title: String
    public let group: Group
    public let cost: Cost
    public let action: Action
    /// Process names that must not be running while this is cleaned, e.g. ["Xcode"].
    public let blockedBy: [String]
    /// Existing paths only; an empty array means nothing to report.
    public let locate: @Sendable (Env) -> [URL]

    public init(id: String, title: String, group: Group, cost: Cost, action: Action = .remove,
                blockedBy: [String] = [], locate: @escaping @Sendable (Env) -> [URL]) {
        self.id = id
        self.title = title
        self.group = group
        self.cost = cost
        self.action = action
        self.blockedBy = blockedBy
        self.locate = locate
    }
}

/// Why an item is reported but left alone.
public enum SkipReason: String, Codable, Sendable {
    case recentlyModified = "modified in the last 3 hours"
    case openFiles = "files are open"
    case processRunning = "the owning app is running"
    case tooNew = "newer than --older-than"
}

/// One item the scan found.
public struct Finding: Codable, Sendable, Equatable {
    public var ruleID: String
    public var title: String
    public var group: Group
    public var path: String
    /// Bytes deleting it frees: hardlinks and APFS clones counted once.
    public var bytes: Int64
    public var lastModified: Date?
    public var cost: Cost
    public var action: Action
    public var skipped: SkipReason?

    public init(ruleID: String, title: String, group: Group, path: String, bytes: Int64,
                lastModified: Date?, cost: Cost, action: Action, skipped: SkipReason? = nil) {
        self.ruleID = ruleID
        self.title = title
        self.group = group
        self.path = path
        self.bytes = bytes
        self.lastModified = lastModified
        self.cost = cost
        self.action = action
        self.skipped = skipped
    }
}

/// Returns the paths among `candidates` that exist.
public func existing(_ candidates: [URL]) -> [URL] {
    candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
}

/// Direct subfolders of `url`, hidden ones included, sorted by name. Empty if `url` is missing.
public func subfolders(of url: URL) -> [URL] {
    let items = (try? FileManager.default.contentsOfDirectory(
        at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? []
    return items.filter {
        let values = try? $0.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values?.isDirectory == true && values?.isSymbolicLink != true
    }.sorted { $0.lastPathComponent < $1.lastPathComponent }
}

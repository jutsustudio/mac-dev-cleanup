import Foundation

/// A kind of per-project folder that can be rebuilt.
public struct ProjectKind: Sendable {
    /// Stable identifier, e.g. "project-node-modules".
    public let id: String
    /// Human-readable name shown in findings.
    public let title: String
    /// The `--only` group this kind belongs to.
    public let group: Group
    /// Folder name to look for inside a project.
    public let folder: String
    /// Sibling file names; any one present qualifies the folder. Empty means `insideMarker` decides.
    public let markers: [String]
    /// File that must exist inside the folder instead, e.g. "pyvenv.cfg".
    public let insideMarker: String?
    /// What deleting the folder costs the user.
    public let cost: Cost

    /// Creates a kind from all of its fields.
    public init(id: String, title: String, group: Group, folder: String,
                markers: [String], insideMarker: String?, cost: Cost) {
        self.id = id
        self.title = title
        self.group = group
        self.folder = folder
        self.markers = markers
        self.insideMarker = insideMarker
        self.cost = cost
    }
}

/// One build/dependency folder the scanner located.
public struct ProjectHit: Sendable, Equatable, Hashable {
    /// The matching kind's `id`.
    public let kindID: String
    /// The folder's location.
    public let url: URL

    /// Creates a hit from a kind id and the folder it matched.
    public init(kindID: String, url: URL) {
        self.kindID = kindID
        self.url = url
    }
}

/// Walks folders under given roots and returns build/dependency folders identified by markers.
public struct ProjectScanner: Sendable {
    /// Every per-project folder kind the scanner knows.
    public static let kinds: [ProjectKind] = [
        ProjectKind(id: "project-node-modules", title: "node_modules", group: .node, folder: "node_modules",
                    markers: ["package.json"], insideMarker: nil,
                    cost: .redownload("npm/pnpm/yarn install brings it back")),
        ProjectKind(id: "project-next", title: "Next.js build", group: .node, folder: ".next",
                    markers: ["package.json"], insideMarker: nil,
                    cost: .rebuild("next build recreates it")),
        ProjectKind(id: "project-turbo", title: "Turborepo cache", group: .node, folder: ".turbo",
                    markers: ["package.json"], insideMarker: nil,
                    cost: .rebuild("turbo recreates it")),
        ProjectKind(id: "project-nuxt", title: "Nuxt build", group: .node, folder: ".nuxt",
                    markers: ["package.json"], insideMarker: nil,
                    cost: .rebuild("nuxt recreates it")),
        ProjectKind(id: "project-rust-target", title: "Rust target", group: .rust, folder: "target",
                    markers: ["Cargo.toml"], insideMarker: nil,
                    cost: .rebuild("cargo build recompiles everything")),
        ProjectKind(id: "project-maven-target", title: "Maven target", group: .jvm, folder: "target",
                    markers: ["pom.xml"], insideMarker: nil,
                    cost: .rebuild("mvn package rebuilds it")),
        ProjectKind(id: "project-gradle", title: "Gradle build", group: .jvm, folder: "build",
                    markers: ["build.gradle", "build.gradle.kts"], insideMarker: nil,
                    cost: .rebuild("gradle build recreates it")),
        ProjectKind(id: "project-gradle-cache", title: "Gradle project cache", group: .jvm, folder: ".gradle",
                    markers: ["settings.gradle", "settings.gradle.kts", "build.gradle", "build.gradle.kts"],
                    insideMarker: nil, cost: .rebuild("recreated on next gradle run")),
        ProjectKind(id: "project-swiftpm", title: "SwiftPM build", group: .xcode, folder: ".build",
                    markers: ["Package.swift"], insideMarker: nil,
                    cost: .rebuild("swift build recompiles it")),
        ProjectKind(id: "project-pods", title: "CocoaPods Pods", group: .xcode, folder: "Pods",
                    markers: ["Podfile"], insideMarker: nil,
                    cost: .redownload("pod install brings it back")),
        ProjectKind(id: "project-venv", title: "Python venv", group: .python, folder: ".venv",
                    markers: [], insideMarker: "pyvenv.cfg",
                    cost: .redownload("recreate it and reinstall requirements")),
        ProjectKind(id: "project-venv-plain", title: "Python venv", group: .python, folder: "venv",
                    markers: [], insideMarker: "pyvenv.cfg",
                    cost: .redownload("recreate it and reinstall requirements")),
    ]

    private let roots: [URL]
    private let maxDepth: Int
    private let home: URL

    /// Kinds grouped by the folder name they look for.
    private static let kindsByFolder: [String: [ProjectKind]] = Dictionary(grouping: kinds, by: \.folder)
    /// Folder names the walk never enters once they failed to qualify.
    private static let neverEnteredNames: Set<String> = [".git", ".Trash", "node_modules"]

    /// Creates a scanner walking `roots` down to `maxDepth` folder levels below each root.
    /// The Library folder directly under `home` is never entered.
    public init(roots: [URL], maxDepth: Int = 8, home: URL = Env().home) {
        self.roots = roots
        self.maxDepth = maxDepth
        self.home = home
    }

    /// Returns hits sorted by path; never descends into a hit, a symlink, or a skipped folder.
    public func scan() -> [ProjectHit] {
        guard maxDepth > 0 else { return [] }
        let libraryPath = home.appendingPathComponent("Library").standardizedFileURL.path
        var hits = Set<ProjectHit>()
        for root in roots {
            var stack = [Frame(url: root, depth: 0)]
            while let frame = stack.popLast() {
                // Unreadable folders yield no subfolders and are skipped silently.
                for child in subfolders(of: frame.url) {
                    let name = child.lastPathComponent
                    if name == "Library" && child.standardizedFileURL.path == libraryPath { continue }
                    if let kind = (Self.kindsByFolder[name] ?? [])
                        .first(where: { Self.qualifies($0, folder: child, parent: frame.url) }) {
                        hits.insert(ProjectHit(kindID: kind.id, url: child))
                        continue
                    }
                    // A node_modules without a sibling package.json is skipped, not descended into.
                    if Self.neverEnteredNames.contains(name) { continue }
                    if name.hasPrefix(".") { continue }
                    if frame.depth + 1 < maxDepth {
                        stack.append(Frame(url: child, depth: frame.depth + 1))
                    }
                }
            }
        }
        return hits.sorted {
            $0.url.path == $1.url.path ? $0.kindID < $1.kindID : $0.url.path < $1.url.path
        }
    }

    /// True when a marker file sits next to the folder or the inside marker exists in it.
    private static func qualifies(_ kind: ProjectKind, folder: URL, parent: URL) -> Bool {
        if !kind.markers.isEmpty {
            return kind.markers.contains {
                FileManager.default.fileExists(atPath: parent.appendingPathComponent($0).path)
            }
        }
        guard let insideMarker = kind.insideMarker else { return false }
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent(insideMarker).path)
    }

    /// One folder pending enumeration during the walk.
    private struct Frame: Sendable {
        let url: URL
        let depth: Int
    }
}

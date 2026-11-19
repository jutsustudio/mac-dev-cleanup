import Foundation

/// What `Scan.run()` looks at: a group filter, an age floor and where project folders are searched.
public struct ScanOptions: Sendable {
    /// `nil` means every group; otherwise only these groups are reported.
    public var groups: Set<Group>?
    /// Seconds from `--older-than`; `nil` means no age floor.
    public var olderThan: TimeInterval?
    /// Roots the project-folder walk starts from, usually just the home directory.
    public var projectRoots: [URL]

    /// Creates options; `groups` and `olderThan` default to "no filter".
    public init(groups: Set<Group>? = nil, olderThan: TimeInterval? = nil, projectRoots: [URL]) {
        self.groups = groups
        self.olderThan = olderThan
        self.projectRoots = projectRoots
    }
}

/// Runs every fixed-location rule, the project-folder walk and the docker probe once,
/// applies the guards, and returns the findings sorted by bytes descending then path.
public struct Scan {
    private let env: Env
    private let options: ScanOptions
    private let rules: [Rule]
    private let runningProcesses: () -> Set<String>
    private let openFiles: ([String]) -> Set<String>
    private let docker: () -> Finding?

    /// Creates a scan; the closure defaults read the live system, tests pass fixed snapshots.
    public init(env: Env, options: ScanOptions, rules: [Rule] = Catalog.all,
                runningProcesses: @escaping () -> Set<String> = Guards.runningProcessNames,
                openFiles: @escaping ([String]) -> Set<String> = Guards.openFiles(under:),
                docker: @escaping () -> Finding? = { nil }) {
        self.env = env
        self.options = options
        self.rules = rules
        self.runningProcesses = runningProcesses
        self.openFiles = openFiles
        self.docker = docker
    }

    /// Every finding, sorted by bytes descending then path ascending.
    public func run() -> [Finding] {
        var sizer = Sizer()
        var entries: [(finding: Finding, blockedBy: [String])] = []

        // 1. Fixed-location rules.
        for rule in rules where Self.includes(rule.group, in: options.groups) {
            for url in rule.locate(env) {
                let measured = sizer.measure(url)
                guard measured.bytes != 0 else { continue }
                entries.append((Finding(ruleID: rule.id, title: rule.title, group: rule.group,
                                        path: url.path, bytes: measured.bytes,
                                        lastModified: measured.lastModified, cost: rule.cost,
                                        action: rule.action), rule.blockedBy))
            }
        }

        // 2. Per-project build folders.
        if options.groups.map({ !Self.kindsGroups.isDisjoint(with: $0) }) ?? true {
            for hit in ProjectScanner(roots: options.projectRoots, home: env.home).scan() {
                guard let kind = Self.kindsByID[hit.kindID],
                      Self.includes(kind.group, in: options.groups) else { continue }
                let measured = sizer.measure(hit.url)
                guard measured.bytes != 0 else { continue }
                entries.append((Finding(ruleID: kind.id, title: kind.title, group: kind.group,
                                        path: hit.url.path, bytes: measured.bytes,
                                        lastModified: measured.lastModified, cost: kind.cost,
                                        action: .remove), []))
            }
        }

        // 3. Docker, when its group is not filtered out. Prune has no age filter,
        //    so --older-than leaves Docker out instead of pruning everything.
        if options.olderThan == nil, Self.includes(.docker, in: options.groups), let finding = docker() {
            entries.append((finding, []))
        }

        // 4. Guards over everything found.
        let guards = Guards(now: env.now, olderThan: options.olderThan,
                            runningProcesses: runningProcesses(),
                            pathsWithOpenFiles: openFiles(entries.map { $0.finding.path }))
        let findings = entries.map { entry -> Finding in
            var finding = entry.finding
            finding.skipped = guards.skipReason(path: finding.path, lastModified: finding.lastModified,
                                                blockedBy: entry.blockedBy)
            return finding
        }

        // 5. Biggest first, ties by path.
        return findings.sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.path < $1.path }
    }

    /// Findings `clean` may delete: not skipped, and not in an opt-in group (archives, agents, models) unless `only` contains it.
    public static func cleanable(_ findings: [Finding], only: Set<Group>?) -> [Finding] {
        findings.filter { finding in
            guard finding.skipped == nil else { return false }
            if finding.group.isOptIn {
                return only?.contains(finding.group) ?? false
            }
            return true
        }
    }

    /// True when `group` passes the filter; a `nil` filter lets everything through.
    private static func includes(_ group: Group, in filter: Set<Group>?) -> Bool {
        filter?.contains(group) ?? true
    }

    /// Groups the project kinds cover; the walk runs only when the filter intersects them.
    private static let kindsGroups: Set<Group> = Set(ProjectScanner.kinds.map(\.group))

    /// Kinds by id, to map scanner hits back to their kind.
    private static let kindsByID: [String: ProjectKind] =
        Dictionary(uniqueKeysWithValues: ProjectScanner.kinds.map { ($0.id, $0) })
}

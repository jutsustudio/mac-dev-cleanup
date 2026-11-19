import Foundation

/// The subcommand the user asked for.
public enum Command: Equatable, Sendable {
    case scan, clean, list, version, help
}

/// One parsed command line, without argv[0].
public struct CLIArguments: Equatable, Sendable {
    /// The subcommand.
    public var command: Command
    /// Groups from `--only`; `nil` means all of them.
    public var only: Set<Group>?
    /// Seconds from `--older-than`; `nil` means no age floor.
    public var olderThan: TimeInterval?
    /// `--json` was given.
    public var json: Bool
    /// `--yes` was given; only valid with `clean`.
    public var yes: Bool
    /// `--path DIR`.
    public var path: String?

    /// Parses `args` (no argv[0]) or throws a `UsageError` naming the problem.
    public static func parse(_ args: [String]) throws -> CLIArguments {
        guard let first = args.first else {
            return CLIArguments(command: .help, only: nil, olderThan: nil, json: false, yes: false, path: nil)
        }
        let command: Command
        switch first {
        case "scan": command = .scan
        case "clean": command = .clean
        case "list": command = .list
        case "--version", "-v":
            return CLIArguments(command: .version, only: nil, olderThan: nil, json: false, yes: false, path: nil)
        case "--help", "-h":
            return CLIArguments(command: .help, only: nil, olderThan: nil, json: false, yes: false, path: nil)
        default:
            throw UsageError(message: "unknown command '\(first)'; expected scan, clean or list")
        }

        var only: Set<Group>?
        var olderThan: TimeInterval?
        var json = false
        var yes = false
        var path: String?

        var index = 1
        while index < args.count {
            let arg = args[index]
            index += 1
            switch arg {
            case "--json":
                json = true
            case "--yes":
                yes = true
            case "--only":
                only = try parseGroups(try nextValue(args, &index, option: "--only"))
            case "--older-than":
                olderThan = try parseAgeValue(try nextValue(args, &index, option: "--older-than"))
            case "--path":
                path = try directoryValue(try nextValue(args, &index, option: "--path"))
            case let option where option.hasPrefix("--only="):
                only = try parseGroups(String(option.dropFirst("--only=".count)))
            case let option where option.hasPrefix("--older-than="):
                olderThan = try parseAgeValue(String(option.dropFirst("--older-than=".count)))
            case let option where option.hasPrefix("--path="):
                path = try directoryValue(String(option.dropFirst("--path=".count)))
            default:
                throw UsageError(message: arg.hasPrefix("-")
                    ? "unknown option '\(arg)'" : "unexpected argument '\(arg)'")
            }
        }

        if yes && command != .clean {
            throw UsageError(message: "--yes is only valid with the clean command")
        }
        return CLIArguments(command: command, only: only, olderThan: olderThan, json: json, yes: yes, path: path)
    }

    /// The value of `option`: the next argument, or a `UsageError` when the command line ends first.
    private static func nextValue(_ args: [String], _ index: inout Int, option: String) throws -> String {
        guard index < args.count else { throw UsageError(message: "missing value for \(option)") }
        let value = args[index]
        index += 1
        return value
    }

    /// A directory argument; empty strings are refused.
    private static func directoryValue(_ value: String) throws -> String {
        guard !value.isEmpty, !value.hasPrefix("-") else { throw UsageError(message: "--path requires a directory") }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: value, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw UsageError(message: "--path: no such directory '\(value)'")
        }
        return value
    }

    /// Comma-separated group names; unknown names are `UsageError`s listing the valid ones.
    private static func parseGroups(_ text: String) throws -> Set<Group> {
        let names = text.split(separator: ",").map(String.init)
        var groups = Set<Group>()
        for name in names {
            guard let group = Group(rawValue: name) else {
                throw UsageError(message: "unknown group '\(name)'; valid groups: "
                    + Group.allCases.map(\.rawValue).joined(separator: ", "))
            }
            groups.insert(group)
        }
        guard !groups.isEmpty else { throw UsageError(message: "--only requires a group list") }
        return groups
    }

    /// `Guards.parseAge` or a `UsageError` naming the expected format.
    private static func parseAgeValue(_ text: String) throws -> TimeInterval {
        guard let age = Guards.parseAge(text) else {
            throw UsageError(message: "bad age '\(text)'; expected a number followed by h, d or w, e.g. 7d")
        }
        return age
    }
}

/// Why the command line could not be parsed; printed with the usage text before exiting 2.
public struct UsageError: Error, Equatable {
    /// One line naming the problem, without the usage text.
    public let message: String

    /// Creates the error shown for a malformed command line.
    public init(message: String) {
        self.message = message
    }
}

/// Version, usage text and the footer line.
public enum CLI {
    /// The version `--version` prints.
    public static let version = "0.1.0"

    /// The four commands and their options.
    public static let usage: String = """
        mac-dev-cleanup scan  [--only xcode,node,...] [--older-than 7d] [--json] [--path DIR]
        mac-dev-cleanup clean [--only ...] [--older-than ...] [--json] [--path DIR] [--yes]
        mac-dev-cleanup list
        mac-dev-cleanup --version
        """

    /// The one-line plug shown after `clean` finishes.
    public static let footer = "See what else fills your disk: https://pixeldisk.app"
}

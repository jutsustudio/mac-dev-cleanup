import DevCleanupCore
import Foundation

/// Writes one line to stderr, where errors and usage belong.
func printStderr(_ line: String) {
    FileHandle.standardError.write(Data((line + "\n").utf8))
}

/// The options every scan/clean shares: a `--path` root or the home directory.
func makeOptions(env: Env, _ arguments: CLIArguments) -> ScanOptions {
    let root = arguments.path.map { URL(fileURLWithPath: $0) } ?? env.home
    return ScanOptions(groups: arguments.only, olderThan: arguments.olderThan, projectRoots: [root])
}

/// The scan with the real Docker probe wired in.
func makeScan(env: Env, _ arguments: CLIArguments) -> Scan {
    Scan(env: env, options: makeOptions(env: env, arguments), docker: { Docker.finding(env: env) })
}

/// One line per fixed rule and one per project kind: `id  group  cost`.
func listRules() {
    for rule in Catalog.all {
        print("\(rule.id)  \(rule.group.rawValue)  \(rule.cost.text)")
    }
    for kind in ProjectScanner.kinds {
        print("\(kind.id)  \(kind.group.rawValue)  \(kind.cost.text)")
    }
}

/// The table (or JSON) of everything the scan found.
func performScan(_ arguments: CLIArguments) {
    let env = Env()
    let findings = makeScan(env: env, arguments).run()
    if arguments.json {
        do {
            print(try Format.json(findings))
        } catch {
            printStderr("error: \(error.localizedDescription)")
            exit(1)
        }
        return
    }
    print(Format.table(findings, home: env.home.path), terminator: "")
}

/// The dry-run table, or the actual deletions; returns the exit code.
func performClean(_ arguments: CLIArguments) -> Int32 {
    let env = Env()
    let findings = makeScan(env: env, arguments).run()
    let deletable = Scan.cleanable(findings, only: arguments.only)

    if !arguments.yes {
        if arguments.json {
            do {
                print(try Format.json(deletable))
            } catch {
                printStderr("error: \(error.localizedDescription)")
                return 1
            }
            return 0
        }
        print(Format.table(deletable, home: env.home.path), terminator: "")
        print("Dry run. Nothing was deleted. Run again with --yes to delete.")
        let excluded = findings.filter {
            $0.group.isOptIn && !(arguments.only?.contains($0.group) ?? false)
        }
        if !excluded.isEmpty {
            let names = Set(excluded.map(\.group)).sorted { $0.rawValue < $1.rawValue }
            let flags = names.map { "--only \($0.rawValue)" }.joined(separator: " / ")
            print("Also found \(excluded.count) \(names.map(\.rawValue).joined(separator: "/")) "
                + "item\(excluded.count == 1 ? "" : "s"); add \(flags) to clean them.")
        }
        return 0
    }

    let remover = Remover(env: env)
    var removals: [Removal] = []
    var freed: Int64 = 0
    var failures = 0
    for finding in deletable {
        do {
            removals.append(try remover.remove(finding))
            freed += finding.bytes
            if !arguments.json && finding.bytes >= Format.smallItemBytes {
                print("Removed \(Format.bytes(finding.bytes))  "
                    + "\(Format.shortPath(finding.path, home: env.home.path))")
            }
        } catch {
            failures += 1
            let message = describe(error)
            removals.append(Removal(date: Date(), ruleID: finding.ruleID, path: finding.path,
                                    bytes: finding.bytes, ok: false, error: message))
            if !arguments.json {
                print("Failed \(Format.shortPath(finding.path, home: env.home.path)): \(message)")
            }
        }
    }
    if arguments.json {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            print(String(decoding: try encoder.encode(removals), as: UTF8.self))
        } catch {
            printStderr("error: \(error.localizedDescription)")
            return 1
        }
        return failures == 0 ? 0 : 1
    }
    let removed = removals.filter(\.ok).count
    print("Freed \(Format.bytes(freed)) from \(removed) item\(removed == 1 ? "" : "s").")
    if removals.contains(where: \.ok) {
        print(CLI.footer)
    }
    return failures == 0 ? 0 : 1
}

/// One readable line for why a removal failed.
func describe(_ error: Error) -> String {
    if let removeError = error as? RemoveError {
        switch removeError {
        case .skipped: return "skipped by guards"
        case .outsideHome: return "outside the home directory"
        case .tooShallow: return "too shallow to delete safely"
        case .commandFailed(let status): return "command exited with status \(status)"
        case .io(let message): return message
        }
    }
    return error.localizedDescription
}

let arguments: CLIArguments
do {
    arguments = try CLIArguments.parse(Array(CommandLine.arguments.dropFirst()))
} catch let error as UsageError {
    printStderr(error.message)
    printStderr(CLI.usage)
    exit(2)
} catch {
    printStderr("unexpected error: \(error)")
    exit(2)
}

switch arguments.command {
case .help:
    print(CLI.usage)
case .version:
    print("mac-dev-cleanup \(CLI.version)")
case .list:
    listRules()
case .scan:
    performScan(arguments)
case .clean:
    exit(performClean(arguments))
}
exit(0)

import Foundation
import Testing
@testable import DevCleanupCore

@Suite struct CLITests {
    @Test func parsesPlainScan() throws {
        let parsed = try CLIArguments.parse(["scan"])
        #expect(parsed == CLIArguments(command: .scan, only: nil, olderThan: nil,
                                       json: false, yes: false, path: nil))
    }

    @Test func parsesCleanWithYesAndOnly() throws {
        let parsed = try CLIArguments.parse(["clean", "--yes", "--only", "xcode,node"])
        #expect(parsed == CLIArguments(command: .clean, only: [.xcode, .node], olderThan: nil,
                                       json: false, yes: true, path: nil))
    }

    @Test func parsesInlineOnlyForm() throws {
        let parsed = try CLIArguments.parse(["scan", "--only=xcode"])
        #expect(parsed.command == .scan)
        #expect(parsed.only == [.xcode])
    }

    @Test func parsesOlderThan() throws {
        let parsed = try CLIArguments.parse(["scan", "--older-than", "2w"])
        #expect(parsed.command == .scan)
        #expect(parsed.olderThan == 2 * 7 * 86400.0)
        #expect(parsed.only == nil)
    }

    @Test func parsesJsonPathAndInlineAge() throws {
        let parsed = try CLIArguments.parse(["scan", "--json", "--path", "/tmp", "--older-than=12h"])
        #expect(parsed.json)
        #expect(parsed.path == "/tmp")
        #expect(parsed.olderThan == 12 * 3600.0)
    }

    @Test func parsesList() throws {
        #expect(try CLIArguments.parse(["list"]).command == .list)
    }

    @Test func parsesVersionAndHelpFlags() throws {
        #expect(try CLIArguments.parse(["--version"]).command == .version)
        #expect(try CLIArguments.parse(["-v"]).command == .version)
        #expect(try CLIArguments.parse(["--help"]).command == .help)
        #expect(try CLIArguments.parse(["-h"]).command == .help)
        #expect(try CLIArguments.parse([]).command == .help)
    }

    @Test func badGroupIsUsageErrorNamingValidGroups() throws {
        do {
            _ = try CLIArguments.parse(["scan", "--only", "xcode,bogus"])
            Issue.record("parsing an unknown group should have failed")
        } catch let error as UsageError {
            #expect(error.message.contains("bogus"))
            #expect(error.message.contains("xcode"))
            #expect(error.message.contains("brew"))
        }
    }

    @Test func badAgeIsUsageError() throws {
        #expect(throws: UsageError.self) { try CLIArguments.parse(["scan", "--older-than", "soon"]) }
    }

    @Test func yesWithScanIsUsageError() throws {
        #expect(throws: UsageError.self) { try CLIArguments.parse(["scan", "--yes"]) }
    }

    @Test func unknownFlagIsUsageError() throws {
        #expect(throws: UsageError.self) { try CLIArguments.parse(["scan", "--bogus"]) }
    }

    @Test func missingValueIsUsageError() throws {
        #expect(throws: UsageError.self) { try CLIArguments.parse(["scan", "--only"]) }
        #expect(throws: UsageError.self) { try CLIArguments.parse(["scan", "--older-than"]) }
        #expect(throws: UsageError.self) { try CLIArguments.parse(["clean", "--path"]) }
    }

    @Test func pathMustBeAnExistingDirectory() throws {
        #expect(throws: UsageError.self) { try CLIArguments.parse(["scan", "--path", "--json"]) }
        #expect(throws: UsageError.self) { try CLIArguments.parse(["scan", "--path", "/no/such/dir/here"]) }
        #expect(try CLIArguments.parse(["scan", "--path", "/tmp"]).path == "/tmp")
    }

    @Test func unknownCommandIsUsageError() throws {
        #expect(throws: UsageError.self) { try CLIArguments.parse(["explode"]) }
    }

    @Test func usageListsTheFourCommandsAndTheirOptions() {
        let lines = CLI.usage.split(separator: "\n").map(String.init)
        #expect(lines.count == 4)
        #expect(lines[0] == "mac-dev-cleanup scan  [--only xcode,node,...] [--older-than 7d] [--json] [--path DIR]")
        #expect(lines[1] == "mac-dev-cleanup clean [--only ...] [--older-than ...] [--json] [--path DIR] [--yes]")
        #expect(lines[2] == "mac-dev-cleanup list")
        #expect(lines[3] == "mac-dev-cleanup --version")
        #expect(CLI.version == "0.1.0")
        #expect(CLI.footer == "See what else fills your disk: https://pixeldisk.app")
    }
}

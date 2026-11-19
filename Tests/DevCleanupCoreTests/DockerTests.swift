import Foundation
import Testing
@testable import DevCleanupCore

@Suite struct DockerTests {
    @Test func findingSumsImagesContainersAndBuildCacheOnly() throws {
        let home = try makeFixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let env = Env(home: home)
        let expectedArgv = ["docker", "system", "df", "--format", "{{json .}}"]
        let sample = """
            {"Active":"2","Reclaimable":"1.2GB (40%)","Size":"3GB","TotalCount":"5","Type":"Images"}
            {"Active":"0","Reclaimable":"256MB (100%)","Size":"256MB","TotalCount":"3","Type":"Containers"}
            {"Active":"5","Reclaimable":"900MB (80%)","Size":"1.1GB","TotalCount":"7","Type":"Local Volumes"}
            {"Active":"0","Reclaimable":"12.3kB (100%)","Size":"12.3kB","TotalCount":"20","Type":"Build Cache"}
            """
        // A wrong argv returns non-zero, so a regression in the query fails here too.
        let runner: Docker.Runner = { argv in argv == expectedArgv ? (0, sample) : (1, "") }
        let finding = try #require(Docker.finding(env: env, runner: runner))
        #expect(finding.ruleID == "docker-prune")
        #expect(finding.title == "Docker unused images, stopped containers, build cache")
        #expect(finding.group == .docker)
        #expect(finding.bytes == 1_200_000_000 + 256_000_000 + 12_300)
        #expect(finding.path == home.appendingPathComponent(".docker").path)
        #expect(finding.lastModified == nil)
        #expect(finding.skipped == nil)
        #expect(finding.cost == .lost("stopped containers' data is deleted; local images rebuild, others pull again"))
        #expect(finding.action == .command(["docker", "system", "prune", "-af"]))
    }

    @Test func zeroReclaimableReturnsNil() throws {
        let home = try makeFixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let env = Env(home: home)
        let sample = """
            {"Active":"1","Reclaimable":"0B (0%)","Size":"1GB","TotalCount":"4","Type":"Images"}
            {"Active":"0","Reclaimable":"0B (0%)","Size":"0B","TotalCount":"0","Type":"Containers"}
            {"Active":"3","Reclaimable":"2GB (100%)","Size":"2GB","TotalCount":"6","Type":"Local Volumes"}
            {"Active":"0","Reclaimable":"0B (0%)","Size":"0B","TotalCount":"0","Type":"Build Cache"}
            """
        let runner: Docker.Runner = { _ in (0, sample) }
        #expect(Docker.finding(env: env, runner: runner) == nil)
    }

    @Test func nonZeroStatusReturnsNil() throws {
        let home = try makeFixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let env = Env(home: home)
        let sample = """
            {"Active":"2","Reclaimable":"1.2GB (40%)","Size":"3GB","TotalCount":"5","Type":"Images"}
            """
        // 127 is what /usr/bin/env exits with when docker is not installed.
        let runner: Docker.Runner = { _ in (127, sample) }
        #expect(Docker.finding(env: env, runner: runner) == nil)
    }

    @Test func emptyOutputReturnsNil() throws {
        let home = try makeFixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let env = Env(home: home)
        #expect(Docker.finding(env: env, runner: { _ in (0, "") }) == nil)
        #expect(Docker.finding(env: env, runner: { _ in (0, "  \n \n") }) == nil)
    }

    @Test func parseSizeUnderstandsDockerFormats() {
        #expect(Docker.parseSize("0B") == 0)
        #expect(Docker.parseSize("512B") == 512)
        #expect(Docker.parseSize("12.3kB") == 12_300)
        #expect(Docker.parseSize("512MB") == 512_000_000)
        #expect(Docker.parseSize("1.234GB") == 1_234_000_000)
        #expect(Docker.parseSize("1.5GB (40%)") == 1_500_000_000)
        #expect(Docker.parseSize("2TB") == 2_000_000_000_000)
        #expect(Docker.parseSize("1PB") == 1_000_000_000_000_000)
    }

    @Test func parseSizeRejectsGarbage() {
        #expect(Docker.parseSize("nonsense") == nil)
        #expect(Docker.parseSize("") == nil)
        #expect(Docker.parseSize("12.3 XB") == nil)
        #expect(Docker.parseSize("GB") == nil)
        #expect(Docker.parseSize("1.2.3GB") == nil)
        #expect(Docker.parseSize("-5MB") == nil)
    }

    @Test func makeRunnerReadsLargeOutputWithoutDeadlock() {
        let runner = Docker.makeRunner(timeout: 5)
        let (status, output) = runner(["sh", "-c", "head -c 200000 /dev/zero | tr '\\0' a"])
        #expect(status == 0)
        #expect(output == String(repeating: "a", count: 200_000))
    }

    @Test func makeRunnerKillsAProcessThatIgnoresSIGTERM() {
        let started = Date()
        let runner = Docker.makeRunner(timeout: 1)
        let (status, _) = runner(["sh", "-c", "trap '' TERM; sleep 20"])
        #expect(status == -1)
        #expect(Date().timeIntervalSince(started) < 4)
    }

    @Test func missingBinaryReturnsNonZeroAndAbsentDockerYieldsNil() throws {
        let runner = Docker.makeRunner(timeout: 5)
        let (status, _) = runner(["nosuchbinary-xyz"])
        #expect(status != 0)
        let home = try makeFixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let env = Env(home: home)
        #expect(Docker.finding(env: env, runner: { _ in (127, "") }) == nil)
    }

    @Test func garbageLinesAroundOneValidLineAreSkipped() throws {
        let home = try makeFixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let env = Env(home: home)
        let sample = """
            WARNING: docker is acting up
            this line is not json
            {"Active":"2","Reclaimable":"1.2GB (40%)","Size":"3GB","TotalCount":"5","Type":"Images"}
            """
        let runner: Docker.Runner = { _ in (0, sample) }
        let finding = try #require(Docker.finding(env: env, runner: runner))
        #expect(finding.bytes == 1_200_000_000)
    }
}

/// Creates a throwaway fixture directory with a UUID name under the system temp folder.
private func makeFixture() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("docker-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

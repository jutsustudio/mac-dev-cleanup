import Darwin
import Foundation
import Testing
@testable import DevCleanupCore

@Suite struct SizerTests {
    @Test func folderWithTwoFilesCountsBoth() throws {
        let dir = try makeFixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeHundredKilobytes(to: dir.appendingPathComponent("first.bin"))
        try writeHundredKilobytes(to: dir.appendingPathComponent("second.bin"))
        var sizer = Sizer()
        let result = sizer.measure(dir)
        #expect(result.bytes >= 200_000)
        #expect(result.lastModified != nil)
    }

    @Test func hardlinkInsideOneFolderCountsOnce() throws {
        let dir = try makeFixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("file.bin")
        try writeHundredKilobytes(to: file)
        try FileManager.default.linkItem(at: file, to: dir.appendingPathComponent("link.bin"))
        var sizer = Sizer()
        var reference = Sizer()
        let folder = sizer.measure(dir)
        let single = reference.measure(file)
        #expect(folder.bytes == single.bytes)
    }

    @Test func hardlinkAcrossFoldersCountedOncePerSizer() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let dirA = root.appendingPathComponent("a", isDirectory: true)
        let dirB = root.appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        let shared = dirA.appendingPathComponent("shared.bin")
        try writeHundredKilobytes(to: shared)
        try FileManager.default.linkItem(at: shared, to: dirB.appendingPathComponent("shared.bin"))
        var sizer = Sizer()
        let first = sizer.measure(dirA)
        let second = sizer.measure(dirB)
        #expect(first.bytes > 0)
        #expect(second.bytes == 0)
    }

    @Test func cloneCountsOnlyPrivateBytes() throws {
        let dir = try makeFixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let original = dir.appendingPathComponent("original.bin")
        try writeHundredKilobytes(to: original)
        var sizer = Sizer()
        let originalBytes = sizer.measure(original).bytes
        let clone = dir.appendingPathComponent("clone.bin")
        try FileManager.default.copyItem(at: original, to: clone)
        let cloneBytes = sizer.measure(clone).bytes
        #expect(originalBytes > 0)
        #expect(cloneBytes >= 0)
        #expect(cloneBytes <= originalBytes)
        if isAPFS(dir) {
            #expect(cloneBytes < originalBytes)
        }
    }

    @Test func symlinkCountsZeroAndMissingPathIsEmpty() throws {
        let dir = try makeFixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let big = dir.appendingPathComponent("big.bin")
        try Data(repeating: 0x55, count: 1024 * 1024).write(to: big)
        try FileManager.default.createSymbolicLink(
            at: dir.appendingPathComponent("big.link"), withDestinationURL: big)
        var sizer = Sizer()
        let link = sizer.measure(dir.appendingPathComponent("big.link"))
        #expect(link.bytes == 0)
        var reference = Sizer()
        var walker = Sizer()
        let direct = reference.measure(big).bytes
        let folder = walker.measure(dir).bytes
        #expect(folder == direct)
        var empty = Sizer()
        let missing = empty.measure(dir.appendingPathComponent("missing.bin"))
        #expect(missing.bytes == 0)
        #expect(missing.lastModified == nil)
    }
}

/// Creates a throwaway fixture directory with a UUID name under the system temp folder.
private func makeFixture() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("sizer-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Writes 100 KB of filler data to `url`.
private func writeHundredKilobytes(to url: URL) throws {
    try Data(repeating: 0x55, count: 100 * 1024).write(to: url)
}

/// True when the volume holding `url` is APFS, where copying a file creates a clone.
private func isAPFS(_ url: URL) -> Bool {
    var info = statfs()
    guard statfs(url.path, &info) == 0 else { return false }
    let type = withUnsafeBytes(of: info.f_fstypename) { raw -> String in
        String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
    }
    return type == "apfs"
}

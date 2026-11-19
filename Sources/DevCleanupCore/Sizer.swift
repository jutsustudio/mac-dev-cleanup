import Darwin
import Foundation

/// Bytes of `path` that are not shared with another file; nil when the volume lacks the attribute.
private func privateSize(_ path: String) -> Int64? {
    var list = attrlist()
    list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
    list.forkattr = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE)
    var buffer = [UInt8](repeating: 0, count: 64)
    let options = UInt32(FSOPT_NOFOLLOW) | UInt32(FSOPT_ATTR_CMN_EXTENDED)
    guard getattrlist(path, &list, &buffer, buffer.count, options) == 0 else { return nil }
    let length = buffer.withUnsafeBytes { $0.load(as: UInt32.self) }
    guard length >= 12 else { return nil }
    return buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: Int64.self) }
}

/// True when `mode` describes a regular file.
private func isRegularFile(_ mode: mode_t) -> Bool {
    mode & mode_t(S_IFMT) == mode_t(S_IFREG)
}

/// True when `mode` describes a directory.
private func isDirectory(_ mode: mode_t) -> Bool {
    mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
}

/// Measures how many bytes deleting a path would free, counting each hardlinked inode once.
/// APFS clones count only their private bytes, so a fresh clone measures as 0.
public struct Sizer: Sendable {
    /// Identity of one inode on one volume, used to deduplicate hardlinks.
    private struct InodeKey: Hashable, Sendable {
        var dev: UInt64
        var ino: UInt64
    }

    /// Inodes of hardlinked files this sizer has already counted.
    private var countedInodes: Set<InodeKey> = []

    /// Creates a sizer with no inode counted yet.
    public init() {}

    /// Bytes freed by deleting `url` (file or folder, recursive) and the newest modification date inside it.
    /// Hardlinks: a (st_dev, st_ino) seen before, in this call or an earlier call on the same Sizer, adds 0.
    public mutating func measure(_ url: URL) -> (bytes: Int64, lastModified: Date?) {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return (0, nil) }
        if isRegularFile(st.st_mode) {
            return (countedBytes(url.path, st), modificationDate(st))
        }
        guard isDirectory(st.st_mode) else { return (0, nil) }
        var bytes: Int64 = 0
        var lastModified: Date? = modificationDate(st)
        measureContents(of: url, bytes: &bytes, lastModified: &lastModified)
        return (bytes, lastModified)
    }

    /// Adds the bytes and mtimes of everything below `directory` to the running totals.
    private mutating func measureContents(of directory: URL, bytes: inout Int64, lastModified: inout Date?) {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [],
            errorHandler: { _, _ in true }
        ) else { return }
        while let raw: Any = enumerator.nextObject() {
            guard let child = raw as? URL else { continue }
            var st = stat()
            guard lstat(child.path, &st) == 0 else { continue }
            let modified = modificationDate(st)
            if isDirectory(st.st_mode) {
                lastModified = max(lastModified ?? .distantPast, modified)
            } else if isRegularFile(st.st_mode) {
                // note: clones of each other inside one folder each report 0 private bytes, so such a
                // folder under-reports (never over-reports); exact needs extent-level accounting.
                bytes += countedBytes(child.path, st)
                lastModified = max(lastModified ?? .distantPast, modified)
            } else {
                enumerator.skipDescendants()
            }
        }
    }

    /// Allocated bytes of one regular file; a hardlink whose inode this sizer already counted adds 0.
    private mutating func countedBytes(_ path: String, _ st: stat) -> Int64 {
        if st.st_nlink > 1 {
            let key = InodeKey(dev: UInt64(st.st_dev), ino: UInt64(st.st_ino))
            if countedInodes.contains(key) { return 0 }
            countedInodes.insert(key)
        }
        return privateSize(path) ?? Int64(st.st_blocks) * 512
    }

    /// The modification date recorded in a stat result, including sub-second precision.
    private func modificationDate(_ st: stat) -> Date {
        let time = st.st_mtimespec
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1_000_000_000)
    }
}

import Foundation
import Darwin

public struct ConfigurationSnapshot: Sendable {
    public var configuration: Configuration
    public var data: Data?
    public var warnings: [String] = []
}
public enum ConfigurationConflict: LocalizedError {
    case changed(String)
    public var errorDescription: String? {
        switch self { case .changed(let path): "別のプロセスでも設定が変更されました（\(path)）。編集中の内容は保持しています。再読込するか、変更を見直してください。" }
    }
}

public struct ConfigurationStore: Sendable {
    public let url: URL
    public init(url: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/ReKey/rekey.json")) { self.url = url }
    public var resolvedURL: URL { url.resolvingSymlinksInPath() }
    public func load() throws -> Configuration { try snapshot().configuration }
    /// Changes whenever the file is replaced or rewritten; nil while it does not exist.
    public struct FileStamp: Equatable, Sendable { let inode: UInt64, size: Int64, seconds: Int, nanoseconds: Int }
    /// A cheap check before reading and validating the whole file.
    public func stamp() -> FileStamp? {
        var st = stat()
        guard stat(resolvedURL.path, &st) == 0 else { return nil }
        return FileStamp(inode: st.st_ino, size: st.st_size, seconds: st.st_mtimespec.tv_sec, nanoseconds: st.st_mtimespec.tv_nsec)
    }
    public func snapshot() throws -> ConfigurationSnapshot { try read(at: resolvedURL) }
    /// Merge the editor's delta with the current file while holding the same lock as the Agent.
    public func save(_ config: Configuration, basedOn baseline: Data?) throws -> ConfigurationSnapshot {
        try withLock { target in
            let latest = try read(at: target)
            let proposed = try config.encoded()
            if latest.data == baseline { return try commit(config, encoded: proposed, at: target, previous: latest.data) }
            guard let baseline, let current = latest.data else { throw ConfigurationConflict.changed("rekey.json") }
            let decoder = JSONDecoder()
            let base = try decoder.decode(JSONValue.self, from: baseline)
            let desired = try decoder.decode(JSONValue.self, from: proposed)
            let disk = try decoder.decode(JSONValue.self, from: current)
            func selected(_ value: JSONValue) -> String? {
                value["profiles"]?.array?.first { $0["selected"] == .bool(true) }?["id"]?.string
            }
            if selected(base) != selected(desired), selected(base) != selected(disk), selected(desired) != selected(disk) {
                throw ConfigurationConflict.changed("profiles.selected")
            }
            let value = try Self.merge(base: base, desired: desired, current: disk, path: "root")
            let merged = try decoder.decode(Configuration.self, from: JSONEncoder().encode(value))
            return try commit(merged, encoded: merged.encoded(), at: target, previous: latest.data)
        }
    }
    /// Read, mutate and commit in one transaction so profile/shortcut changes never overwrite UI edits.
    @discardableResult public func update(_ edit: (inout Configuration) throws -> Void) throws -> ConfigurationSnapshot {
        try withLock { target in
            let latest = try read(at: target)
            var config = latest.configuration
            try edit(&config)
            return try commit(config, encoded: config.encoded(), at: target, previous: latest.data)
        }
    }
    private func read(at target: URL) throws -> ConfigurationSnapshot {
        let fd = open(target.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        if fd < 0 {
            if errno == ENOENT { return .init(configuration: Configuration(), data: nil) }
            throw posix()
        }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0 else { throw posix() }
        guard st.st_uid == getuid(), (st.st_mode & S_IFMT) == S_IFREG, (st.st_mode & 0o077) == 0, st.st_size >= 0, st.st_size <= 4 * 1024 * 1024 else {
            throw ConfigError.invalid("設定ファイルの所有者・アクセス権・サイズが不正です。")
        }
        var data = Data(count: Int(st.st_size))
        try data.withUnsafeMutableBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.read(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw posix(count == 0 ? EIO : errno) }
                offset += count
            }
        }
        var after = stat()
        guard fstat(fd, &after) == 0 else { throw posix() }
        guard st.st_size == after.st_size, st.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, st.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else { throw ConfigurationConflict.changed("rekey.json") }
        return .init(configuration: try Configuration.decode(data), data: data)
    }
    private func withLock<T>(_ operation: (URL) throws -> T) throws -> T {
        let target = resolvedURL
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let lockURL = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).lock")
        let fd = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw posix() }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0 else { throw posix() }
        guard st.st_uid == getuid(), (st.st_mode & S_IFMT) == S_IFREG, st.st_mode & 0o077 == 0 else { throw ConfigError.invalid("設定ロックファイルの所有者またはアクセス権が不正です。") }
        let deadline = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) + 2_000_000_000
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            if errno == EINTR { continue }
            guard errno == EWOULDBLOCK || errno == EAGAIN else { throw posix() }
            guard clock_gettime_nsec_np(CLOCK_UPTIME_RAW) < deadline else { throw ConfigError.invalid("別のプロセスが設定を保存中です。しばらくしてから再試行してください。") }
            usleep(2_000)
        }
        defer { flock(fd, LOCK_UN) }
        guard resolvedURL == target else { throw ConfigurationConflict.changed("symlink") }
        return try operation(target)
    }
    /// `data` must come from `config.encoded()`, which already validated it.
    private func commit(_ config: Configuration, encoded data: Data, at target: URL, previous: Data?) throws -> ConfigurationSnapshot {
        if previous == data { return .init(configuration: config, data: previous) }
        let fm = FileManager.default
        let backups = target.deletingLastPathComponent().appendingPathComponent("Backups")
        if let previous {
            try fm.createDirectory(at: backups, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let backup = backups.appendingPathComponent("rekey.json.bak.\(stamp)-\(UUID().uuidString)")
            try writePrivate(previous, to: backup)
            try syncDirectory(backups)
        }
        let temporary = target.deletingLastPathComponent().appendingPathComponent(".rekey-\(UUID().uuidString).tmp")
        defer { try? fm.removeItem(at: temporary) }
        try writePrivate(data, to: temporary)
        guard resolvedURL == target else { throw ConfigurationConflict.changed("symlink") }
        guard rename(temporary.path, target.path) == 0 else { throw posix() }
        var result = ConfigurationSnapshot(configuration: config, data: data)
        do { try syncDirectory(target.deletingLastPathComponent()) }
        catch { result.warnings.append("設定は保存しましたが、ディレクトリの同期に失敗しました: \(error.localizedDescription)") }
        do {
            if fm.fileExists(atPath: backups.path) {
                let files = try fm.contentsOfDirectory(at: backups, includingPropertiesForKeys: [.creationDateKey]).filter { $0.lastPathComponent.hasPrefix("rekey.json.bak.") }
                let dated: [(URL, Date)] = try files.map { file in
                    let date = try file.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                    return (file, date)
                }
                let ordered = dated.sorted { left, right in
                    if left.1 == right.1 { return left.0.lastPathComponent > right.0.lastPathComponent }
                    return left.1 > right.1
                }
                for old in ordered.dropFirst(20) { try fm.removeItem(at: old.0) }
            }
        } catch { result.warnings.append("設定は保存しましたが、古いバックアップの整理に失敗しました: \(error.localizedDescription)") }
        return result
    }
    private func writePrivate(_ data: Data, to target: URL) throws {
        let fd = open(target.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw posix() }
        var succeeded = false
        defer { close(fd); if !succeeded { unlink(target.path) } }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw posix(count == 0 ? EIO : errno) }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw posix() }
        if fcntl(fd, F_FULLFSYNC) != 0, errno != EINVAL && errno != ENOTSUP { throw posix() }
        succeeded = true
    }
    private func syncDirectory(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw posix() }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw posix() }
    }
    private func posix(_ code: Int32 = errno) -> POSIXError { POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }

    private static func merge(base: JSONValue?, desired: JSONValue?, current: JSONValue?, path: String) throws -> JSONValue? {
        if desired == base { return current }
        if current == base || desired == current { return desired }
        if case .object(let b) = base, case .object(let d) = desired, case .object(let c) = current {
            var result: [String: JSONValue] = [:]
            for key in Set(b.keys).union(d.keys).union(c.keys) {
                result[key] = try merge(base: b[key], desired: d[key], current: c[key], path: "\(path).\(key)")
            }
            return .object(result)
        }
        if case .array(let b) = base, case .array(let d) = desired, case .array(let c) = current {
            func keyed(_ values: [JSONValue]) throws -> [Data: JSONValue]? {
                var result: [Data: JSONValue] = [:]
                let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
                for value in values {
                    guard let id = value["id"] else { return nil }
                    let key = try encoder.encode(id)
                    guard result[key] == nil else { return nil }
                    result[key] = value
                }
                return result
            }
            if let bb = try keyed(b), let dd = try keyed(d), let cc = try keyed(c) {
                let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
                let baseOrder = try b.map { try encoder.encode($0["id"]!) }
                let desiredOrder = try d.map { try encoder.encode($0["id"]!) }
                let currentOrder = try c.map { try encoder.encode($0["id"]!) }
                let common = Set(bb.keys).intersection(dd.keys).intersection(cc.keys)
                let baseCommon = baseOrder.filter { common.contains($0) }
                let desiredCommon = desiredOrder.filter { common.contains($0) }
                let currentCommon = currentOrder.filter { common.contains($0) }
                if desiredCommon != baseCommon && currentCommon != baseCommon && desiredCommon != currentCommon { throw ConfigurationConflict.changed("\(path).order") }
                var order = desiredCommon == baseCommon ? currentOrder : desiredOrder
                let other = desiredCommon == baseCommon ? desiredOrder : currentOrder
                for (index, id) in other.enumerated() where !order.contains(id) {
                    if !other[(index + 1)...].contains(where: { order.contains($0) }) { order.append(id) }
                    else if let previous = other[..<index].last(where: { order.contains($0) }), let position = order.firstIndex(of: previous) { order.insert(id, at: position + 1) }
                    else { order.insert(id, at: 0) }
                }
                var values: [JSONValue] = []
                for id in order { if let v = try merge(base: bb[id], desired: dd[id], current: cc[id], path: "\(path)[id]") { values.append(v) } }
                // A removed item still present in the other branch must participate in conflict detection.
                for id in bb.keys where !order.contains(id) { _ = try merge(base: bb[id], desired: dd[id], current: cc[id], path: "\(path)[id]") }
                return .array(values)
            }
        }
        throw ConfigurationConflict.changed(path)
    }
}

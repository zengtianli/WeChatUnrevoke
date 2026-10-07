// Shared Apple configuration transfer. Vendor this file; edit only this source.
import Foundation
#if os(macOS)
import AppKit
import Darwin
#endif

/// Only these JSON field paths may leave the device. Other fields survive imports.
/// Dotted fields are literal; JSON Pointer fields support a segment ending in * for preference maps.
struct AppConfigurationFile {
    let url: URL
    let keys: [String]
    let validateValue: ((Any) throws -> Void)?
    init(url: URL, keys: [String]) { self.url = url; self.keys = keys; self.validateValue = nil }
    init(url: URL, keys: [String], validateValue: @escaping (Any) throws -> Void) { self.url = url; self.keys = keys; self.validateValue = validateValue }
}

/// Opt-in settings sync; permissions, credentials and business data need explicit product exclusion.
/// File indices and allowlisted keys are the portable identity, not local file paths.
/// Sandboxed Mac targets opt into the provisioned KVS transport with APP_LIFECYCLE_KVS.
final class AppConfiguration: NSObject {
    var onChange: (() -> Void)?
    var hasSettings: Bool { !defaultsKeys.isEmpty || files.contains { !$0.keys.isEmpty } }
    var enabled: Bool { defaults.bool(forKey: enabledKey) }
    private(set) var status = "iCloud 配置同步已关闭"
    private let productID: String
    private let defaultsKeys: [String]
    private let files: [AppConfigurationFile]
    private let defaults: UserDefaults
    private let worker = DispatchQueue(label: "cyou.tianli.configuration", qos: .utility)
    private var observers: [NSObjectProtocol] = []
    private let localLock = NSRecursiveLock()
    #if os(macOS)
    private var workspaceObserver: NSObjectProtocol?
    #endif
    private var started = false
    private var applying = false
    private var lastFingerprint: Data?
    private var presenter: ConfigurationPresenter?
    #if os(macOS)
    private var localPresenters: [ConfigurationPresenter] = []
    #endif
    private let enabledKey = "appLifecycle.configuration.enabled"
    private let localDirectory: URL
    private var stateURL: URL { localDirectory.appendingPathComponent("state.json") }
    private var importedURL: URL { localDirectory.appendingPathComponent("pending-import.json") }
    #if os(macOS)
    /// The sentence `status` holds, kept beside state.json for another process to read: the command line reports what
    /// the running window shows. A file, never a preference (a stored preference would start another sync pass); it is
    /// not exported, not synced and presented by nothing. The app keeps the default name. A command process names its
    /// own record, so a short-lived command never replaces the running window's sentence.
    static let appStatusRecord = "status.json"
    var statusRecordName = AppConfiguration.appStatusRecord
    struct StatusRecord { let status: String; let at: TimeInterval; let pid: Int32 }
    func statusRecord(named name: String = AppConfiguration.appStatusRecord) -> StatusRecord? {
        guard let data = try? Data(contentsOf: localDirectory.appendingPathComponent(name)),
              let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let status = value["status"] as? String, let at = (value["at"] as? NSNumber)?.doubleValue,
              let pid = (value["pid"] as? NSNumber)?.int32Value else { return nil }
        return StatusRecord(status: status, at: at, pid: pid)
    }
    private func recordStatus(_ value: String) {
        let record: [String: Any] = ["status": value, "at": Date().timeIntervalSince1970, "pid": Int(ProcessInfo.processInfo.processIdentifier)]
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
        try? FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? data.write(to: localDirectory.appendingPathComponent(statusRecordName), options: .atomic)
    }
    #endif
    private let isolated: Bool

    init(productID: String, defaultsKeys: [String] = [], files: [AppConfigurationFile] = [], defaults: UserDefaults = .standard) {
        self.productID = productID
        self.defaultsKeys = Array(Set(defaultsKeys)).sorted()
        self.files = files
        self.defaults = defaults
        let env = ProcessInfo.processInfo.environment
        isolated = env["APP_LIFECYCLE_SUPPORT_DIR"] != nil
        if let p = env["APP_LIFECYCLE_SUPPORT_DIR"] {
            localDirectory = URL(fileURLWithPath: p, isDirectory: true).appendingPathComponent(productID, isDirectory: true)
        } else {
            localDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("TianliApps/Configuration/" + productID, isDirectory: true)
        }
        super.init()
        if enabled { status = "等待 iCloud 配置同步" }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        #if os(macOS)
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        if let presenter { NSFileCoordinator.removeFilePresenter(presenter) }
        localPresenters.forEach(NSFileCoordinator.removeFilePresenter)
        #endif
    }

    /// Set up native notifications only. Disabled installations never open the cloud file.
    func start() {
        guard !started else { return }
        started = true
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: defaults, queue: nil) { [weak self] _ in
            guard let self, self.enabled else { return }
            self.worker.async {
                guard !self.applying, let snapshot = try? self.snapshot(), let fingerprint = try? Self.json(snapshot), fingerprint != self.lastFingerprint else { return }
                self.reconcile()
            }
        })
        #if os(macOS)
        observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name.NSUbiquityIdentityDidChange, object: nil, queue: nil) { [weak self] _ in self?.resetPresenter(); self?.reconcile() })
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in self?.reconcile() }
        #endif
        #if !os(macOS) || APP_LIFECYCLE_KVS
        if !isolated {
            observers.append(NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: NSUbiquitousKeyValueStore.default, queue: nil) { [weak self] _ in self?.reconcile() })
        }
        #endif
        if enabled { reconcile() }
    }

    func setEnabled(_ value: Bool) {
        defaults.set(value, forKey: enabledKey)
        if value { start(); reconcile() }
        else { resetPresenter(); resetLocalPresenters(); publishStatus("iCloud 配置同步已关闭") }
    }

    func reconcile(completion: ((Error?) -> Void)? = nil) {
        worker.async { [weak self] in
            guard let self else { return }
            do {
                guard self.enabled else { self.publishStatus("iCloud 配置同步已关闭"); self.finish(completion, nil); return }
                guard self.hasSettings else { self.publishStatus("此 App 没有需要同步的配置"); self.finish(completion, nil); return }
                self.installLocalPresenters()
                try self.withLock {
                    let remote = try self.readCloud()
                    let baseline = try self.readState()
                    // The file's presence is the intent. Its values were applied to this device when the import was made.
                    let pendingImport = FileManager.default.fileExists(atPath: self.importedURL.path)
                    // Local settings are read last: one changed while the cloud copy was being read belongs to this pass.
                    let local = try self.snapshot()
                    var merged: [String: Any]
                    if pendingImport {
                        // A deliberate import also wins before this device's first cloud connection. What wins is this
                        // device as it stands now, not a replay of the file: a setting changed since is not put back.
                        merged = local
                    } else if let baseline {
                        // A temporarily absent/not-yet-downloaded cloud file is not deletion of all settings.
                        merged = Self.merge(local: local, cloud: remote ?? baseline.cloud, baseLocal: baseline.local, baseCloud: baseline.cloud)
                    } else if let remote {
                        merged = local
                        // On the first connection, cloud wins existing fields; local-only explicit fields survive.
                        for (key, value) in remote { merged[key] = value }
                    } else { merged = local }
                    merged = self.allowed(merged)
                    if remote == nil && merged.isEmpty {
                        self.publishStatus("iCloud 已开启，等待已有配置；空白配置不会覆盖云端")
                        return
                    }
                    // The baseline is the local values this pass reconciled, never a re-read after the cloud write: a
                    // setting changed meanwhile must still count as a local change, and still start the next pass.
                    var synced = local
                    if !Self.equal(local, merged) {
                        try self.apply(merged, backup: true)
                        // Only what this pass wrote here is re-read, to record it the way this device stores it.
                        let stored = try self.snapshot()
                        for key in Set(local.keys).union(merged.keys) where !Self.equalValue(local[key], merged[key]) { synced[key] = stored[key] }
                    }
                    if remote == nil || !Self.equal(remote!, merged) { try self.writeCloud(merged) }
                    try self.writeState(local: synced, cloud: merged)
                    if pendingImport { try FileManager.default.removeItem(at: self.importedURL) }
                    self.lastFingerprint = try Self.json(synced)
                    #if os(macOS) && !APP_LIFECYCLE_KVS
                    self.publishStatus("配置已与 iCloud Drive 同步；其他设备由系统下载")
                    #elseif os(macOS)
                    self.publishStatus(self.isolated ? "隔离 KVS 配置同步完成" : "配置已提交系统同步；跨设备恢复等待 iCloud")
                    #else
                    self.publishStatus(self.isolated ? "隔离配置同步完成" : "配置已提交系统同步；跨设备恢复等待 iCloud")
                    #endif
                }
                self.finish(completion, nil)
            } catch {
                self.publishStatus("配置同步未完成：" + error.localizedDescription)
                self.finish(completion, error)
            }
        }
    }

    /// Import/export are available independently of the cloud toggle.
    func exportData() throws -> Data { try envelope(snapshot()) }

    func importData(_ data: Data) throws {
        let values = try decode(data)
        try withLock {
            // Keep the intent across a failed/offline sync and restart; never ignore malformed cloud data.
            let previous = try? Data(contentsOf: importedURL)
            try envelope(values).write(to: importedURL, options: .atomic)
            do { try apply(values, backup: true) }
            catch {
                if let previous { try? previous.write(to: importedURL, options: .atomic) }
                else { try? FileManager.default.removeItem(at: importedURL) }
                throw error
            }
        }
        if enabled { reconcile() }
    }

    private enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
    }
    private struct Baseline { var local: [String: Any]; var cloud: [String: Any] }

    private func allowedKey(_ key: String) -> Bool {
        if key.hasPrefix("defaults.") { return defaultsKeys.contains(String(key.dropFirst("defaults.".count))) }
        for (index, file) in files.enumerated() {
            let prefix = "file.\(index)."
            if key.hasPrefix(prefix) { return file.keys.contains { Self.matches(String(key.dropFirst(prefix.count)), pattern: $0) } }
        }
        return false
    }
    private func allowed(_ values: [String: Any]) -> [String: Any] { values.filter { allowedKey($0.key) } }

    private func snapshot() throws -> [String: Any] {
        _ = defaults.synchronize()
        var values: [String: Any] = [:]
        for key in defaultsKeys {
            if let value = defaults.object(forKey: key) { values["defaults." + key] = try Self.pack(value) }
        }
        for (index, file) in files.enumerated() {
            guard FileManager.default.fileExists(atPath: file.url.path) else { continue }
            let object = try Self.readObject(file.url)
            for key in file.keys {
                for path in Self.paths(key, in: object) {
                    if let value = Self.get(path, from: object) { try file.validateValue?(value); values["file.\(index)." + path] = value }
                }
            }
        }
        return values
    }

    private func envelope(_ values: [String: Any]) throws -> Data {
        try Self.json(["version": 1, "product": productID, "values": values])
    }

    private func decode(_ data: Data) throws -> [String: Any] {
        guard data.count <= 4 * 1024 * 1024,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["version"] as? Int == 1, object["product"] as? String == productID,
              let values = object["values"] as? [String: Any] else {
            throw Failure.message("配置文件格式、版本或所属 App 不匹配，原配置已保留")
        }
        guard values.keys.allSatisfy(allowedKey) else { throw Failure.message("配置含此 App 未允许同步的字段") }
        for key in defaultsKeys {
            if let value = values["defaults." + key] { _ = try Self.unpack(value) }
        }
        for (index, file) in files.enumerated() {
            let prefix = "file.\(index)."
            for (key, value) in values where key.hasPrefix(prefix) { try file.validateValue?(value) }
        }
        return values
    }

    private func apply(_ values: [String: Any], backup: Bool) throws {
        let before = try snapshot()
        guard !Self.equal(before, values) else { return }
        // Validate and prepare every file before touching any preferences or file.
        var writes: [(URL, Data, Data?)] = []
        for (index, file) in files.enumerated() {
            let exists = FileManager.default.fileExists(atPath: file.url.path)
            var object = exists ? try Self.readObject(file.url) : [:]
            let prefix = "file.\(index)."
            let existingPaths = file.keys.flatMap { Self.paths($0, in: object) }
            let incomingPaths = values.keys.filter { $0.hasPrefix(prefix) && allowedKey($0) }.map { String($0.dropFirst(prefix.count)) }
            for path in Set(existingPaths).union(incomingPaths) { Self.put(values[prefix + path], at: path, in: &object) }
            let data = try Self.json(object)
            let original = exists ? try Data(contentsOf: file.url) : nil
            if original != data && (exists || !incomingPaths.isEmpty) { writes.append((file.url, data, original)) }
        }
        var prefs: [String: Any] = [:]
        for key in defaultsKeys { if let value = values["defaults." + key] { prefs[key] = try Self.unpack(value) } }
        if backup {
            let destination = localDirectory.appendingPathComponent("Backups/" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try envelope(before).write(to: destination.appendingPathComponent("settings.json"), options: .atomic)
            for (index, item) in writes.enumerated() { if let data = item.2 { try data.write(to: destination.appendingPathComponent("file-\(index).json"), options: .atomic) } }
        }
        applying = true
        defer { applying = false }
        var written: [(URL, Data?)] = []
        do {
            for (url, data, original) in writes {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try data.write(to: url, options: .atomic)
                written.append((url, original))
            }
        } catch {
            for (url, original) in written.reversed() {
                if let original { try? original.write(to: url, options: .atomic) }
                else { try? FileManager.default.removeItem(at: url) }
            }
            throw error
        }
        for key in defaultsKeys { if let value = prefs[key] { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } }
        _ = defaults.synchronize()
        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }

    private func readState() throws -> Baseline? {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return nil }
        let state = try Self.readObject(stateURL)
        guard state["product"] as? String == productID, let local = state["local"] as? [String: Any], let cloud = state["cloud"] as? [String: Any] else {
            throw Failure.message("本机同步记录损坏，已保留云端与本机配置")
        }
        return Baseline(local: allowed(local), cloud: allowed(cloud))
    }
    private func writeState(local: [String: Any], cloud: [String: Any]) throws {
        try Self.json(["product": productID, "local": local, "cloud": cloud]).write(to: stateURL, options: .atomic)
    }

    /// Different keys merge independently; a genuinely concurrent edit of the same key prefers local.
    static func merge(local: [String: Any], cloud: [String: Any], baseLocal: [String: Any], baseCloud: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for key in Set(local.keys).union(cloud.keys).union(baseLocal.keys).union(baseCloud.keys) {
            let localChanged = !equalValue(local[key], baseLocal[key])
            let selected = localChanged ? local[key] : cloud[key]
            if let selected { result[key] = selected }
        }
        return result
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        localLock.lock()
        defer { localLock.unlock() }
        try FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        #if os(macOS)
        let descriptor = open(localDirectory.appendingPathComponent("sync.lock").path, O_CREAT | O_RDWR, mode_t(0o600))
        guard descriptor >= 0 else { throw Failure.message("无法锁定配置同步") }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw Failure.message("无法锁定配置同步") }
        defer { _ = flock(descriptor, LOCK_UN) }
        #endif
        return try body()
    }

    private var cloudURL: URL? {
        let env = ProcessInfo.processInfo.environment
        if isolated {
            guard let p = env["APP_LIFECYCLE_CLOUD_DIR"] else { return nil }
            return URL(fileURLWithPath: p, isDirectory: true).appendingPathComponent(productID + ".json")
        }
        #if os(macOS) && !APP_LIFECYCLE_KVS
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard FileManager.default.ubiquityIdentityToken != nil, FileManager.default.fileExists(atPath: root.path), FileManager.default.isUbiquitousItem(at: root) else { return nil }
        return root.appendingPathComponent("TianliApps/Settings/" + productID + ".json")
        #else
        return nil
        #endif
    }

    private func readCloud() throws -> [String: Any]? {
        #if os(macOS) && !APP_LIFECYCLE_KVS
        guard let url = cloudURL else { throw Failure.message("请在系统设置登录 Apple 账户并开启 iCloud Drive") }
        installPresenter(url)
        if !isolated { try? FileManager.default.startDownloadingUbiquitousItem(at: url) }
        if !FileManager.default.fileExists(atPath: url.path) { return nil }
        if !isolated, let download = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus,
           download == .notDownloaded { throw Failure.message("正在从 iCloud 下载配置，请稍后同步") }
        return try coordinated(url, writing: false) { try decode(Data(contentsOf: $0)) }
        #else
        if isolated {
            guard let url = cloudURL else { throw Failure.message("隔离运行没有配置测试云目录") }
            return FileManager.default.fileExists(atPath: url.path) ? try decode(Data(contentsOf: url)) : nil
        }
        guard FileManager.default.ubiquityIdentityToken != nil else { throw Failure.message("请在系统设置登录 Apple 账户并开启 iCloud") }
        guard NSUbiquitousKeyValueStore.default.synchronize() else { throw Failure.message("iCloud 键值存储当前不可用，请检查账户与 App 的 iCloud 权限") }
        guard let data = NSUbiquitousKeyValueStore.default.data(forKey: "settings." + productID) else { return nil }
        return try decode(data)
        #endif
    }

    private func writeCloud(_ values: [String: Any]) throws {
        let data = try envelope(values)
        #if os(macOS) && !APP_LIFECYCLE_KVS
        guard let url = cloudURL else { throw Failure.message("iCloud Drive 当前不可用") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try coordinated(url, writing: true) { try data.write(to: $0, options: .atomic) }
        #else
        if isolated {
            guard let url = cloudURL else { throw Failure.message("隔离运行没有配置测试云目录") }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } else {
            guard data.count < 900_000 else { throw Failure.message("配置超出 iCloud 键值存储大小限制") }
            NSUbiquitousKeyValueStore.default.set(data, forKey: "settings." + productID)
            guard NSUbiquitousKeyValueStore.default.synchronize() else { throw Failure.message("iCloud 配置暂未完成上传，请稍后重试") }
        }
        #endif
    }

    private func resetPresenter() {
        #if os(macOS)
        if let presenter { NSFileCoordinator.removeFilePresenter(presenter) }
        presenter = nil
        #endif
    }
    private func resetLocalPresenters() {
        #if os(macOS)
        localPresenters.forEach(NSFileCoordinator.removeFilePresenter)
        localPresenters = []
        #endif
    }
    private func installLocalPresenters() {
        #if os(macOS)
        guard localPresenters.isEmpty else { return }
        for file in files {
            let p = ConfigurationPresenter(directory: file.url.deletingLastPathComponent(), filename: file.url.lastPathComponent) { [weak self] in self?.reconcile() }
            localPresenters.append(p)
            NSFileCoordinator.addFilePresenter(p)
        }
        #endif
    }
    #if os(macOS)
    private func installPresenter(_ url: URL) {
        guard presenter?.presentedItemURL != url.deletingLastPathComponent() else { return }
        resetPresenter()
        let p = ConfigurationPresenter(directory: url.deletingLastPathComponent(), filename: url.lastPathComponent) { [weak self] in self?.reconcile() }
        presenter = p
        NSFileCoordinator.addFilePresenter(p)
    }
    private func coordinated<T>(_ url: URL, writing: Bool, _ body: (URL) throws -> T) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        let coordinator = NSFileCoordinator(filePresenter: presenter)
        if writing { coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) { target in result = Result { try body(target) } } }
        else { coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { target in result = Result { try body(target) } } }
        if let coordinationError { throw coordinationError }
        guard let result else { throw Failure.message("iCloud 文件协调没有返回结果") }
        return try result.get()
    }
    #endif

    private func publishStatus(_ value: String) {
        DispatchQueue.main.async { [weak self] in
            self?.status = value
            #if os(macOS)
            self?.recordStatus(value)   // where the sentence is set, so the record never differs from it
            #endif
            NotificationCenter.default.post(name: Notification.Name("AppConfigurationStatusChanged"), object: self)
        }
    }
    private func finish(_ completion: ((Error?) -> Void)?, _ error: Error?) { DispatchQueue.main.async { completion?(error) } }

    private static func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]) }
    private static func equal(_ a: [String: Any], _ b: [String: Any]) -> Bool { (try? json(a)) == (try? json(b)) }
    private static func equalValue(_ a: Any?, _ b: Any?) -> Bool {
        guard let a else { return b == nil }
        guard let b else { return false }
        return (try? json(a)) == (try? json(b))
    }
    private static func readObject(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard data.count <= 8 * 1024 * 1024, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.message("配置文件不是 JSON 对象，原文件已保留") }
        return object
    }
    /// UserDefaults Data (shortcut/preferences JSON) remains a Data value after migration.
    private static func pack(_ value: Any) throws -> Any {
        if let data = value as? Data { return ["$data": data.base64EncodedString()] }
        if let date = value as? Date { return ["$date": date.timeIntervalSince1970] }
        if let array = value as? [Any] { return try array.map(pack) }
        if let object = value as? [String: Any] { return try object.mapValues(pack) }
        _ = try json(value)
        return value
    }
    private static func unpack(_ value: Any) throws -> Any {
        if let object = value as? [String: Any] {
            if Set(object.keys) == ["$data"] {
                guard let text = object["$data"] as? String, let data = Data(base64Encoded: text) else { throw Failure.message("配置中的 Data 字段无效") }
                return data
            }
            if Set(object.keys) == ["$date"] {
                guard let seconds = object["$date"] as? Double, seconds.isFinite else { throw Failure.message("配置中的日期无效") }
                return Date(timeIntervalSince1970: seconds)
            }
            return try object.mapValues(unpack)
        }
        if let array = value as? [Any] { return try array.map(unpack) }
        guard !(value is NSNull) else { throw Failure.message("UserDefaults 配置不能是 null") }
        return value
    }
    private static func parts(_ path: String) -> [String] {
        if path.hasPrefix("/") { return path.dropFirst().split(separator: "/", omittingEmptySubsequences: false).map { $0.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~") } }
        return path.split(separator: ".").map(String.init)
    }
    private static func matches(_ path: String, pattern: String) -> Bool {
        guard path.hasPrefix("/") == pattern.hasPrefix("/") else { return false }
        let actual = parts(path), expected = parts(pattern)
        guard actual.count == expected.count else { return false }
        return zip(actual, expected).allSatisfy { value, rule in
            pattern.hasPrefix("/") && rule.hasSuffix("*") ? value.hasPrefix(String(rule.dropLast())) : value == rule
        }
    }
    private static func paths(_ pattern: String, in object: [String: Any]) -> [String] {
        guard pattern.hasPrefix("/"), parts(pattern).contains(where: { $0.hasSuffix("*") }) else { return [pattern] }
        func expand(_ remaining: ArraySlice<String>, _ object: [String: Any], _ prefix: [String]) -> [[String]] {
            guard let rule = remaining.first else { return [prefix] }
            let keys = rule.hasSuffix("*") ? object.keys.filter { $0.hasPrefix(String(rule.dropLast())) }.sorted() : [rule]
            return keys.flatMap { key -> [[String]] in
                if remaining.count == 1 { return object[key] == nil ? [] : [prefix + [key]] }
                guard let child = object[key] as? [String: Any] else { return [] }
                return expand(remaining.dropFirst(), child, prefix + [key])
            }
        }
        return expand(ArraySlice(parts(pattern)), object, []).map { "/" + $0.map { $0.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1") }.joined(separator: "/") }
    }
    private static func get(_ path: String, from object: [String: Any]) -> Any? {
        var current: Any = object
        for part in parts(path) { guard let next = (current as? [String: Any])?[part] else { return nil }; current = next }
        return current
    }
    private static func put(_ value: Any?, at path: String, in object: inout [String: Any]) {
        put(value, parts: ArraySlice(parts(path)), in: &object)
    }
    private static func put(_ value: Any?, parts: ArraySlice<String>, in object: inout [String: Any]) {
        guard let first = parts.first else { return }
        if parts.count == 1 { if let value { object[first] = value } else { object.removeValue(forKey: first) }; return }
        var child = object[first] as? [String: Any] ?? [:]
        put(value, parts: parts.dropFirst(), in: &child)
        if child.isEmpty { object.removeValue(forKey: first) } else { object[first] = child }
    }
}

#if os(macOS)
private final class ConfigurationPresenter: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 1; q.qualityOfService = .utility; return q }()
    private let filename: String
    private let changed: () -> Void
    init(directory: URL, filename: String, changed: @escaping () -> Void) { presentedItemURL = directory; self.filename = filename; self.changed = changed }
    func presentedItemDidChange() { changed() }
    func presentedSubitemDidAppear(at url: URL) { if url.lastPathComponent == filename { changed() } }
    func presentedSubitemDidChange(at url: URL) { if url.lastPathComponent == filename { changed() } }
}
#else
private final class ConfigurationPresenter {}
#endif

// Shared product version checking. Distributed by vendor-lifecycle.py.
import Foundation

enum AppUpdateSource {
    case github(repository: String)
    case manifest(URL)
    case privateCloud(channel: String)
    case appStore(id: String)
}

struct AppRelease {
    let version: String
    let build: String
    let downloadURL: URL?
    let releaseURL: URL?
    var sha256: String? = nil
    var size: Int64? = nil
    var channel: String? = nil
    var bundleID: String? = nil
    var installation: String? = nil
    var notes: String? = nil
    var publishedAt: String? = nil

    func isNewer(than version: String, build: String) -> Bool {
        let versions = AppVersion.compare(self.version, version)
        if versions != .orderedSame { return versions == .orderedDescending }
        return AppVersion.compare(self.build, build) == .orderedDescending
    }
}

enum AppVersion {
    /// Numeric components preserve independent build numbers such as 022 and 0.3.5.
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        func components(_ string: String) -> [Int]? {
            let source = string.hasPrefix("v") ? String(string.dropFirst()) : string
            let parts = source.split(separator: ".", omittingEmptySubsequences: false)
            guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
            return parts.compactMap { Int($0) }
        }
        guard let a = components(lhs), let b = components(rhs) else {
            return lhs.compare(rhs, options: .numeric)
        }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}

struct AppUpdateError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

struct AppUpdateOptions: Codable {
    var automaticCheck = false
    var intervalHours = 24
    var automaticDownload = false
    var automaticInstall = false
    var channel: String? = nil
    var skippedBuild: String? = nil
    var remindAfter: Double? = nil
    init() {}
    private enum CodingKeys:String,CodingKey { case automaticCheck,intervalHours,automaticDownload,automaticInstall,channel,skippedBuild,remindAfter }
    init(from decoder:Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        automaticCheck = try c.decodeIfPresent(Bool.self,forKey:.automaticCheck) ?? false
        intervalHours = try c.decodeIfPresent(Int.self,forKey:.intervalHours) ?? 24
        automaticDownload = try c.decodeIfPresent(Bool.self,forKey:.automaticDownload) ?? false
        automaticInstall = try c.decodeIfPresent(Bool.self,forKey:.automaticInstall) ?? false
        channel = try c.decodeIfPresent(String.self,forKey:.channel)
        skippedBuild = try c.decodeIfPresent(String.self,forKey:.skippedBuild)
        remindAfter = try c.decodeIfPresent(Double.self,forKey:.remindAfter)
    }
}

/// Preferences and check history shared by the native window and short-lived CLI.
/// Only appUpdateOptions is portable; local timestamps and staged packages stay per Mac.
enum AppUpdatePreferences {
    static func defaults(_ bundleID:String) -> UserDefaults {
        if bundleID == Bundle.main.bundleIdentifier { return .standard }
        return UserDefaults(suiteName:bundleID.isEmpty ? "test.tianli.shared-update" : bundleID) ?? .standard
    }
    static func options(_ bundleID:String) -> AppUpdateOptions {
        guard let value = defaults(bundleID).dictionary(forKey:"appUpdateOptions"),
              let data = try? JSONSerialization.data(withJSONObject:value),let result = try? JSONDecoder().decode(AppUpdateOptions.self,from:data) else { return AppUpdateOptions() }
        guard (try? validate(result)) != nil else { return AppUpdateOptions() };return result
    }
    static func validate(_ options:AppUpdateOptions) throws {
        guard (1...720).contains(options.intervalHours),options.remindAfter?.isFinite != false else { throw AppUpdateError("检查间隔应为 1–720 小时") }
        if let channel = options.channel { guard validChannel(channel) else { throw AppUpdateError("无效的更新渠道") } }
    }
    static func save(_ options:AppUpdateOptions,_ bundleID:String) throws {
        try validate(options)
        let data = try JSONEncoder().encode(options)
        let value = try JSONSerialization.jsonObject(with:data)
        let store = defaults(bundleID)
        if self.options(bundleID).channel != options.channel { store.removeObject(forKey:"appUpdateState") }
        store.set(value,forKey:"appUpdateOptions");store.synchronize()
        #if os(macOS)
        DistributedNotificationCenter.default().postNotificationName(Notification.Name("cyou.tianli.update-options." + bundleID),object:nil,userInfo:nil,deliverImmediately:true)
        #endif
    }
    static func validChannel(_ s:String) -> Bool { !s.isEmpty && s.count <= 79 && !s.contains("..") && s.allSatisfy{$0.isASCII && ($0.isLetter || $0.isNumber || "_.-".contains($0))} }
    static func source(_ fallback:AppUpdateSource,_ bundleID:String) -> AppUpdateSource {
        if case .privateCloud = fallback,let channel = options(bundleID).channel { return .privateCloud(channel:channel) };return fallback
    }
    static func describe(_ source:AppUpdateSource) -> String {
        switch source {
        case .privateCloud(let channel):return "iCloud 私有渠道 · " + channel
        case .github(let repository):return "GitHub · " + repository
        case .manifest(let url):return url.host ?? "HTTPS 发行源"
        case .appStore(let id):return "App Store · " + id
        }
    }
    static func record(_ bundleID:String,_ result:Result<AppRelease,Error>,source:AppUpdateSource) {
        guard describe(self.source(source,bundleID)) == describe(source) else { return }
        let store = defaults(bundleID);var state = store.dictionary(forKey:"appUpdateState") ?? [:]
        state["last_attempt_at"] = Date().timeIntervalSince1970
        switch result {
        case .success(let release):state["last_success_at"] = Date().timeIntervalSince1970;state["last_error"] = "";state["latest_version"] = release.version;state["latest_build"] = release.build
        case .failure(let error):state["last_error"] = error.localizedDescription
        }
        store.set(state,forKey:"appUpdateState");store.synchronize()
    }
    static func status(_ bundleID:String,source:AppUpdateSource) -> [String:Any] {
        let options = options(bundleID)
        let data = (try? JSONEncoder().encode(options)) ?? Data("{}".utf8)
        return ["options":(try? JSONSerialization.jsonObject(with:data)) ?? [:],"history":defaults(bundleID).dictionary(forKey:"appUpdateState") ?? [:],"source":describe(self.source(source,bundleID))]
    }
    static func due(_ bundleID:String,at:Date = Date()) -> Bool {
        let settings = options(bundleID)
        guard settings.automaticCheck,(settings.remindAfter ?? 0) <= at.timeIntervalSince1970 else { return false }
        let last = defaults(bundleID).dictionary(forKey:"appUpdateState")?["last_attempt_at"] as? Double ?? 0
        return at.timeIntervalSince1970 - last >= Double(settings.intervalHours) * 3600
    }
}

enum AppUpdateChecker {
    static let maximumFeedSize = 262_144

    static func privateDirectory(bundleID: String, channel: String) throws -> URL {
        guard validComponent(bundleID), validComponent(channel) else { throw AppUpdateError("无效的更新渠道。") }
        if let isolated = ProcessInfo.processInfo.environment["APP_LIFECYCLE_SUPPORT_DIR"] {
            guard let cloud = ProcessInfo.processInfo.environment["APP_LIFECYCLE_CLOUD_DIR"], !isolated.isEmpty else {
                throw AppUpdateError("隔离运行没有配置测试更新目录。")
            }
            return URL(fileURLWithPath: cloud).appendingPathComponent("TianliApps/Updates/\(bundleID)/\(channel)")
        }
        #if os(macOS)
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        guard FileManager.default.ubiquityIdentityToken != nil,
              FileManager.default.fileExists(atPath: root.path), FileManager.default.isUbiquitousItem(at: root) else {
            throw AppUpdateError("请在系统设置登录 Apple ID 并开启 iCloud Drive，才能获取此私有版更新。")
        }
        return root.appendingPathComponent("TianliApps/Updates/\(bundleID)/\(channel)")
        #else
        throw AppUpdateError("请使用此 App 的系统发行渠道升级。")
        #endif
    }

    static func check(source: AppUpdateSource, bundleID: String, version: String, build: String,
                      completion: @escaping (Result<AppRelease, Error>) -> Void) {
        let source = AppUpdatePreferences.source(source,bundleID)
        let finish: (Result<AppRelease,Error>) -> Void = { result in AppUpdatePreferences.record(bundleID,result,source:source);completion(result) }
        switch source {
        case .privateCloud(let channel):
            DispatchQueue.global(qos: .utility).async {
                do {
                    let directory = try privateDirectory(bundleID: bundleID, channel: channel)
                    let file = directory.appendingPathComponent("release.json")
                    guard FileManager.default.fileExists(atPath: file.path) else {
                        throw AppUpdateError("iCloud 中还没有此渠道的发行包，当前版本 \(version) (\(build))。")
                    }
                    if FileManager.default.isUbiquitousItem(at: file) { try FileManager.default.startDownloadingUbiquitousItem(at: file) }
                    var error: NSError?, result: Result<AppRelease, Error>?
                    NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &error) { url in
                        result = Result { try manifest(Data(contentsOf: url), at: file, bundleID: bundleID, channel: channel) }
                    }
                    if let error { throw error }
                    finish(result ?? .failure(AppUpdateError("无法读取 iCloud 发行记录。")))
                } catch { finish(.failure(error)) }
            }
        case .manifest(let url):
            fetch(url) { result in
                finish(result.flatMap { data in Result { try manifest(data, at: url, bundleID: bundleID) } })
            }
        case .github(let repository):
            #if APP_LIFECYCLE_LOCAL_ONLY
            finish(.failure(AppUpdateError("此 App 只读取 iCloud 已下载到本机的私有发行包。")))
            #else
            guard repository.split(separator: "/").count == 2,
                  repository.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_/ .".contains($0)) }),
                  !repository.contains(" "), !repository.contains(".."),
                  let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
                finish(.failure(AppUpdateError("无效的发行仓库。"))); return
            }
            fetch(url) { result in
                finish(result.flatMap { data in Result { try github(data, bundleID: bundleID) } })
            }
            #endif
        case .appStore(let id):
            #if APP_LIFECYCLE_LOCAL_ONLY
            finish(.failure(AppUpdateError("此 App 只读取 iCloud 已下载到本机的私有发行包。")))
            #else
            let region = (Locale.current.region?.identifier ?? "US").lowercased()
            let country = region.count == 2 && region.allSatisfy(\.isLetter) ? region : "us"
            guard id.allSatisfy(\.isNumber), !id.isEmpty,
                  let url = URL(string: "https://itunes.apple.com/lookup?id=\(id)&country=\(country)") else {
                finish(.failure(AppUpdateError("未配置 App Store 发行渠道。"))); return
            }
            fetch(url) { result in
                finish(result.flatMap { data in Result { try appStore(data, id: id, bundleID: bundleID) } })
            }
            #endif
        }
    }

    static func fetch(_ url: URL, completion: @escaping (Result<Data, Error>) -> Void) {
        #if APP_LIFECYCLE_LOCAL_ONLY
        completion(.failure(AppUpdateError("此 App 只读取 iCloud 已下载到本机的私有发行包。")))
        #else
        guard url.scheme == "https", url.user == nil, url.password == nil else {
            completion(.failure(AppUpdateError("更新来源必须使用 HTTPS。"))); return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("TianliApp-Update/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        session.dataTask(with: request) { data, response, error in
            defer { session.finishTasksAndInvalidate() }
            if let error { completion(.failure(error)); return }
            guard let response = response as? HTTPURLResponse, response.url?.scheme == "https", response.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                completion(.failure(AppUpdateError("未能读取发行记录（HTTP \(code)）。请稍后重试。"))); return
            }
            guard let data, !data.isEmpty, data.count <= maximumFeedSize else {
                completion(.failure(AppUpdateError("发行记录为空或过大。"))); return
            }
            completion(.success(data))
        }.resume()
        #endif
    }

    static func manifest(_ data: Data, at feed: URL, bundleID: String, channel: String? = nil) throws -> AppRelease {
        guard data.count <= maximumFeedSize,
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = value["version"] as? String, validVersion(version) else { throw AppUpdateError("发行记录缺少有效版本。") }
        let declaredID = value["bundle_id"] as? String
        if let declaredID, declaredID != bundleID { throw AppUpdateError("发行包属于另一个 App。") }
        if let channel, value["channel"] as? String != channel { throw AppUpdateError("发行渠道不匹配，不能替换当前版本。") }
        let build = string(value["build"]) ?? "0"
        guard validVersion(build) else { throw AppUpdateError("发行记录构建号无效。") }
        let reference = value["download_url"] as? String ?? value["filename"] as? String
        var download: URL?
        if let reference {
            if feed.isFileURL {
                guard validComponent(reference), declaredID == bundleID else { throw AppUpdateError("私有发行包路径或身份无效。") }
                download = feed.deletingLastPathComponent().appendingPathComponent(reference)
            } else {
                guard let resolved = URL(string: reference, relativeTo: feed)?.absoluteURL, resolved.scheme == "https",
                      resolved.user == nil, resolved.password == nil else { throw AppUpdateError("下载地址无效。") }
                download = resolved
            }
        }
        let releaseURL = (value["release_url"] as? String).flatMap { URL(string: $0) }
        if let releaseURL, releaseURL.scheme != "https" { throw AppUpdateError("发行说明地址无效。") }
        let hash = value["sha256"] as? String
        if let hash, !(hash.count == 64 && hash.allSatisfy(\.isHexDigit)) { throw AppUpdateError("发行包校验值无效。") }
        if feed.isFileURL && (download == nil || hash == nil) { throw AppUpdateError("私有发行包缺少下载或校验信息。") }
        return AppRelease(version: version, build: build, downloadURL: download, releaseURL: releaseURL,
                          sha256: hash, size: (value["size_bytes"] as? NSNumber)?.int64Value,
                          channel: value["channel"] as? String, bundleID: declaredID,
                          installation: value["installation"] as? String,
                          notes: (value["notes"] as? String).map{String($0.prefix(6000))},publishedAt:value["published_at"] as? String)
    }

    static func github(_ data: Data, bundleID: String) throws -> AppRelease {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              value["draft"] as? Bool != true, value["prerelease"] as? Bool != true,
              let tag = value["tag_name"] as? String else { throw AppUpdateError("没有可用的正式发行。") }
        let parts = (tag.hasPrefix("v") ? String(tag.dropFirst()) : tag).split(separator: "-", maxSplits: 1)
        guard let version = parts.first.map(String.init), validVersion(version) else { throw AppUpdateError("发行版本格式无效。") }
        let build = parts.count > 1 ? String(parts[1]) : "0"
        guard validVersion(build) else { throw AppUpdateError("发行构建号格式无效。") }
        let assets = (value["assets"] as? [[String: Any]] ?? []).filter {
            let name = ($0["name"] as? String ?? "").lowercased()
            return (name.hasSuffix(".zip") || name.hasSuffix(".dmg")) && !name.contains("x86") && !name.contains("intel")
        }.sorted {
            func score(_ asset: [String: Any]) -> Int {
                let name = (asset["name"] as? String ?? "").lowercased()
                return (name.hasSuffix(".zip") ? 2 : 0) + (name.contains("arm64") ? 4 : 0)
            }
            return score($0) > score($1)
        }
        let asset = assets.first
        let download = (asset?["browser_download_url"] as? String).flatMap { URL(string: $0) }
        guard download?.scheme == "https", download?.host == "github.com" else { throw AppUpdateError("正式发行缺少 Mac 安装包。") }
        let hash = (asset?["digest"] as? String).flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)) : nil }
        return AppRelease(version: version, build: build, downloadURL: download,
                          releaseURL: (value["html_url"] as? String).flatMap { URL(string: $0) },
                          sha256: hash, size: (asset?["size"] as? NSNumber)?.int64Value, bundleID: bundleID)
    }

    static func appStore(_ data: Data, id: String, bundleID: String) throws -> AppRelease {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let apps = value["results"] as? [[String: Any]],
              let app = apps.first(where: { string($0["trackId"]) == id && $0["bundleId"] as? String == bundleID }),
              let version = app["version"] as? String, validVersion(version),
              let string = app["trackViewUrl"] as? String, let url = URL(string: string), url.scheme == "https", url.host == "apps.apple.com" else {
            throw AppUpdateError("此地区暂未找到此 App 的商店发行，不能判断是否已是最新版。")
        }
        return AppRelease(version: version, build: "0", downloadURL: url, releaseURL: url, bundleID: bundleID)
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }
    private static func validVersion(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return !value.isEmpty && value.count < 80 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) && Int($0) != nil }
    }
    private static func validComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && value.count < 240 &&
        value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
    }
}

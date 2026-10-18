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

/// Language of the shared lifecycle windows (Mac settings/update panel, iOS/Mac SwiftUI panel, menu items).
/// These files are vendored into each product's own target, so they cannot rely on the product's String Catalog:
/// every UI string carries English and Simplified Chinese inline and goes through `pick`.
/// The language follows the product's own localizations when it declares any (so the panel matches the rest of the
/// app), otherwise the user's preferred languages; anything not Chinese is English.
/// `APP_LIFECYCLE_LANGUAGE=en|zh-Hans` pins it (acceptance runs).
/// Messages the shared core stores or the command line prints (configuration status, update errors, installer
/// stages) keep their original Chinese text byte for byte; only the window translates them with `display`.
enum LifecycleText {
    enum Language: String { case english = "en", chinese = "zh-Hans" }
    static var language: Language {
        if let pinned = ProcessInfo.processInfo.environment["APP_LIFECYCLE_LANGUAGE"], !pinned.isEmpty { return resolve([pinned]) }
        let declared = Bundle.main.localizations.filter { $0 != "Base" }
        if !declared.isEmpty { return resolve(Bundle.main.preferredLocalizations.filter { $0 != "Base" }) }
        return resolve(Locale.preferredLanguages)
    }

    static func resolve(_ identifiers: [String]) -> Language {
        guard let first = identifiers.first else { return .english }
        return first.lowercased().hasPrefix("zh") ? .chinese : .english
    }

    static func pick(_ english: String, _ chinese: String) -> String { language == .chinese ? chinese : english }

    /// The window's rendering of a message produced by the shared core; unknown text is shown as it is.
    static func display(_ message: String) -> String {
        guard language == .english, !message.isEmpty else { return message }
        if let exact = messages[message] { return exact }
        for (zhPrefix, zhSuffix, enPrefix, enSuffix) in patterns
        where message.hasPrefix(zhPrefix) && message.hasSuffix(zhSuffix) && message.count >= zhPrefix.count + zhSuffix.count {
            let middle = String(message.dropFirst(zhPrefix.count).dropLast(zhSuffix.count))
            return enPrefix + display(middle) + enSuffix
        }
        return message
    }

    private static let patterns: [(String, String, String, String)] = [
        ("配置同步未完成：", "", "Settings sync did not finish: ", ""),
        ("iCloud 私有渠道 · ", "", "iCloud private channel · ", ""),
        ("iCloud 中还没有此渠道的发行包，当前版本 ", "。", "iCloud has no release for this channel yet; current version ", "."),
        ("未能读取发行记录（HTTP ", "）。请稍后重试。", "Could not read the release record (HTTP ", "). Please try again later."),
        ("新版需要 macOS ", " 或更新系统。", "The new version requires macOS ", " or later."),
        ("此产品需要其专用安装事务：", "", "This product needs its own installer: ", ""),
        ("安装包验证失败：", "", "Package verification failed: ", ""),
    ]

    private static let messages: [String: String] = [
        // AppShortcuts errors (thrown in Chinese so CLI output stays byte-identical)
        "应用快捷键须为 ⌘ 加单个字母或数字，可另加 ⇧、⌥、⌃。": "An app shortcut must be ⌘ plus one letter or digit, optionally with ⇧, ⌥ or ⌃.",
        "此组合保留给系统或编辑菜单，请选择其他快捷键。": "This combination is reserved for the system or the Edit menu; choose another shortcut.",
        "此应用菜单已使用这个组合，原快捷键保持不变。": "This app's menu already uses this combination; the original shortcut is unchanged.",
        // AppConfiguration status sentences
        "iCloud 配置同步已关闭": "iCloud settings sync is off",
        "等待 iCloud 配置同步": "Waiting for iCloud settings sync",
        "此 App 没有需要同步的配置": "This app has no settings to sync",
        "iCloud 已开启，等待已有配置；空白配置不会覆盖云端": "iCloud is on and waiting for existing settings; blank settings never overwrite iCloud",
        "配置已与 iCloud Drive 同步；其他设备由系统下载": "Settings synced with iCloud Drive; other devices download them through the system",
        "隔离 KVS 配置同步完成": "Isolated KVS settings sync finished",
        "配置已提交系统同步；跨设备恢复等待 iCloud": "Settings handed to system sync; restoring on other devices waits for iCloud",
        "隔离配置同步完成": "Isolated settings sync finished",
        // AppConfiguration failures
        "配置文件格式、版本或所属 App 不匹配，原配置已保留": "The settings file's format, version or app does not match; the current settings are kept",
        "配置含此 App 未允许同步的字段": "The settings contain fields this app does not allow to sync",
        "本机同步记录损坏，已保留云端与本机配置": "The local sync record is damaged; iCloud and local settings are kept",
        "无法锁定配置同步": "Could not lock settings sync",
        "请在系统设置登录 Apple 账户并开启 iCloud Drive": "Sign in to your Apple Account and turn on iCloud Drive in System Settings",
        "正在从 iCloud 下载配置，请稍后同步": "Downloading settings from iCloud; sync again shortly",
        "隔离运行没有配置测试云目录": "This isolated run has no test cloud directory",
        "请在系统设置登录 Apple 账户并开启 iCloud": "Sign in to your Apple Account and turn on iCloud in System Settings",
        "iCloud 键值存储当前不可用，请检查账户与 App 的 iCloud 权限": "iCloud key-value storage is unavailable; check the account and this app's iCloud permission",
        "iCloud Drive 当前不可用": "iCloud Drive is unavailable",
        "配置超出 iCloud 键值存储大小限制": "The settings exceed the iCloud key-value storage size limit",
        "iCloud 配置暂未完成上传，请稍后重试": "Settings have not finished uploading to iCloud; try again later",
        "iCloud 文件协调没有返回结果": "iCloud file coordination returned no result",
        "配置文件不是 JSON 对象，原文件已保留": "The settings file is not a JSON object; the original file is kept",
        "配置中的 Data 字段无效": "A Data field in the settings is invalid",
        "配置中的日期无效": "A date in the settings is invalid",
        "UserDefaults 配置不能是 null": "A UserDefaults setting cannot be null",
        // AppLifecycle update checks
        "检查间隔应为 1–720 小时": "The check interval must be 1–720 hours",
        "无效的更新渠道": "Invalid update channel",
        "无效的更新渠道。": "Invalid update channel.",
        "HTTPS 发行源": "HTTPS release source",
        "隔离运行没有配置测试更新目录。": "This isolated run has no test update directory.",
        "请在系统设置登录 Apple ID 并开启 iCloud Drive，才能获取此私有版更新。": "Sign in to your Apple ID and turn on iCloud Drive in System Settings to get this private update.",
        "请使用此 App 的系统发行渠道升级。": "Please update through this app's system release channel.",
        "无法读取 iCloud 发行记录。": "Could not read the iCloud release record.",
        "此 App 只读取 iCloud 已下载到本机的私有发行包。": "This app only reads private releases iCloud has already downloaded to this Mac.",
        "无效的发行仓库。": "Invalid release repository.",
        "未配置 App Store 发行渠道。": "No App Store release channel is configured.",
        "更新来源必须使用 HTTPS。": "The update source must use HTTPS.",
        "发行记录为空或过大。": "The release record is empty or too large.",
        "发行记录缺少有效版本。": "The release record has no valid version.",
        "发行包属于另一个 App。": "The release belongs to another app.",
        "发行渠道不匹配，不能替换当前版本。": "The release channel does not match; the current version cannot be replaced.",
        "发行记录构建号无效。": "The release record's build number is invalid.",
        "私有发行包路径或身份无效。": "The private release path or identity is invalid.",
        "下载地址无效。": "The download address is invalid.",
        "发行说明地址无效。": "The release notes address is invalid.",
        "发行包校验值无效。": "The release checksum is invalid.",
        "私有发行包缺少下载或校验信息。": "The private release is missing download or checksum information.",
        "没有可用的正式发行。": "No official release is available.",
        "发行版本格式无效。": "The release version format is invalid.",
        "发行构建号格式无效。": "The release build number format is invalid.",
        "正式发行缺少 Mac 安装包。": "The official release has no Mac package.",
        "此地区暂未找到此 App 的商店发行，不能判断是否已是最新版。": "No store release of this app was found in this region, so it cannot tell whether this is the latest version.",
        // Mac installer (shared with `update install`)
        "升级已取消，当前 App 保留": "Update canceled; the current app is kept",
        "发行包缺少完整性校验。": "The release has no integrity checksum.",
        "发行包大小不匹配。": "The release size does not match.",
        "发行包 SHA256 校验失败。": "The release failed its SHA256 check.",
        "安装包中没有唯一的 App。": "The package does not contain exactly one app.",
        "不支持此安装包格式。": "This package format is not supported.",
        "安装包 App 身份或版本不匹配。": "The packaged app's identity or version does not match.",
        "当前 App 无开发者身份，请使用正式下载渠道手动安装。": "The current app has no developer identity; install manually from the official download.",
        "新版的签名开发者与当前 App 不同。": "The new version is signed by a different developer than the current app.",
        "发行包 Team 不匹配。": "The release's Team does not match.",
        "同步安装缺少完整身份、build 或最低系统版本。": "The synced install is missing its identity, build or minimum system version.",
        "同步安装拒绝相同版本和降级。": "The synced install refuses the same version and downgrades.",
        "安装包架构不匹配。": "The package architecture does not match.",
        "测试构建仅允许隔离目录。": "Test builds are allowed only in isolated directories.",
        "需要正式 Developer ID 签名。": "An official Developer ID signature is required.",
        "需要正式公证。": "Official notarization is required.",
        "此 App 只安装 iCloud 已下载到本机的私有发行包。": "This app only installs private releases iCloud has already downloaded to this Mac.",
        "下载来源必须使用 HTTPS。": "The download source must use HTTPS.",
        "下载未完成。": "The download did not finish.",
        "完整性回读参数不完整。": "The integrity read-back parameters are incomplete.",
        "当前安装目录不可写，请把 App 安装在用户可写的位置。": "The install location is not writable; install the app somewhere your account can write.",
        "此 Notihub 发行包缺少安全采集器升级接口。": "This Notihub release lacks the secure collector upgrade interface.",
        "替换前 App 身份或路径不匹配。": "The app's identity or path changed before replacement.",
        // Mac sandbox update access (AppLifecycleMobile)
        "隔离运行只使用显式测试更新目录。": "Isolated runs use only the explicit test update directory.",
        "请选择系统 iCloud Drive 根目录。": "Choose the system iCloud Drive root folder.",
        "请先选择 iCloud Drive 更新目录，授予此 Mac 读取发行包的权限。": "First choose the iCloud Drive update folder to let this Mac read releases.",
        "更新目录权限已失效，请重新选择 iCloud Drive 更新目录。": "Access to the update folder expired; choose the iCloud Drive update folder again.",
        "所选 iCloud Drive 目录暂不可用，请检查系统 iCloud Drive 状态。": "The chosen iCloud Drive folder is unavailable; check iCloud Drive in System Settings.",
        "发行目录超出所选 iCloud Drive 目录。": "The release folder is outside the chosen iCloud Drive folder.",
        "此 Mac 沙盒版需要手动安装的正式 ZIP 发行包。": "This sandboxed Mac version needs an official ZIP release to install manually.",
        "发行包身份或路径不匹配，请重新检查更新。": "The release identity or path does not match; check for updates again.",
        "发行包尚未完整下载，请稍后重试。": "The release has not finished downloading; try again later.",
        "无法读取发行包。": "Could not read the release.",
        "发行包校验失败，请重新下载。": "The release failed its checksum; download it again.",
        "系统未能打开 ZIP 发行包。": "The system could not open the ZIP release.",
        // Installer progress stages
        "正在下载": "Downloading",
        "正在验证校验和": "Verifying checksum",
        "正在解包与验证签名": "Unpacking and verifying signature",
        "发行包验证完成": "Release verified",
        "正在读取私有发行包": "Reading private release",
    ]
}

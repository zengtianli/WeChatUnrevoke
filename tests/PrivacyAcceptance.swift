import Foundation

/// Receives the real production URLSession.shared request, without sending it.
/// sandbox-exec independently denies network access for this entire process.
final class PrivacyHTTPProtocol: URLProtocol, @unchecked Sendable {
    enum Response { case config, offline, invalid }
    private static let lock = NSLock()
    private static var response: Response = .config
    private static var captured: [URLRequest] = []

    static func select(_ next: Response) {
        lock.lock(); defer { lock.unlock() }
        response = next
    }
    static func requests() -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return captured
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.captured.append(request)
        let response = Self.response
        Self.lock.unlock()
        switch response {
        case .offline:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        case .config, .invalid:
            let data = Data((response == .config ? "[{\"build\":\"fixture-base\"},{\"build\":\"fixture-new\"}]" : "<html>not configuration</html>").utf8)
            let http = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

@main
struct PrivacyAcceptance {
    struct CheckFailure: Error, CustomStringConvertible { let description: String }

    static func main() async throws {
        func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
            if try !condition() { throw CheckFailure(description: message) }
        }
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment
        let isolatedHome = URL(fileURLWithPath: env["UNREVOKE_ACCEPT_HOME"]!).standardizedFileURL
        let support = Engine.supportDirectory.standardizedFileURL
        // Fail before writing config if Foundation does not honor home isolation.
        try check(support.path.hasPrefix(isolatedHome.path + "/"), "Foundation support directory escaped isolated home")
        try check(Bundle.main.bundleIdentifier?.hasPrefix("io.github.zengtianli.unrevoke.accept.privacy.") == true,
                  "Refusing real app preferences domain")
        let defaults = UserDefaults.standard
        let resources = Bundle.main.resourceURL!
        let fakeApp = resources.appendingPathComponent("WeChat.app")
        try fm.createDirectory(at: fakeApp, withIntermediateDirectories: true)
        defaults.set(fakeApp.path, forKey: "weChatPath")
        let sentinel = isolatedHome.appendingPathComponent("synthetic-chat-canary.txt")
        let canary = "PRIVATE_FIXTURE_CHAT_7B5A83_DO_NOT_TRANSMIT"
        let sentinelBytes = Data(canary.utf8)
        try sentinelBytes.write(to: sentinel)
        defaults.set(canary, forKey: "privacy-canary")
        defer { defaults.removePersistentDomain(forName: Bundle.main.bundleIdentifier!) }
        let bundled = Engine.bundledConfigURL!
        try Data("[{\"build\":\"fixture-base\"}]".utf8).write(to: bundled)
        try check(Engine.activeConfigURL() == bundled, "Initial configuration did not use isolated bundle")
        print("PASS: production configuration paths stay inside a disposable home and app bundle")

        try check(URLProtocol.registerClass(PrivacyHTTPProtocol.self), "Could not register controlled HTTP transport")
        defer { URLProtocol.unregisterClass(PrivacyHTTPProtocol.self) }
        let engine = Engine()
        let refreshed = await engine.refreshConfig()
        try check(refreshed, "Injected configuration was not consumed by production refreshConfig")
        let requests = PrivacyHTTPProtocol.requests()
        try check(requests.count == 1, "Production configuration request escaped interception")
        let request = requests[0]
        try check(request.url == Engine.remoteConfigURL && request.url?.scheme == "https", "Unexpected configuration destination")
        try check(request.httpMethod == "GET" && request.httpBody == nil && request.httpBodyStream == nil,
                  "Configuration request carries an upload/body")
        try check(request.url?.query == nil && request.url?.user == nil && request.url?.password == nil,
                  "Configuration URL carries private parameters")
        let headers = request.allHTTPHeaderFields ?? [:]
        try check(!headers.keys.contains { ["authorization", "cookie", "proxy-authorization"].contains($0.lowercased()) },
                  "Configuration request carries credentials or cookies")
        let requestText = request.url!.absoluteString + String(describing: headers)
        try check(!requestText.contains(canary) && !requestText.contains(fakeApp.path), "Private state leaked into request")
        print("PASS: actual configuration request is one fixed HTTPS GET with no query, body, credentials, cookies or private fixture data")

        let cached = try Data(contentsOf: Engine.cachedConfigURL)
        try check(Engine.activeConfigURL() == Engine.cachedConfigURL, "Downloaded configuration was not selected")
        try check((try JSONSerialization.jsonObject(with: cached) as? [[String: Any]])?.count == 2,
                  "Production cache did not contain the injected response")
        print("PASS: successful refresh writes only the isolated configuration cache")

        PrivacyHTTPProtocol.select(.offline)
        let offline = await engine.refreshConfig()
        try check(!offline && Engine.activeConfigURL() == Engine.cachedConfigURL,
                  "Offline refresh discarded usable cache")
        try check(try Data(contentsOf: Engine.cachedConfigURL) == cached, "Offline response mutated cache")
        PrivacyHTTPProtocol.select(.invalid)
        let invalid = await engine.refreshConfig()
        try check(!invalid && (try Data(contentsOf: Engine.cachedConfigURL)) == cached,
                  "Malformed network response replaced valid cache")
        try Data("broken cache".utf8).write(to: Engine.cachedConfigURL)
        try check(Engine.activeConfigURL() == bundled, "Invalid cache did not fall back to bundled configuration")
        print("PASS: offline and invalid network responses preserve valid cache; corrupt cache falls back to bundled configuration")

        let args = resources.appendingPathComponent("doctor-arguments")
        let cli = resources.appendingPathComponent("wechattweak")
        let doctorData = resources.appendingPathComponent("doctor.json")
        try JSONSerialization.data(withJSONObject: ["overall": "unprotected", "build": "fixture",
            "app_path": fakeApp.path, "running": false, "writable": true,
            "config_known": true, "entitlements_ok": true]).write(to: doctorData)
        let script = """
        #!/bin/sh
        [ "$1" = doctor ] || exit 91
        printf '%s\\n' "$@" > \(Engine.shellQuote(args.path))
        /bin/cat \(Engine.shellQuote(doctorData.path))
        """
        try script.write(to: cli, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        let status = try await engine.doctor()
        let arguments = try String(contentsOf: args, encoding: .utf8).split(separator: "\n").map(String.init)
        try check(status.overall == .unprotected, "Doctor read path did not decode fixture")
        try check(arguments == ["doctor", "-a", fakeApp.path, "--json", "-c", bundled.path],
                  "Doctor received unexpected paths or arguments")
        try check(!arguments.joined().contains(canary), "Doctor received private preference data")
        print("PASS: actual doctor subprocess receives only the selected app/config paths and read-only command")

        try check(try Data(contentsOf: sentinel) == sentinelBytes, "Configuration/doctor modified synthetic chat data")
        try check(PrivacyHTTPProtocol.requests().count == 3, "Doctor unexpectedly issued network requests")
        let files = try fm.contentsOfDirectory(atPath: support.path)
        try check(files == ["config.json"], "Configuration path created unexpected files")
        print("PASS: synthetic chat sentinel remains unchanged and doctor adds no network traffic")
    }
}

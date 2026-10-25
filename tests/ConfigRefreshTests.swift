import Foundation

// #12: the startup download of config.json failed once, and "Check again" only re-ran doctor, so the
// app stayed on "not supported yet" although the published patch list already had the build.
// Runs the real AppModel -> Engine path with a stubbed network and an engine fixture that reports
// the build as known only when the config it is handed (-c) lists it.
@main
struct ConfigRefreshTests {
    static let build = "270135"

    @MainActor static func main() async throws {
        let fm = FileManager.default
        let resources = Bundle.main.resourceURL!
        let support = resources.appendingPathComponent("support")
        let app = resources.appendingPathComponent("WeChat.app")
        let patchMarker = resources.appendingPathComponent("patched")
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard
        defaults.set(app.path, forKey: "weChatPath")
        defaults.set(support.path, forKey: "supportDirectory")
        defaults.set(true, forKey: "autoRepatch")
        defer {
            for key in ["weChatPath", "supportDirectory", "autoRepatch", "lastBuild", "everProtected", "variant"] {
                defaults.removeObject(forKey: key)
            }
        }
        precondition(Engine.cachedConfigURL.path.hasPrefix(support.path), "cache must stay in the test directory")

        let doctor = """
        #!/bin/sh
        config=""; prev=""
        for arg in "$@"; do [ "$prev" = "-c" ] && config="$arg"; prev="$arg"; done
        case "$1" in
          doctor)
            if [ -n "$config" ] && /usr/bin/grep -q '"\(build)"' "$config"; then
              echo '{"overall":"unprotected","build":"\(build)","app_path":"x","config_known":true,"config_targets":["arm64"],"running":false,"writable":true,"entitlements_ok":true,"entitlement_key_count":17}'
            else
              echo '{"overall":"unsupportedBuild","build":"\(build)","app_path":"x","config_known":false,"running":false,"writable":true,"entitlements_ok":true,"entitlement_key_count":17}'
            fi;;
          patch|restore) /usr/bin/touch \(Engine.shellQuote(patchMarker.path)); exit 0;;
          *) exit 99;;
        esac
        """
        let cli = resources.appendingPathComponent("wechattweak")
        try doctor.write(to: cli, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)

        func list(_ versions: [String], marker: String = "") throws -> Data {
            try JSONSerialization.data(withJSONObject: versions.map {
                ["version": $0, "targets": [["identifier": "revoke" + marker, "arch": "arm64"]]]
            })
        }
        let oldVersions = (1...45).map { String(200000 + $0) }
        let old = try list(oldVersions)
        let current = try list(oldVersions + [build])
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        try old.write(to: Engine.cachedConfigURL)

        URLProtocol.registerClass(StubServer.self)
        func cached() -> Data { (try? Data(contentsOf: Engine.cachedConfigURL)) ?? Data() }

        // 1. Launch while the download fails: unsupported, and the failure is kept with its reason.
        StubServer.reply = .offline
        let model = AppModel()
        model.start()
        for _ in 0..<200 where model.configRefresh == nil { try await Task.sleep(for: .milliseconds(25)) }
        model.stop()
        precondition(model.status?.overall == .unsupportedBuild, "launch should end unsupported while offline")
        guard case .failed(let reason)? = model.configRefresh, reason.contains("network error") else {
            preconditionFailure("startup download failure must be reported, got \(String(describing: model.configRefresh))")
        }
        precondition(StubServer.requests == 1)
        precondition(model.diagnosticsReport?.contains("config refresh : failed: network error") == true)
        precondition(model.diagnosticsReport?.contains("lists build: no") == true)

        // 2. Network back. The doctor-only path (what v1.0.14's button ran) never asks the server: the bug.
        StubServer.reply = .ok(current)
        await model.refresh()
        precondition(StubServer.requests == 1 && model.status?.overall == .unsupportedBuild,
                     "plain refresh is doctor-only; this is why #12 stayed unsupported")

        // 3. The recheck button now downloads first, and the next doctor gets the new config.
        await model.recheck()
        precondition(StubServer.requests == 2, "recheck must re-download the patch database")
        precondition(model.configRefresh == .updated)
        precondition(model.status?.overall == .unprotected && model.status?.configKnown == true,
                     "the downloaded build must be recognised, got \(String(describing: model.status?.overall))")
        precondition(cached() == current)
        precondition(model.diagnosticsReport?.contains("config in use  : downloaded  builds: 46") == true)
        precondition(model.diagnosticsReport?.contains("lists build: yes") == true)
        precondition(!fm.fileExists(atPath: patchMarker.path), "recognising a build must not write WeChat unasked")

        // 4. Other states keep the button doctor-only.
        await model.recheck()
        precondition(StubServer.requests == 2)

        // 5. Same number of builds, corrected content: counts as an update. Same bytes: unchanged.
        let corrected = try list(oldVersions + [build], marker: "-fixed")
        StubServer.reply = .ok(corrected)
        let fixed = await model.updateConfig()
        precondition(fixed == .updated && cached() == corrected)
        let again = await model.updateConfig()
        precondition(again == .unchanged)

        // 6. Bad responses never replace a good cache.
        for (reply, expected) in [(StubServer.Reply.status(404), "HTTP 404"),
                                  (.ok(Data("<html>login</html>".utf8)), "not a patch list"),
                                  (.ok(old), "fewer than the 46")] {
            StubServer.reply = reply
            guard case .failed(let why) = await model.updateConfig(), why.contains(expected) else {
                preconditionFailure("expected failure containing \(expected)")
            }
            precondition(cached() == corrected, "bad response overwrote the cache")
        }

        // 7. Concurrent refreshes share one download.
        StubServer.reply = .ok(current)
        StubServer.delay = 0.3
        let before = StubServer.requests
        async let first = model.updateConfig()
        async let second = model.updateConfig()
        let results = await [first, second]
        StubServer.delay = 0
        precondition(StubServer.requests == before + 1 && results == [.updated, .updated], "\(results)")
        precondition(cached() == current)

        // 8. An already-open app that is unsupported picks up a server-side addition on its periodic tick.
        try old.write(to: Engine.cachedConfigURL)
        let open = AppModel()
        StubServer.reply = .offline
        await open.refresh()
        precondition(open.status?.overall == .unsupportedBuild)
        StubServer.reply = .ok(current)
        await open.periodicCheck()
        precondition(open.status?.overall == .unprotected, "periodic tick should retry the patch database")
        let afterTick = StubServer.requests
        try old.write(to: Engine.cachedConfigURL)
        await open.refresh()
        await open.periodicCheck()
        precondition(StubServer.requests == afterTick, "periodic retries are rate-limited")

        print("ConfigRefreshTests passed (\(StubServer.requests) stubbed requests)")
    }
}

final class StubServer: URLProtocol {
    enum Reply { case offline, status(Int), ok(Data) }
    nonisolated(unsafe) static var reply = Reply.offline
    nonisolated(unsafe) static var delay: TimeInterval = 0
    nonisolated(unsafe) static var requests = 0

    override class func canInit(with request: URLRequest) -> Bool { request.url == Engine.remoteConfigURL }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        StubServer.requests += 1
        let reply = StubServer.reply
        DispatchQueue.global().asyncAfter(deadline: .now() + StubServer.delay) { [self] in
            switch reply {
            case .offline:
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            case .status(let code):
                let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocolDidFinishLoading(self)
            case .ok(let data):
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            }
        }
    }
}

import SwiftUI

// =============================================================================
// ContentView — 一屏说清三件事：现在什么状态、点哪、出事了怎么自救。
//
// 刻意不做的：没有向导、没有多页签、没有把引擎日志当主界面。命令行版本的问题
// 从来不是功能少，是「要自己看 build 号、自己判断该跑哪条命令」。所以这里主按钮
// 永远只有一个，且它的文字就是接下来会发生的事。
// =============================================================================

struct ContentView: View {
    @StateObject private var model: AppModel
    @State private var showDetails = false
    private let automaticallyStart: Bool

    init() {
        _model = StateObject(wrappedValue: AppModel())
        automaticallyStart = true
    }

    /// Use the same native view in the isolated, offscreen acceptance app.
    init(model: AppModel, automaticallyStart: Bool, showDetails: Bool = false) {
        _model = StateObject(wrappedValue: model)
        self.automaticallyStart = automaticallyStart
        _showDetails = State(initialValue: showDetails)
    }

    func refresh() async { await model.refresh() }
    func close() { model.stop() }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 10) {
                        Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                            .resizable().frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("WeChatUnrevoke").font(.headline)
                            Text(L.t("撤回之后，消息仍在。", "Keep the message. Even after recall."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Link(destination: URL(string: "https://unrevoke.tianli.cyou/")!) {
                            Image(systemName: "arrow.up.right.square")
                        }
                        .help(L.t("安装教程与使用帮助", "Installation tutorials and help"))
                        .accessibilityLabel(L.t("安装教程与使用帮助", "Installation tutorials and help"))
                    }
                    statusCard
                    if let error = model.errorMessage { errorBox(error) }
                    if showsVariantPicker { variantPicker }
                    detailsSection
                    guardSection
                }
                .padding(24)
            }
            .topScrollAnchorIfAvailable()
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 520)
        .task { if automaticallyStart { model.start() } }
        .onDisappear { close() }
        .onReceive(NotificationCenter.default.publisher(for: .consoleRefresh)) { _ in
            Task { await refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .unrevokePreferencesChanged)) { _ in
            if automaticallyStart { model.reloadPortablePreferences() }
        }
        .overlay(alignment: .bottom) { toastView }
        .animation(.easeInOut(duration: 0.18), value: model.status)
    }

    // MARK: - 状态卡

    private var statusCard: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: look.symbol)
                .font(.system(size: 38, weight: .regular))
                .foregroundStyle(look.tint)
                .frame(width: 46)
            VStack(alignment: .leading, spacing: 6) {
                Text(look.title).font(.title2.weight(.semibold))
                Text(look.subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let status = model.status {
                    Text("\(L.det_build) \(status.fullVersion ?? status.shortVersion ?? status.build ?? "?")")
                        .font(.caption).foregroundStyle(.tertiary).padding(.top, 2)
                }
                actionRow.padding(.top, 10)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(look.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(look.tint.opacity(0.22)))
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            if model.isBusy {
                ProgressView().controlSize(.small)
                Text(model.busyMessage.isEmpty ? L.flow_working : model.busyMessage)
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                switch model.status?.overall {
                case .unprotected:
                    Button(L.btn_protect) { Task { await model.protectNow() } }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                case .partial:
                    Button(L.btn_repair) { Task { await model.protectNow() } }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                case .protected, .antiRevokeOnly:
                    Button(L.btn_recheck) { Task { await refresh() } }.controlSize(.large)
                case .brokenBundle, .mixed:
                    Button(L.btn_reinstall) {
                        NSWorkspace.shared.open(URL(string: "https://mac.weixin.qq.com")!)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    Button(L.btn_recheck) { Task { await refresh() } }.controlSize(.large)
                case .unsupportedBuild, .none:
                    Button(L.btn_recheck) { Task { await refresh() } }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
                if model.status?.needsAdmin == true {
                    Label(L.det_admin, systemImage: "lock")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private struct Look { let symbol: String; let tint: Color; let title: String; let subtitle: String }

    private var look: Look {
        switch model.status?.overall {
        case .protected:
            return Look(symbol: "checkmark.shield.fill", tint: .green, title: L.st_protected, subtitle: L.st_protectedSub)
        case .antiRevokeOnly:
            let sub = model.status?.updateBlock == "notApplicable" ? L.st_antiRevokeOnlySubAppStore : L.st_antiRevokeOnlySubUnavailable
            return Look(symbol: "checkmark.shield", tint: .green, title: L.st_protected, subtitle: sub)
        case .partial:
            return Look(symbol: "exclamationmark.shield.fill", tint: .orange, title: L.st_partial, subtitle: L.st_partialSub)
        case .unprotected:
            return Look(symbol: "shield", tint: .accentColor, title: L.st_unprotected, subtitle: L.st_unprotectedSub)
        case .unsupportedBuild:
            return Look(symbol: "questionmark.circle", tint: .orange, title: L.st_unsupported,
                        subtitle: L.st_unsupportedSub(model.status?.build ?? "?"))
        case .brokenBundle:
            return Look(symbol: "xmark.octagon.fill", tint: .red, title: L.st_broken, subtitle: L.st_brokenSub)
        case .mixed:
            return Look(symbol: "questionmark.diamond.fill", tint: .orange, title: L.st_mixed, subtitle: L.st_mixedSub)
        case .none:
            return Look(symbol: "hourglass", tint: .secondary, title: L.flow_working, subtitle: "")
        }
    }

    private func errorBox(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 变体

    private var showsVariantPicker: Bool {
        switch model.status?.overall {
        case .unprotected, .partial, .protected, .antiRevokeOnly: return true
        default: return false
        }
    }

    private var variantPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.variant_title).font(.headline)
            Picker("", selection: $model.variant) {
                Text(L.variant_keeptip).tag(PatchVariant.keeptip)
                Text(L.variant_silent).tag(PatchVariant.silent)
            }
            .pickerStyle(.segmented).labelsHidden()
            Text(model.variant == .keeptip ? L.variant_keeptipNote : L.variant_silentNote)
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 详情

    private var detailsSection: some View {
        DisclosureGroup(isExpanded: $showDetails) {
            VStack(spacing: 0) {
                ForEach(detailRows, id: \.0) { row in
                    HStack {
                        Text(row.0).foregroundStyle(.secondary)
                        Spacer()
                        Text(row.1).monospacedDigit().textSelection(.enabled)
                    }
                    .font(.callout)
                    .padding(.vertical, 6)
                    Divider()
                }
            }
            .padding(.top, 6)
        } label: {
            Text(L.btn_details).font(.headline)
        }
    }

    private var detailRows: [(String, String)] {
        guard let s = model.status else { return [] }
        func patchState(_ raw: String?) -> String {
            switch raw {
            case "patched": return L.det_on
            case "pristine": return L.det_off
            case "unknown": return L.det_weird
            case "unavailable": return L.det_unavailable
            default: return L.det_na
            }
        }
        let revoke: String = {
            if s.antiRevokeKeeptip == "patched" { return "\(L.det_on) · \(L.variant_keeptip)" }
            if s.antiRevokeSilent == "patched" { return "\(L.det_on) · \(L.variant_silent)" }
            return patchState(s.antiRevokeSilent ?? s.antiRevokeKeeptip)
        }()
        return [
            (L.det_build, s.fullVersion ?? s.shortVersion ?? s.build ?? "?"),
            ("Build", s.build ?? "?"),
            (L.det_channel, s.installChannel ?? L.det_unknown),
            (L.det_antiRevoke, revoke),
            (L.det_updateBlock, patchState(s.updateBlock)),
            (L.det_entitlements, s.entitlementsOK ? "\(L.det_intact) (\(s.entitlementKeyCount))" : L.det_lost),
            (L.det_signature, s.signature),
            (L.det_sip, s.sip),
            (L.det_admin, s.needsAdmin ? L.det_yes : L.det_no),
        ]
    }

    // MARK: - 守护

    private var guardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(L.guard_title, isOn: $model.autoRepatch)
            Text(L.guard_note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle(L.guard_launchAtLogin, isOn: $model.launchAtLogin).padding(.top, 4)
        }
    }

    // MARK: - 页脚

    private var footer: some View {
        HStack(spacing: 12) {
            Button(L.btn_copyReport) { model.copyReport() }
            Spacer()
            if [.protected, .antiRevokeOnly, .partial].contains(model.status?.overall) {
                Button(L.btn_restore, role: .destructive) { Task { await model.restoreNow() } }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .disabled(model.isBusy)
    }

    @ViewBuilder private var toastView: some View {
        if let toast = model.toast {
            Text(toast)
                .font(.callout)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 6, y: 2)
                .padding(.bottom, 64)
                .transition(.opacity)
                .task(id: toast) {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    model.toast = nil
                }
        }
    }
}

private extension View {
    @ViewBuilder func topScrollAnchorIfAvailable() -> some View {
        if #available(macOS 14.0, *) {
            defaultScrollAnchor(.top)
        } else {
            // macOS 13 ScrollView starts at the top without this newer API.
            self
        }
    }
}

/// In-process native UI acceptance. The runner provides a disposable app bundle
/// and a doctor-only fixture executable; this never operates on installed WeChat.
@MainActor
enum NativeUISelfTest {
    static func launch() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do {
                try await run()
                exit(0)
            } catch {
                fputs("native_ui failed: \(error)\n", stderr)
                exit(1)
            }
        }
        app.run()
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "NativeUISelfTest", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    private static func run() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let bundleID = Bundle.main.bundleIdentifier,
              bundleID.hasPrefix("io.github.zengtianli.unrevoke.accept.nativeui."),
              let root = env["UNREVOKE_UI_FIXTURE"], let output = env["UNREVOKE_UI_OUTPUT"] else {
            throw NSError(domain: "NativeUISelfTest", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Run scripts/accept/native_ui.py with an isolated bundle."])
        }
        let fixture = URL(fileURLWithPath: root)
        let expectedPath = fixture.appendingPathComponent("WeChat.app").path
        try require(Engine.weChatPath == expectedPath, "The test target must be the disposable fixture")
        try require(!UserDefaults.standard.bool(forKey: "autoRepatch"), "Automatic writes must be disabled")
        defer { UserDefaults.standard.removePersistentDomain(forName: bundleID) }
        let model = AppModel(confirmAction: { _, _, _ in false })
        model.autoRepatch = false
        let view = ContentView(model: model, automaticallyStart: false, showDetails: true)
        let hosting = NSHostingView(rootView: view
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
            .background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 620, height: 820),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        defer { model.stop(); window.close() }
        var checks: [String: Bool] = [:]
        checks["automatic_writes_disabled"] = !model.autoRepatch
        var captures: [[String: Any]] = []

        func state(_ name: String) throws {
            try name.write(to: fixture.appendingPathComponent("state"), atomically: true, encoding: .utf8)
        }
        func capture(_ name: String, width: CGFloat = 620, height: CGFloat = 820) throws {
            window.setContentSize(NSSize(width: width, height: height))
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                throw NSError(domain: "NativeUISelfTest", code: 3)
            }
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "NativeUISelfTest", code: 4)
            }
            try require(bitmap.pixelsWide >= Int(width) && bitmap.pixelsHigh >= Int(height), "Incorrect native render dimensions")
            try require(png.count > 12000, "Native view rendered an empty image")
            let path = URL(fileURLWithPath: output).appendingPathComponent(name + ".png")
            try png.write(to: path)
            captures.append(["file": name + ".png", "width": bitmap.pixelsWide,
                             "height": bitmap.pixelsHigh, "bytes": png.count])
        }

        try state("protected")
        await view.refresh() // The same asynchronous action used by the recheck button.
        try await Task.sleep(for: .milliseconds(250))
        checks["refresh_decodes_build_and_entitlements"] = model.status?.overall == .protected
            && model.status?.build == "90001" && model.status?.entitlementKeyCount == 3
            && model.status?.entitlementsOK == true && model.errorMessage == nil
        try capture("protected")

        try state("antiRevokeOnly")
        // Exercise the real menu/notification refresh handler without keyboard events.
        NotificationCenter.default.post(name: .consoleRefresh, object: nil)
        for _ in 0..<40 {
            if model.status?.overall == .antiRevokeOnly { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        checks["refresh_action_accepts_independent_update_result"] = model.status?.overall == .antiRevokeOnly
            && model.status?.updateBlock == "notApplicable" && model.errorMessage == nil
        try await Task.sleep(for: .milliseconds(200))
        try capture("anti-revoke-only")

        model.variant = .silent
        checks["variant_binding_persists_in_isolated_domain"] = UserDefaults.standard.string(forKey: "variant") == "silent"
        try state("failure")
        await view.refresh()
        try await Task.sleep(for: .milliseconds(100))
        checks["engine_error_visible_without_losing_previous_state"] = model.errorMessage?.contains("UI fixture read failed") == true
            && model.status?.overall == .antiRevokeOnly && !model.isBusy
        try capture("error")

        try state("unprotected")
        await view.refresh()
        try await Task.sleep(for: .milliseconds(200))
        checks["refresh_recovers_error_and_shows_unprotected"] = model.status?.overall == .unprotected
            && model.errorMessage == nil && !model.isBusy
        try capture("unprotected")
        try capture("minimum-size", width: 560, height: 520)
        checks["native_view_minimum_size"] = hosting.bounds.width >= 560 && hosting.bounds.height >= 520
        checks["no_visible_or_key_windows"] = !window.isVisible && !window.isKeyWindow
            && NSApplication.shared.windows.allSatisfy { !$0.isVisible && !$0.isKeyWindow }
        view.close() // The same cleanup path used by ContentView.onDisappear.
        window.close()
        checks["close_action"] = !window.isVisible && !model.isBusy
        let result: [String: Any] = ["checks": checks, "captures": captures,
            "scope": "real ContentView and AppModel; isolated doctor subprocess fixtures; no installed app, input, clipboard or network actions"]
        let json = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: URL(fileURLWithPath: output).appendingPathComponent("result.json"))
        let failed = checks.filter { !$0.value }.map(\.key).sorted()
        try require(failed.isEmpty, "Failed checks: \(failed.joined(separator: ", "))")
        print("native_ui: \(checks.count) checks passed; \(captures.count) offscreen native renders")
    }
}

#if APP_STORE
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// The store distribution is an offline compatibility and saved-diagnostics viewer.
// It never calculates DoctorStatus.overall or loads executable patch code.
struct StoreCatalog: Decodable {
    struct Target: Decodable {
        struct Entry: Decodable { let arch: String }
        let identifier: String
        let entries: [Entry]
    }
    let version: String
    let targets: [Target]

    static func bundled() throws -> [StoreCatalog] {
        guard let url = Bundle.main.url(forResource: "config", withExtension: "json") else {
            throw StoreFailure.message(String(localized: "The bundled catalog is missing. Reinstall this test build."))
        }
        let catalog = try JSONDecoder().decode([StoreCatalog].self, from: Data(contentsOf: url))
        guard !catalog.isEmpty else { throw StoreFailure.message(String(localized: "The catalog is empty.")) }
        return catalog
    }

    var summary: String {
        targets.map { target in
            "\(target.identifier): \(Set(target.entries.map(\.arch)).sorted().joined(separator: ", "))"
        }.joined(separator: "\n")
    }
}

enum StoreFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

struct StoreInstallation {
    let path: String
    let version: String
    let build: String

    static func read(_ url: URL) throws -> StoreInstallation {
        let data = try Data(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == "com.tencent.xinWeChat",
              let build = info["CFBundleVersion"] as? String, !build.isEmpty else {
            throw StoreFailure.message(String(localized: "Select a valid WeChat app for Mac."))
        }
        return StoreInstallation(path: url.path, version: info["WeChatBundleVersion"] as? String ?? info["CFBundleShortVersionString"] as? String ?? "—", build: build)
    }
}

@MainActor
final class StoreModel: ObservableObject {
    @Published private(set) var catalog: [StoreCatalog] = []
    @Published private(set) var installation: StoreInstallation?
    @Published private(set) var savedStatus: DoctorStatus?
    @Published private(set) var reportName: String?
    @Published private(set) var importedAt: Date?
    @Published var error: String?
    private var originalReport: Data?

    init() {
        do { catalog = try StoreCatalog.bundled() }
        catch { self.error = error.localizedDescription }
    }

    var selectedEntry: StoreCatalog? { catalog.first { $0.version == installation?.build } }
    static var limitation: String {
        String(localized: "This sandboxed TestFlight build checks versions and saved diagnostics only. It cannot apply or restore anti-recall patches, block WeChat updates, or repatch automatically. Catalog coverage does not mean protection is active.")
    }

    func inspect(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let result = try StoreInstallation.read(url)
        installation = result
        error = nil
    }

    func importReport(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 4_194_304 else {
            throw StoreFailure.message(String(localized: "The diagnostic file exceeds 4 MB."))
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let status = try decoder.decode(DoctorStatus.self, from: data)
        // Commit only after a complete successful decode. A saved result is never
        // substituted for a live inspection of the selected installation.
        savedStatus = status
        originalReport = data
        reportName = url.lastPathComponent
        importedAt = Date()
        error = nil
    }

    func selectInstallation() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Select WeChat for a read-only version check. It will not be modified.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try inspect(url) } catch { self.error = error.localizedDescription }
    }

    func selectReport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Select a report saved with the downloadable engine's doctor --json command.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try importReport(url) } catch { self.error = error.localizedDescription }
    }

    var diagnostics: String {
        var lines = ["WeChatUnrevoke · TestFlight", Self.limitation,
                     "App: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))",
                     "Catalog builds: \(catalog.count)"]
        if let app = installation {
            lines += ["Selected app: \(app.path)", "WeChat: \(app.version) (\(app.build))",
                      "Catalog entry: \(selectedEntry?.summary ?? "not listed")", "Live protection state: not checked"]
        }
        if let originalReport, let raw = String(data: originalReport, encoding: .utf8) {
            lines += ["", "Saved engine report (historical; not a live check): \(reportName ?? "")",
                      "Imported: \(importedAt?.ISO8601Format() ?? "")", raw]
        }
        return lines.joined(separator: "\n")
    }

    func exportReport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "WeChatUnrevoke-diagnostics.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try diagnostics.write(to: url, atomically: true, encoding: .utf8) }
        catch { self.error = error.localizedDescription }
    }
}

struct StoreContentView: View {
    @ObservedObject var model: StoreModel
    @State private var search = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("WeChatUnrevoke", systemImage: "checkmark.shield").font(.largeTitle.bold())
                Text(String(localized: "WeChat versions & diagnostics · TestFlight")).font(.title3)
                Text(StoreModel.limitation).font(.callout).foregroundStyle(.secondary)
                GroupBox(String(localized: "WeChat version")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Button(String(localized: "Select WeChat App…"), action: model.selectInstallation)
                            .keyboardShortcut("o")
                        if let app = model.installation {
                            Text("\(app.version) (\(app.build))").font(.headline)
                            Text(app.path).font(.caption).textSelection(.enabled)
                            Label(model.selectedEntry == nil ? String(localized: "Build not listed in this snapshot") : String(localized: "Build listed in the catalog"),
                                  systemImage: "list.bullet.rectangle")
                                .foregroundStyle(model.selectedEntry == nil ? Color.orange : Color.primary)
                            if let entry = model.selectedEntry { Text(entry.summary).font(.caption.monospaced()) }
                            Text(String(localized: "Version lookup only; current protection has not been checked.")).font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(String(localized: "Grant read access through the system file picker.")).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                GroupBox(String(localized: "Saved engine diagnostics")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Button(String(localized: "Import diagnostic JSON…"), action: model.selectReport)
                        if let status = model.savedStatus {
                            Text("\(String(localized: "Original engine verdict")): \(status.overall.rawValue)").font(.headline).textSelection(.enabled)
                            Text("\(model.reportName ?? "") · \(status.fullVersion ?? status.shortVersion ?? status.build ?? "—")")
                            Text(status.appPath).font(.caption).textSelection(.enabled)
                            Text("\(String(localized: "Anti-recall (keep tip)")): \(status.antiRevokeKeeptip ?? "—")\n\(String(localized: "Anti-recall (silent)")): \(status.antiRevokeSilent ?? "—")\n\(String(localized: "Update block")): \(status.updateBlock ?? "—")")
                                .font(.caption.monospaced())
                            if !status.verdict.isEmpty { Text(status.verdict.joined(separator: "\n")).font(.callout) }
                            Text(String(localized: "This is a historical file result, not the current state of the selected WeChat app.")).font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(String(localized: "Read a report generated by the downloadable engine, preserving its verdict. This build does not run the patch engine.")).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                GroupBox(String(localized: "Bundled catalog snapshot")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(localized: "\(model.catalog.count) builds listed; updated with TestFlight releases."))
                        TextField(String(localized: "Filter by build number"), text: $search)
                        let filtered = model.catalog.filter { search.isEmpty || $0.version.contains(search) }
                        ForEach(filtered.prefix(12), id: \.version) { entry in
                            DisclosureGroup(entry.version) { Text(entry.summary).font(.caption.monospaced()).frame(maxWidth: .infinity, alignment: .leading) }
                        }
                        if filtered.isEmpty { Text(String(localized: "No matching builds.")).foregroundStyle(.secondary) }
                        if filtered.count > 12 { Text(String(localized: "Enter a build number to narrow the results.")).font(.caption) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                if let error = model.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                Button(String(localized: "Export diagnostics…"), action: model.exportReport)
                    .keyboardShortcut("s").disabled(model.installation == nil && model.savedStatus == nil)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(minWidth: 580, idealWidth: 640, minHeight: 620, idealHeight: 780)
            .task { LaneSignal.applyWindowFrame(); LaneSignal.ready("store-diagnostics") }
    }
}

@MainActor
final class StoreDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        LaneSignal.enterQuietIfAsked()
    }
}

struct StoreApplication: App {
    @NSApplicationDelegateAdaptor(StoreDelegate.self) private var delegate
    @StateObject private var model = StoreModel()
    var body: some Scene {
        WindowGroup { StoreContentView(model: model) }
            .defaultSize(width: 640, height: 780)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}

@main
@MainActor
enum StoreEntry {
    static func main() {
        if CommandLine.arguments.contains("--store-self-test") || CommandLine.arguments.contains("--ui-self-test") {
            let app = NSApplication.shared
            app.setActivationPolicy(.prohibited)
            do { try selfTest(); exit(0) }
            catch { print("FAIL: \(error)"); exit(1) }
        }
        StoreApplication.main()
    }

    static func selfTest() throws {
        var checks: [String: Bool] = [:]
        func require(_ value: Bool, _ name: String) throws {
            checks[name] = value
            if !value { throw StoreFailure.message(name) }
        }
        try require(NSHomeDirectory().contains("/Library/Containers/"), "sandbox_container")
        let model = StoreModel()
        try require(model.error == nil && !model.catalog.isEmpty, "bundled_catalog")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("store-self-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = root.appendingPathComponent("WeChat.app")
        try FileManager.default.createDirectory(at: fixture.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let infoURL = fixture.appendingPathComponent("Contents/Info.plist")
        let info: [String: String] = ["CFBundleIdentifier": "com.tencent.xinWeChat", "CFBundleVersion": model.catalog[0].version, "CFBundleShortVersionString": "test-fixture"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: infoURL)
        try model.inspect(fixture)
        try require(model.selectedEntry?.version == model.catalog[0].version, "read_wechat_metadata_and_lookup")
        var unsupported = info
        unsupported["CFBundleVersion"] = "self-test-unlisted"
        try PropertyListSerialization.data(fromPropertyList: unsupported, format: .xml, options: 0).write(to: infoURL)
        try model.inspect(fixture)
        try require(model.selectedEntry == nil, "unlisted_build")
        unsupported["CFBundleIdentifier"] = "invalid.bundle"
        try PropertyListSerialization.data(fromPropertyList: unsupported, format: .xml, options: 0).write(to: infoURL)
        var rejectedApp = false
        do { try model.inspect(fixture) }
        catch StoreFailure.message(_) { rejectedApp = true }
        try require(rejectedApp, "reject_non_wechat")
        let report = root.appendingPathComponent("doctor.json")
        // Deliberately inconsistent component bytes prove that the store preserves
        // the engine's overall verdict rather than calculating a replacement.
        let raw = Data(#"{"overall":"antiRevokeOnly","app_path":"/fixture/WeChat.app","config_known":true,"running":false,"writable":false,"entitlements_ok":true,"anti_revoke_silent":"pristine","update_block":"unavailable","verdict":["fixture only"]}"#.utf8)
        try raw.write(to: report)
        try model.importReport(report)
        try require(model.savedStatus?.overall == .antiRevokeOnly && model.savedStatus?.entitlementsOK == true, "original_doctor_decoder_and_verdict")
        try Data("{}".utf8).write(to: report)
        var rejectedReport = false
        do { try model.importReport(report) }
        catch is DecodingError { rejectedReport = true }
        try require(rejectedReport, "reject_malformed_report")
        try require(model.savedStatus?.overall == .antiRevokeOnly, "failed_import_preserves_previous_report")
        let exported = root.appendingPathComponent("diagnostics.txt")
        try model.diagnostics.write(to: exported, atomically: true, encoding: .utf8)
        try require(try String(contentsOf: exported, encoding: .utf8) == model.diagnostics, "export_readback")
        try require(model.diagnostics.contains(String(decoding: raw, as: UTF8.self)), "export_preserves_original_json")
        let view = NSHostingView(rootView: StoreContentView(model: model))
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 1200)
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw StoreFailure.message("offscreen_bitmap") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try require(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0, "production_view_offscreen")
        let screenshot = FileManager.default.temporaryDirectory.appendingPathComponent("unrevoke-store-self-test.png")
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw StoreFailure.message("offscreen_png") }
        try png.write(to: screenshot)
        // A zero-write open probes sandbox denial without changing WeChat bytes,
        // launching the patch engine, escalating privileges or closing WeChat.
        let target = "/Applications/WeChat.app/Contents/Info.plist"
        var probe: [String: Any] = ["path": target, "writes_performed": 0]
        do {
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: target))
            try handle.close()
            probe["write_open_allowed"] = true
        } catch {
            let e = error as NSError
            probe["write_open_allowed"] = false
            probe["error_domain"] = e.domain
            probe["error_code"] = e.code
            probe["error"] = e.localizedDescription
        }
        let output: [String: Any] = ["ok": true, "checks": checks, "sandbox_home": NSHomeDirectory(), "capability_probe": probe, "screenshot": screenshot.path]
        print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), as: UTF8.self))
    }
}
#endif

import SwiftUI

// =============================================================================
// ContentView — 一屏说清三件事：现在什么状态、点哪、出事了怎么自救。
//
// 刻意不做的：没有向导、没有多页签、没有把引擎日志当主界面。命令行版本的问题
// 从来不是功能少，是「要自己看 build 号、自己判断该跑哪条命令」。所以这里主按钮
// 永远只有一个，且它的文字就是接下来会发生的事。
// =============================================================================

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var showDetails = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statusCard
                    if let error = model.errorMessage { errorBox(error) }
                    if showsVariantPicker { variantPicker }
                    detailsSection
                    guardSection
                }
                .padding(24)
            }
            .defaultScrollAnchor(.top)
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 520)
        .task { model.start() }
        .onDisappear { model.stop() }
        .onReceive(NotificationCenter.default.publisher(for: .consoleRefresh)) { _ in
            Task { await model.refresh() }
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
                if let build = model.status?.build {
                    Text("\(L.det_build) \(build)").font(.caption).foregroundStyle(.tertiary).padding(.top, 2)
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
                case .protected:
                    Button(L.btn_recheck) { Task { await model.refresh() } }.controlSize(.large)
                case .brokenBundle, .mixed:
                    Button(L.btn_reinstall) {
                        NSWorkspace.shared.open(URL(string: "https://mac.weixin.qq.com")!)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    Button(L.btn_recheck) { Task { await model.refresh() } }.controlSize(.large)
                case .unsupportedBuild, .none:
                    Button(L.btn_recheck) { Task { await model.refresh() } }
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
        case .unprotected, .partial, .protected: return true
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
            default: return L.det_na
            }
        }
        let revoke: String = {
            if s.antiRevokeKeeptip == "patched" { return "\(L.det_on) · \(L.variant_keeptip)" }
            if s.antiRevokeSilent == "patched" { return "\(L.det_on) · \(L.variant_silent)" }
            return patchState(s.antiRevokeSilent ?? s.antiRevokeKeeptip)
        }()
        return [
            (L.det_build, s.build ?? "?"),
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
            if model.status?.overall == .protected || model.status?.overall == .partial {
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

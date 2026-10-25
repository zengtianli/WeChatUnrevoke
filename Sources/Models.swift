import Foundation

// =============================================================================
// Models — `wechattweak doctor --json` 的解码契约
//
// 判决只算一次，算在引擎里（WeChatTweak/Sources/WeChatTweak/Doctor.swift 的
// Status.overall）。这里**只解码不推导** —— GUI 一旦自己从各字段重新推一遍
// 「到底保护上了没」，改引擎那天两边就会给出不同答案，而这种分叉没有任何门能拦。
// =============================================================================

/// 一趟只读检查的结果。字段名与引擎 snake_case 输出经 `.convertFromSnakeCase` 对应。
struct DoctorStatus: Decodable, Equatable {
    /// 引擎给出的唯一判决，按严重程度排序：坏掉的 bundle 压过「没打补丁」。
    enum Overall: String, Decodable {
        /// 签名权限被剥掉了，微信起不来 —— 只能重装
        case brokenBundle
        /// 某个补丁点的字节既不是原始也不是我们写的（别的工具动过 / 版本对不上）
        case mixed
        /// config.json 还没收录这个 build
        case unsupportedBuild
        /// 防撤回 + 更新拦截都在
        case protected
        /// 防撤回在；这个版本拦不了自动更新（App Store 版 / 更新器未定位），原因见 updateBlock、updateSource。
        /// 两者是独立功能：拦不了更新不影响防撤回，也不需要用户再做什么。
        case antiRevokeOnly
        /// 只装了一半
        case partial
        /// 都没装，且没有任何阻碍
        case unprotected
    }

    let overall: Overall
    let build: String?
    let fullVersion: String?
    let shortVersion: String?
    let installChannel: String?
    /// 微信在这台 Mac 上实际执行的架构（"arm64" / "x86_64"）；旧引擎不提供时为 nil。
    let hostArch: String?
    /// false → 补丁库认识这个 build，但没有本机架构的防撤回补丁点。判决仍是引擎的
    /// `overall`（此时为 unsupportedBuild），这个字段只用来把原因说清楚。
    let archSupported: Bool
    /// 引擎从文件系统读到的写入障碍（needsAdmin / immutable / aclDeny / readOnlyVolume）。
    let writeBlockers: [String]
    /// 这个 build 在本机架构上有补丁点的防撤回方式；旧引擎不提供时为 nil（两种都照常提供）。
    let availableVariants: [String]?
    let appPath: String
    let configKnown: Bool
    let configTargets: [String]
    /// "enabled" / "disabled" / "unknown"
    let sip: String
    let running: Bool
    /// false → 打补丁必须提权
    let writable: Bool
    let signature: String
    let entitlementsOK: Bool
    let entitlementKeyCount: Int
    /// "patched" / "pristine" / "unknown"，该 build 没有这个 target 时为 nil
    let antiRevokeSilent: String?
    let antiRevokeKeeptip: String?
    let updateBlock: String?
    let updateSource: String
    let verdict: [String]
    let nextCommand: String?

    private enum CodingKeys: String, CodingKey {
        case overall, build, fullVersion, shortVersion, installChannel
        case hostArch, archSupported, writeBlockers, availableVariants
        case appPath, configKnown, configTargets, sip, running, writable
        case signature, entitlementsOk, entitlementKeyCount
        case antiRevokeSilent, antiRevokeKeeptip, updateBlock, updateSource, verdict, nextCommand
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        overall = try c.decode(Overall.self, forKey: .overall)
        build = try c.decodeIfPresent(String.self, forKey: .build)
        fullVersion = try c.decodeIfPresent(String.self, forKey: .fullVersion)
        shortVersion = try c.decodeIfPresent(String.self, forKey: .shortVersion)
        installChannel = try c.decodeIfPresent(String.self, forKey: .installChannel)
        hostArch = try c.decodeIfPresent(String.self, forKey: .hostArch)
        archSupported = try c.decodeIfPresent(Bool.self, forKey: .archSupported) ?? true
        writeBlockers = try c.decodeIfPresent([String].self, forKey: .writeBlockers) ?? []
        availableVariants = try c.decodeIfPresent([String].self, forKey: .availableVariants)
        appPath = try c.decode(String.self, forKey: .appPath)
        configKnown = try c.decode(Bool.self, forKey: .configKnown)
        configTargets = try c.decodeIfPresent([String].self, forKey: .configTargets) ?? []
        sip = try c.decodeIfPresent(String.self, forKey: .sip) ?? "unknown"
        running = try c.decode(Bool.self, forKey: .running)
        writable = try c.decode(Bool.self, forKey: .writable)
        signature = try c.decodeIfPresent(String.self, forKey: .signature) ?? ""
        // 引擎侧字段名是 entitlementsOK；.convertToSnakeCase 把它写成 entitlements_ok，
        // 解回来是 entitlementsOk（小写 k）—— 大小写在这条链上会变，所以显式列 CodingKey，
        // 不靠「看起来一样」。这一条本身就是 CodingKeys × convertFromSnakeCase 那个坑。
        entitlementsOK = try c.decode(Bool.self, forKey: .entitlementsOk)
        entitlementKeyCount = try c.decodeIfPresent(Int.self, forKey: .entitlementKeyCount) ?? 0
        antiRevokeSilent = try c.decodeIfPresent(String.self, forKey: .antiRevokeSilent)
        antiRevokeKeeptip = try c.decodeIfPresent(String.self, forKey: .antiRevokeKeeptip)
        updateBlock = try c.decodeIfPresent(String.self, forKey: .updateBlock)
        updateSource = try c.decodeIfPresent(String.self, forKey: .updateSource) ?? ""
        verdict = try c.decodeIfPresent([String].self, forKey: .verdict) ?? []
        nextCommand = try c.decodeIfPresent(String.self, forKey: .nextCommand)
    }

    /// 当前生效的防撤回变体；都没打则 nil。
    var activeVariant: PatchVariant? {
        if antiRevokeSilent == "patched" { return .silent }
        if antiRevokeKeeptip == "patched" { return .keeptip }
        return nil
    }

    /// 引擎说这台 Mac 上只有一种防撤回方式可用时，就是那一种；否则 nil（由用户选）。
    var onlyVariant: PatchVariant? {
        guard let list = availableVariants, list.count == 1 else { return nil }
        return PatchVariant(rawValue: list[0])
    }

    /// 打补丁需要提权（4.1.13 之前的包是 root 所有）。
    var needsAdmin: Bool { !writable }
}

/// 防撤回的两种做法。keeptip 是默认：消息留着，且私聊仍显示「对方撤回了一条消息」。
enum PatchVariant: String, CaseIterable, Identifiable {
    case keeptip
    case silent
    var id: String { rawValue }
}

// =============================================================================
// L — 中英文案
//
// 受众两边都在：上游 issue 里问的人说中文，GitHub 上找过来的人说英文。
// 文案由 Localizable.xcstrings 同时维护英文和简体中文，跟随系统语言。
// =============================================================================

enum L {

    // 错误
    static var err_cliMissing: String { String(localized: "The wechattweak engine is missing from this app bundle — this build is incomplete, please download WeChatUnrevoke again.") }
    static func err_launch(_ m: String) -> String { String(localized: "Failed to launch the engine: \(m)") }
    static func err_decode(_ m: String, _ raw: String) -> String { String(localized: "Could not parse the engine output (\(m)). Raw: \(raw)") }
    static func err_timeout(_ s: Int) -> String { String(localized: "The engine did not finish within \(s)s and was terminated. Re-signing a large WeChat bundle is slow — try again.") }
    static var err_authCanceled: String { String(localized: "You canceled the authorization — nothing was changed.") }
    static var err_writePermissionDenied: String { String(localized: "Access to WeChat files was denied; this error alone does not identify the cause. Check each item:\n1. Administrator access: root-owned files or missing user write access require administrator authorization for this operation.\n2. File permissions and locks: check the reported file and its directory for ownership, access permissions, ACLs and immutable flags (uchg/schg). Administrator authorization may not remove a lock.\n3. App Management: if file permissions are correct, allow the current WeChatUnrevoke in System Settings → Privacy & Security → App Management, then quit and reopen it. This system permission is separate from administrator authorization.\nEntitlements are shown in Details and are separate from file write permissions. Keep the original engine log when copying diagnostics.") }
    /// 引擎在写入被拒后给出的原因代码（`Write blocked: <codes>`）→ 对应的恢复办法。
    /// 原因由引擎判定，这里只负责把每个代码翻成一句能照做的话。
    static func err_writeBlocked(_ codes: [String]) -> String {
        let lines = codes.map { code -> String in
            switch code {
            case "needsAdmin": return String(localized: "WeChat's files belong to another user (usually root) and this user cannot write them. Try again and complete the administrator authorization in the system dialog.")
            case "immutable": return String(localized: "WeChat's files are locked (immutable flag — \"Locked\" in Finder's Get Info). An administrator password does not bypass a lock. Untick Locked in Finder, or run chflags -R nouchg /Applications/WeChat.app in Terminal, then retry.")
            case "aclDeny": return String(localized: "An access-control entry (ACL) denies writing to WeChat's files. Inspect it with ls -le in Terminal and remove the deny entry, then retry.")
            case "readOnlyVolume": return String(localized: "WeChat is on a read-only location (opened straight from the disk image, or translocated). Drag WeChat into Applications and use that copy.")
            case "appManagement": return String(localized: "Owner, permissions, locks and access control all allow the write, yet macOS refused it — most likely the App Management permission is missing. In System Settings → Privacy & Security → App Management, enable WeChatUnrevoke (use + to add this copy if it is not listed), quit and reopen this app, then retry. If it is already enabled there and the write is still refused (this happens after updating this app — the permission is tied to the version that was granted): select WeChatUnrevoke, remove it with −, then add this copy with +. An administrator password does not replace this permission; security software that protects apps can cause the same refusal.")
            default: return String(localized: "Write blocker reported by the engine: \(code)")
            }
        }
        return ([String(localized: "Could not write WeChat's files. Cause and fix:")] + lines).joined(separator: "\n")
    }
    static func blockerName(_ code: String) -> String {
        switch code {
        case "needsAdmin": return String(localized: "Needs administrator authorization")
        case "immutable": return String(localized: "Files are locked")
        case "aclDeny": return String(localized: "An ACL denies writing")
        case "readOnlyVolume": return String(localized: "Read-only location")
        case "appManagement": return String(localized: "App Management permission missing")
        default: return code
        }
    }
    static var err_wechatStillRunning: String { String(localized: "WeChat has not fully quit yet. Its helper processes linger a few seconds after the main one — wait a moment and try again.") }
    static var err_noWeChat: String { String(localized: "No WeChat.app in /Applications. Install WeChat from mac.weixin.qq.com first.") }

    // 状态卡
    static var st_protected: String { String(localized: "Anti-recall is on") }
    static var st_protectedSub: String { String(localized: "WeChat's auto-updater is blocked too, so the next update can't silently wipe the patch.") }
    static var st_unprotected: String { String(localized: "Not patched yet") }
    static var st_unprotectedSub: String { String(localized: "Hit the button below and recalled messages will stay in your chat.") }
    static var st_partial: String { String(localized: "Partially protected") }
    static var st_partialSub: String { String(localized: "One of anti-recall and the update block is still missing. Use the button below to add it.") }
    static var st_antiRevokeOnlySubAppStore: String { String(localized: "This is the App Store edition: the App Store updates it, so there is no in-app updater to block. Turn off App Store automatic updates to keep the patch.") }
    static var st_antiRevokeOnlySubUnavailable: String { String(localized: "This WeChat build's auto-updater can't be blocked yet (its patch points aren't covered). Anti-recall is unaffected; after a WeChat update the patch is gone and this app will remind you to turn it on again.") }
    static var st_unsupported: String { String(localized: "This WeChat build isn't covered yet") }
    static func st_unsupportedSub(_ build: String) -> String { String(localized: "The patch configuration does not yet support build \(build). Configuration updates arrive online; new engine rules may require a WeChatUnrevoke update.") }
    static func st_unsupportedArchSub(_ build: String, _ arch: String) -> String { String(localized: "The patch configuration has build \(build), but only for the other processor architecture. On this Mac WeChat runs \(arch) code, so applying those points would change nothing — the switch is not offered. Points for this architecture arrive with online configuration updates once they are covered.") }
    static var st_broken: String { String(localized: "WeChat lost its entitlements") }
    static var st_brokenSub: String { String(localized: "Some tool re-signed it the wrong way. In this state WeChat won't launch at all on a machine with SIP on — reinstall it from mac.weixin.qq.com, then patch.") }
    static var st_mixed: String { String(localized: "Unrecognized bytes") }
    static var st_mixedSub: String { String(localized: "The bytes at a patch point are neither pristine nor mine — most likely another tool touched them. Reinstall WeChat, then come back.") }

    // 按钮
    static var btn_protect: String { String(localized: "Turn on anti-recall") }
    static var btn_repair: String { String(localized: "Complete the patch") }
    static var btn_restore: String { String(localized: "Restore WeChat") }
    static var btn_recheck: String { String(localized: "Check again") }
    static var btn_reinstall: String { String(localized: "Download WeChat") }
    static var btn_details: String { String(localized: "Details") }
    static var btn_copyReport: String { String(localized: "Copy diagnostics") }
    static var btn_copied: String { String(localized: "Copied") }
    static var btn_quitWeChatAndGo: String { String(localized: "Quit WeChat and continue") }
    static var btn_cancel: String { String(localized: "Cancel") }

    // 流程
    static var flow_wechatRunning: String { String(localized: "WeChat is running") }
    static var flow_wechatRunningBody: String { String(localized: "WeChat's binary can only be modified while it is fully quit — otherwise macOS kills it mid-write and leaves a half-signed bundle.\n\nQuit WeChat now? It will be reopened once the patch is done.") }
    static var flow_working: String { String(localized: "Working…") }
    static var flow_resigning: String { String(localized: "Re-signing WeChat (this takes a while, don't quit)…") }
    static var flow_doneProtect: String { String(localized: "Done. WeChat has been reopened.") }
    static var flow_doneRestore: String { String(localized: "Restored to stock. WeChat's auto-updater is live again.") }
    static var flow_restoreConfirm: String { String(localized: "Restore WeChat to stock?") }
    static var flow_restoreBody: String { String(localized: "Every patch point is written back to its original bytes and the bundle is re-signed. Anti-recall stops working and WeChat's auto-updater comes back.") }

    // 守护
    static var guard_title: String { String(localized: "Re-apply automatically after a WeChat update") }
    static var guard_note: String { String(localized: "Updates can remove patches. Reapply only after full protection previously succeeded, with WeChat closed and no password needed. Otherwise, only notify.") }
    static var guard_launchAtLogin: String { String(localized: "Launch at login") }
    static func notif_repatched(_ build: String) -> String { String(localized: "WeChat updated to \(build); the anti-recall patch has been re-applied automatically.") }
    static func notif_needsYou(_ build: String) -> String { String(localized: "WeChat updated to \(build) and the patch is gone. Open WeChatUnrevoke and click once to put it back.") }

    // 变体
    static var variant_title: String { String(localized: "Anti-recall style") }
    static func variant_onlyNote(_ arch: String) -> String { String(localized: "On this Mac's processor architecture (\(arch)), this WeChat build offers this style only.") }
    static var variant_keeptip: String { String(localized: "Keep the tip (recommended)") }
    static var variant_keeptipNote: String { String(localized: "The message stays and one-to-one chats still show \"X recalled a message\" — you see both what was recalled and that it was. Group chats keep the message but show no tip.") }
    static var variant_silent: String { String(localized: "Silent") }
    static var variant_silentNote: String { String(localized: "The message stays and no recall tip is shown at all.") }

    // 详情
    static var det_build: String { String(localized: "WeChat version") }
    static var det_channel: String { String(localized: "Install channel") }
    static var det_unknown: String { String(localized: "Unknown (not supplied by older engines)") }
    static var det_arch: String { String(localized: "Architecture") }
    static var det_writeAccess: String { String(localized: "Write blockers") }
    static var det_none: String { String(localized: "None") }
    static var det_antiRevoke: String { String(localized: "Anti-recall") }
    static var det_updateBlock: String { String(localized: "Update block") }
    static var det_sip: String { String(localized: "SIP") }
    static var det_signature: String { String(localized: "Signature") }
    static var det_entitlements: String { String(localized: "Entitlements") }
    static var det_admin: String { String(localized: "Engine requests administrator authorization") }
    static var det_yes: String { String(localized: "Yes") }
    static var det_no: String { String(localized: "No") }
    static var det_on: String { String(localized: "Applied") }
    static var det_off: String { String(localized: "Not applied") }
    static var det_weird: String { String(localized: "Unrecognized") }
    static var det_na: String { String(localized: "n/a") }
    static var det_unavailable: String { String(localized: "Not available") }
    static var det_intact: String { String(localized: "Intact") }
    static var det_lost: String { String(localized: "Lost") }

    // 页脚
    static var foot_engine: String { String(localized: "Engine") }
    static var foot_configFresh: String { String(localized: "Patch database up to date") }
    static var foot_configUpdated: String { String(localized: "Patch database updated") }
    static var flow_updatingConfig: String { String(localized: "Updating patch database…") }
    static func err_configRefresh(_ reason: String) -> String { String(localized: "Could not update the patch database, so support for this build may not have arrived yet: \(reason). Check the network connection to raw.githubusercontent.com, then click Check again.") }
}

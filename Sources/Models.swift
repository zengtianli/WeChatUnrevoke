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
        case hostArch, archSupported, writeBlockers
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
// 用一个按系统语言取值的表，而不是 .strings —— 两种语言的句子并排放在同一行，
// 改文案时不可能只改一半（.lproj 分家最常见的病就是一边漏改）。
// =============================================================================

enum L {
    static let zh: Bool = (Locale.preferredLanguages.first ?? "en").hasPrefix("zh")
    static func t(_ zh: String, _ en: String) -> String { L.zh ? zh : en }

    // 错误
    static var err_cliMissing: String { t(
        "App 内少了 wechattweak 引擎 —— 这份 WeChatUnrevoke 没构建完整，请重新下载。",
        "The wechattweak engine is missing from this app bundle — this build is incomplete, please download WeChatUnrevoke again.") }
    static func err_launch(_ m: String) -> String { t("引擎启动失败：\(m)", "Failed to launch the engine: \(m)") }
    static func err_decode(_ m: String, _ raw: String) -> String { t(
        "读不懂引擎的输出（\(m)）。原始输出：\(raw)",
        "Could not parse the engine output (\(m)). Raw: \(raw)") }
    static func err_timeout(_ s: Int) -> String { t(
        "引擎 \(s) 秒没跑完，已经掐掉了。微信包很大时重签名会慢，可以再试一次。",
        "The engine did not finish within \(s)s and was terminated. Re-signing a large WeChat bundle is slow — try again.") }
    static var err_authCanceled: String { t("你取消了授权，什么都没改。", "You canceled the authorization — nothing was changed.") }
    static var err_writePermissionDenied: String { t(
        "微信文件的读写被拒绝；仅凭这条错误不能确定原因。请逐项检查：\n1. 管理员权限：文件属于 root 或当前用户无写权限时，需要在本次操作中完成管理员授权。\n2. 文件权限与锁定：检查报错文件及其目录的所有者、访问权限、ACL 和不可变标记（uchg/schg）；管理员授权不一定能解除锁定。\n3. App 管理：若上述权限正常，到「系统设置 → 隐私与安全性 → App 管理」允许当前 WeChatUnrevoke 修改其他 App，然后完全退出并重开。本项系统授权与管理员授权是两回事。\n签名权限是否完好见详情，与文件写权限分开判断。复制诊断报告时请保留原始引擎日志。",
        "Access to WeChat files was denied; this error alone does not identify the cause. Check each item:\n1. Administrator access: root-owned files or missing user write access require administrator authorization for this operation.\n2. File permissions and locks: check the reported file and its directory for ownership, access permissions, ACLs and immutable flags (uchg/schg). Administrator authorization may not remove a lock.\n3. App Management: if file permissions are correct, allow the current WeChatUnrevoke in System Settings → Privacy & Security → App Management, then quit and reopen it. This system permission is separate from administrator authorization.\nEntitlements are shown in Details and are separate from file write permissions. Keep the original engine log when copying diagnostics.") }
    /// 引擎在写入被拒后给出的原因代码（`Write blocked: <codes>`）→ 对应的恢复办法。
    /// 原因由引擎判定，这里只负责把每个代码翻成一句能照做的话。
    static func err_writeBlocked(_ codes: [String]) -> String {
        let lines = codes.map { code -> String in
            switch code {
            case "needsAdmin": return t(
                "微信文件属于其他用户（通常是 root），当前用户没有写权限。再点一次并在弹出的系统对话框里完成管理员授权。",
                "WeChat's files belong to another user (usually root) and this user cannot write them. Try again and complete the administrator authorization in the system dialog.")
            case "immutable": return t(
                "微信文件被锁定（不可变标记，访达「显示简介」里的「已锁定」）。管理员密码绕不过锁定。先在访达取消「已锁定」，或在终端执行 chflags -R nouchg /Applications/WeChat.app，然后再试。",
                "WeChat's files are locked (immutable flag — \"Locked\" in Finder's Get Info). An administrator password does not bypass a lock. Untick Locked in Finder, or run chflags -R nouchg /Applications/WeChat.app in Terminal, then retry.")
            case "aclDeny": return t(
                "微信文件上有一条拒绝写入的访问控制规则（ACL）。在终端用 ls -le 查看，去掉那条 deny 规则后再试。",
                "An access-control entry (ACL) denies writing to WeChat's files. Inspect it with ls -le in Terminal and remove the deny entry, then retry.")
            case "readOnlyVolume": return t(
                "微信在只读位置（直接从磁盘映像里打开，或被系统隔离转移）。把微信拖进「应用程序」文件夹，再对那一份操作。",
                "WeChat is on a read-only location (opened straight from the disk image, or translocated). Drag WeChat into Applications and use that copy.")
            case "appManagement": return t(
                "文件的所有者、权限、锁定和访问控制都允许写入，但 macOS 仍然拒绝了：多半是缺少「App 管理」授权。到「系统设置 → 隐私与安全性 → App 管理」打开 WeChatUnrevoke（列表里没有就用 + 添加当前这份），完全退出并重开本应用再试。管理员密码不能代替这项授权；保护 App 的安全软件也会造成同样的拒绝。",
                "Owner, permissions, locks and access control all allow the write, yet macOS refused it — most likely the App Management permission is missing. In System Settings → Privacy & Security → App Management, enable WeChatUnrevoke (use + to add this copy if it is not listed), quit and reopen this app, then retry. An administrator password does not replace this permission; security software that protects apps can cause the same refusal.")
            default: return t("引擎报告的写入障碍：\(code)", "Write blocker reported by the engine: \(code)")
            }
        }
        return ([t("没能写入微信文件。原因与办法：", "Could not write WeChat's files. Cause and fix:")] + lines).joined(separator: "\n")
    }
    static func blockerName(_ code: String) -> String {
        switch code {
        case "needsAdmin": return t("需要管理员授权", "Needs administrator authorization")
        case "immutable": return t("文件被锁定", "Files are locked")
        case "aclDeny": return t("访问控制规则拒绝写入", "An ACL denies writing")
        case "readOnlyVolume": return t("只读位置", "Read-only location")
        case "appManagement": return t("缺少 App 管理授权", "App Management permission missing")
        default: return code
        }
    }
    static var err_wechatStillRunning: String { t(
        "微信还没完全退出。它的辅助进程会比主进程多活几秒，等一下再点一次就好。",
        "WeChat has not fully quit yet. Its helper processes linger a few seconds after the main one — wait a moment and try again.") }
    static var err_noWeChat: String { t(
        "在 /Applications 里没找到 WeChat.app。请先从 mac.weixin.qq.com 装上微信。",
        "No WeChat.app in /Applications. Install WeChat from mac.weixin.qq.com first.") }

    // 状态卡
    static var st_protected: String { t("防撤回已生效", "Anti-recall is on") }
    static var st_protectedSub: String { t(
        "微信的自动更新也拦住了，补丁不会被下一次更新悄悄抹掉。",
        "WeChat's auto-updater is blocked too, so the next update can't silently wipe the patch.") }
    static var st_unprotected: String { t("还没打补丁", "Not patched yet") }
    static var st_unprotectedSub: String { t(
        "点下面的按钮，撤回的消息就会留在聊天里。",
        "Hit the button below and recalled messages will stay in your chat.") }
    static var st_partial: String { t("部分保护已生效", "Partially protected") }
    static var st_partialSub: String { t(
        "防撤回和拦截自动更新还差一项没打上，点下面的按钮补上。",
        "One of anti-recall and the update block is still missing. Use the button below to add it.") }
    static var st_antiRevokeOnlySubAppStore: String { t(
        "这是 App Store 版微信，由 App Store 负责更新，没有可拦截的内置更新器。想保住补丁，请在 App Store 设置里关闭自动更新。",
        "This is the App Store edition: the App Store updates it, so there is no in-app updater to block. Turn off App Store automatic updates to keep the patch.") }
    static var st_antiRevokeOnlySubUnavailable: String { t(
        "这个微信版本暂时拦不住自动更新（更新器的补丁点还没收录）。防撤回不受影响；微信更新后补丁会失效，本 app 会提醒你重新开启。",
        "This WeChat build's auto-updater can't be blocked yet (its patch points aren't covered). Anti-recall is unaffected; after a WeChat update the patch is gone and this app will remind you to turn it on again.") }
    static var st_unsupported: String { t("这个微信版本还没收录", "This WeChat build isn't covered yet") }
    static func st_unsupportedSub(_ build: String) -> String { t(
        "补丁库尚未支持 build \(build)。配置会联网更新；如果需要新的引擎规则，请安装新版 WeChatUnrevoke。",
        "The patch configuration does not yet support build \(build). Configuration updates arrive online; new engine rules may require a WeChatUnrevoke update.") }
    static func st_unsupportedArchSub(_ build: String, _ arch: String) -> String { t(
        "补丁库有 build \(build) 的补丁点，但只有另一种处理器架构的；这台 Mac 上微信运行的是 \(arch) 代码，照着打不会有任何效果，所以不提供开启。该架构的补丁点收录后会随配置联网更新。",
        "The patch configuration has build \(build), but only for the other processor architecture. On this Mac WeChat runs \(arch) code, so applying those points would change nothing — the switch is not offered. Points for this architecture arrive with online configuration updates once they are covered.") }
    static var st_broken: String { t("微信的签名权限掉了", "WeChat lost its entitlements") }
    static var st_brokenSub: String { t(
        "曾经有工具用错误的方式重签过它。这种状态下微信在开着 SIP 的机器上根本起不来，只能从 mac.weixin.qq.com 重装一次，再来打补丁。",
        "Some tool re-signed it the wrong way. In this state WeChat won't launch at all on a machine with SIP on — reinstall it from mac.weixin.qq.com, then patch.") }
    static var st_mixed: String { t("字节对不上", "Unrecognized bytes") }
    static var st_mixedSub: String { t(
        "补丁点上的字节既不是原始的、也不是我写的 —— 多半是另一个工具动过。重装微信后再来。",
        "The bytes at a patch point are neither pristine nor mine — most likely another tool touched them. Reinstall WeChat, then come back.") }

    // 按钮
    static var btn_protect: String { t("开启防撤回", "Turn on anti-recall") }
    static var btn_repair: String { t("补齐", "Complete the patch") }
    static var btn_restore: String { t("还原微信", "Restore WeChat") }
    static var btn_recheck: String { t("重新检查", "Check again") }
    static var btn_reinstall: String { t("去下载微信", "Download WeChat") }
    static var btn_details: String { t("详情", "Details") }
    static var btn_copyReport: String { t("复制诊断报告", "Copy diagnostics") }
    static var btn_copied: String { t("已复制", "Copied") }
    static var btn_quitWeChatAndGo: String { t("退出微信并继续", "Quit WeChat and continue") }
    static var btn_cancel: String { t("取消", "Cancel") }

    // 流程
    static var flow_wechatRunning: String { t("微信正在运行", "WeChat is running") }
    static var flow_wechatRunningBody: String { t(
        "改动微信的程序文件必须在它完全退出时进行，否则 macOS 会在中途把它杀掉，留下一个签名残破的微信。\n\n要现在退出微信吗？打完补丁我再帮你打开。",
        "WeChat's binary can only be modified while it is fully quit — otherwise macOS kills it mid-write and leaves a half-signed bundle.\n\nQuit WeChat now? It will be reopened once the patch is done.") }
    static var flow_working: String { t("正在处理…", "Working…") }
    static var flow_resigning: String { t("正在重新签名微信（几十秒，别退出）…", "Re-signing WeChat (this takes a while, don't quit)…") }
    static var flow_doneProtect: String { t("打好了。微信已经重新打开。", "Done. WeChat has been reopened.") }
    static var flow_doneRestore: String { t("已还原成没动过的样子。微信的自动更新也恢复了。", "Restored to stock. WeChat's auto-updater is live again.") }
    static var flow_restoreConfirm: String { t("要把微信还原吗？", "Restore WeChat to stock?") }
    static var flow_restoreBody: String { t(
        "会把所有补丁点写回原始字节并重新签名。防撤回随之失效，微信的自动更新也会恢复。",
        "Every patch point is written back to its original bytes and the bundle is re-signed. Anti-recall stops working and WeChat's auto-updater comes back.") }

    // 守护
    static var guard_title: String { t("微信更新后自动打回补丁", "Re-apply automatically after a WeChat update") }
    static var guard_note: String { t(
        "微信更新可能清除补丁。曾成功开启完整保护、无需密码且微信已退出时，自动重新应用；条件不满足时只发提醒。",
        "Updates can remove patches. Reapply only after full protection previously succeeded, with WeChat closed and no password needed. Otherwise, only notify.") }
    static var guard_launchAtLogin: String { t("开机自动运行", "Launch at login") }
    static func notif_repatched(_ build: String) -> String { t(
        "微信更新到 \(build)，防撤回补丁已经自动打回去了。",
        "WeChat updated to \(build); the anti-recall patch has been re-applied automatically.") }
    static func notif_needsYou(_ build: String) -> String { t(
        "微信更新到 \(build)，补丁被抹掉了。打开 WeChatUnrevoke 点一下就能装回来。",
        "WeChat updated to \(build) and the patch is gone. Open WeChatUnrevoke and click once to put it back.") }

    // 变体
    static var variant_title: String { t("防撤回方式", "Anti-recall style") }
    static var variant_keeptip: String { t("保留提示（推荐）", "Keep the tip (recommended)") }
    static var variant_keeptipNote: String { t(
        "消息留着，私聊里仍然显示「对方撤回了一条消息」——你知道对方撤了什么，也知道对方撤过。群聊目前只保留消息、不出提示。",
        "The message stays and one-to-one chats still show \"X recalled a message\" — you see both what was recalled and that it was. Group chats keep the message but show no tip.") }
    static var variant_silent: String { t("静默", "Silent") }
    static var variant_silentNote: String { t(
        "消息留着，完全不显示撤回提示，对方那边也看不出你装了什么。",
        "The message stays and no recall tip is shown at all.") }

    // 详情
    static var det_build: String { t("微信版本", "WeChat version") }
    static var det_channel: String { t("安装渠道", "Install channel") }
    static var det_unknown: String { t("未知（旧引擎未提供）", "Unknown (not supplied by older engines)") }
    static var det_arch: String { t("处理器架构", "Architecture") }
    static var det_writeAccess: String { t("写入障碍", "Write blockers") }
    static var det_none: String { t("无", "None") }
    static var det_antiRevoke: String { t("防撤回", "Anti-recall") }
    static var det_updateBlock: String { t("拦截自动更新", "Update block") }
    static var det_sip: String { t("系统完整性保护", "SIP") }
    static var det_signature: String { t("签名", "Signature") }
    static var det_entitlements: String { t("签名权限", "Entitlements") }
    static var det_admin: String { t("引擎请求管理员授权", "Engine requests administrator authorization") }
    static var det_yes: String { t("是", "Yes") }
    static var det_no: String { t("否", "No") }
    static var det_on: String { t("已生效", "Applied") }
    static var det_off: String { t("未打", "Not applied") }
    static var det_weird: String { t("对不上", "Unrecognized") }
    static var det_na: String { t("不适用", "n/a") }
    static var det_unavailable: String { t("暂不支持", "Not available") }
    static var det_intact: String { t("完整", "Intact") }
    static var det_lost: String { t("已丢失", "Lost") }

    // 页脚
    static var foot_engine: String { t("引擎", "Engine") }
    static var foot_configFresh: String { t("补丁库已是最新", "Patch database up to date") }
    static var foot_configUpdated: String { t("补丁库已更新", "Patch database updated") }
}

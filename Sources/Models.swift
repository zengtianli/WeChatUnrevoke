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
        /// 只装了一半
        case partial
        /// 都没装，且没有任何阻碍
        case unprotected
    }

    let overall: Overall
    let build: String?
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
        case overall, build, appPath, configKnown, configTargets, sip, running, writable
        case signature, entitlementsOk, entitlementKeyCount
        case antiRevokeSilent, antiRevokeKeeptip, updateBlock, updateSource, verdict, nextCommand
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        overall = try c.decode(Overall.self, forKey: .overall)
        build = try c.decodeIfPresent(String.self, forKey: .build)
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
        "App 内少了 wechattweak 引擎 —— 这份 Unrevoke 没构建完整，请重新下载。",
        "The wechattweak engine is missing from this app bundle — this build is incomplete, please download Unrevoke again.") }
    static func err_launch(_ m: String) -> String { t("引擎启动失败：\(m)", "Failed to launch the engine: \(m)") }
    static func err_decode(_ m: String, _ raw: String) -> String { t(
        "读不懂引擎的输出（\(m)）。原始输出：\(raw)",
        "Could not parse the engine output (\(m)). Raw: \(raw)") }
    static func err_timeout(_ s: Int) -> String { t(
        "引擎 \(s) 秒没跑完，已经掐掉了。微信包很大时重签名会慢，可以再试一次。",
        "The engine did not finish within \(s)s and was terminated. Re-signing a large WeChat bundle is slow — try again.") }
    static var err_authCanceled: String { t("你取消了授权，什么都没改。", "You canceled the authorization — nothing was changed.") }
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
    static var st_partial: String { t("只装了一半", "Half applied") }
    static var st_partialSub: String { t(
        "防撤回和「拦住自动更新」这两件事没配齐 —— 缺了后者，微信下次更新会把补丁抹掉。",
        "Anti-recall and the update block are not both in place. Without the latter, WeChat's next update wipes the patch.") }
    static var st_unsupported: String { t("这个微信版本还没收录", "This WeChat build isn't covered yet") }
    static func st_unsupportedSub(_ build: String) -> String { t(
        "build \(build) 的补丁点还没找出来。新版本发布后我会补进 config.json，Unrevoke 会自己拉到，不用更新 app。",
        "The patch points for build \(build) haven't been located yet. They get appended to config.json after each release and Unrevoke picks them up on its own — no app update needed.") }
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
        "微信整包替换式的更新会把补丁抹掉（已经发生过四次）。开着这项，Unrevoke 发现补丁没了就自己打回去；需要输密码或微信正开着时，只提醒不动手。",
        "A WeChat update replaces the whole bundle and wipes the patch — that has happened four times. With this on, Unrevoke re-applies it the moment it notices. If a password is needed or WeChat is open, it only notifies.") }
    static var guard_launchAtLogin: String { t("开机自动运行", "Launch at login") }
    static func notif_repatched(_ build: String) -> String { t(
        "微信更新到 \(build)，防撤回补丁已经自动打回去了。",
        "WeChat updated to \(build); the anti-recall patch has been re-applied automatically.") }
    static func notif_needsYou(_ build: String) -> String { t(
        "微信更新到 \(build)，补丁被抹掉了。打开 Unrevoke 点一下就能装回来。",
        "WeChat updated to \(build) and the patch is gone. Open Unrevoke and click once to put it back.") }

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
    static var det_build: String { t("微信版本", "WeChat build") }
    static var det_antiRevoke: String { t("防撤回", "Anti-recall") }
    static var det_updateBlock: String { t("拦截自动更新", "Update block") }
    static var det_sip: String { t("系统完整性保护", "SIP") }
    static var det_signature: String { t("签名", "Signature") }
    static var det_entitlements: String { t("签名权限", "Entitlements") }
    static var det_admin: String { t("需要管理员密码", "Needs an admin password") }
    static var det_yes: String { t("是", "Yes") }
    static var det_no: String { t("否", "No") }
    static var det_on: String { t("已生效", "Applied") }
    static var det_off: String { t("未打", "Not applied") }
    static var det_weird: String { t("对不上", "Unrecognized") }
    static var det_na: String { t("不适用", "n/a") }
    static var det_intact: String { t("完整", "Intact") }
    static var det_lost: String { t("已丢失", "Lost") }

    // 页脚
    static var foot_engine: String { t("引擎", "Engine") }
    static var foot_configFresh: String { t("补丁库已是最新", "Patch database up to date") }
    static var foot_configUpdated: String { t("补丁库已更新", "Patch database updated") }
}

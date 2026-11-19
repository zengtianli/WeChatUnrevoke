#!/usr/bin/env python3
"""WeChatUnrevoke 在“别人的 Mac”上从装到用走一遍（交得出去，2026-11-18；共享 clean_env.py 原生模式的一份小配置）。

跑法（先构建发行同款的包，再走一遍）：
    cd ~/Apps/unrevoke
    INSTALL_APP=0 CONFIG=Release UNREVOKE_OUTPUT_APP="$PWD/build/clean-env/WeChatUnrevoke.app" bash build.sh
    python3 tests/clean_env.py [--app 路径] [--keep]
    （等价：python3 ~/Dev/tools/dev/lib/tools/macapp/clean_env.py tests/clean_env.py）
记录：build/clean-env/report.json（有一项不对退出码 1）。

为什么不是 build/candidate：候选包沿用本机已装的引擎（sudo 免密规则按摘要钉着它），别人下载的发行包里的引擎是按
引擎源码现编的。这里走的就是别人拿到的那一份：本仓当前源码 + 引擎仓当前源码（build.sh 不带 UNREVOKE_PREBUILT_ENGINE）。
记录里 notes.package 写下被测包的版本、build、引擎摘要和两个仓的提交。

包先拷进临时目录、只跑拷贝；空家目录（HOME 与 CFFIXED_USER_HOME）、系统 PATH、不带本人的环境变量；每步套沙箱：读写本人
家目录、cfprefsd、钥匙串、TCC 授权框、登录项、Apple Event、窗口服务器一律挡（拦到读写本人家目录即判失败）。另外：
  · protect：本人这台的真实微信 /Applications/WeChat.app 与已装的 /Applications/WeChatUnrevoke.app 沙箱里写不进，
    拦到即判 protected.untouched 失败；走完再核一遍真实微信关键文件的摘要（real_wechat.unchanged）。
  · 补丁只打在临时目录里的微信副本上（APFS 克隆，放隐藏目录 .wechat.noindex，系统不会把它登记进 LaunchServices）。
  · WECHATTWEAK_KEEP_PRIVACY_GRANTS=1：副本和真实微信同一个包名，引擎换签名身份时会去清“录屏/麦克风/摄像头”授权，
    清的是真实微信的那几条；这里不让它清（沙箱也挡着 tccd）。
  · UNREVOKE_DEFAULTS_DOMAIN={test_domain}：命令行的偏好写进一次性偏好域，跨步保留、跑完删掉（沙箱挡 cfprefsd，
    不设的话写入不跨步）。
依次：
  1. 第一次打开、什么都没设：版本；防撤回方式默认 keeptip、自动重打默认开、目标是 /Applications/WeChat.app；补丁库用的是
     随包那份；没有写入记录；没有第二个微信；没开 iCloud 记住配置。
  2. 联网：补丁库联网更新（读到就写进她自己的 Application Support，读不到要给人话原因、随包那份照用），检查更新
     （读 GitHub Releases）；两样各在断网的一步里再走一次，读不到的那条路每次都走到、几秒内返回。
  3. 体检她装的微信（只读）：引擎能认出版本、给出判决；补丁库认识哪些版本。
  4. 在微信副本上：先还原成原样（不加 --yes 被拒）→ 开启防撤回（默认 keeptip）→ 再开一次是空操作 → 体检 protected →
     还原 → 设置里改成 silent（存进偏好，下一条命令读到）→ 计划与开启都用上存下的方式 → 体检 silent 生效 → 还原 →
     体检 unprotected，签名权限完好；走完副本的签名 codesign 严格校验通过。
     偏好只写一次：挡了 cfprefsd 以后 CF 直写只在偏好文件还不存在时落得了盘，后面的步再改不落盘（共享原版文件头有实测）。
开机自动运行、管理员授权框、通知授权、窗口本身要真人与系统，不在这里（窗口另有 Chapter native_ui 离屏验收）。
"""
from __future__ import annotations

import hashlib
import json
import plistlib
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SHARED = Path.home() / "Dev/tools/dev/lib/tools/macapp"
REAL_WECHAT = Path("/Applications/WeChat.app")
CLI = "{bin}/unrevoke"
SUPPORT = "{home}/Library/Application Support/Unrevoke"
VERDICTS = ["protected", "antiRevokeOnly", "unprotected", "partial", "unsupportedBuild", "brokenBundle", "mixed"]


def cli(name, *args, expect=None, exit=0, **extra):
    return {"name": name, "run": [CLI, *args], "expect": expect or {"ok": True}, "exit": exit, **extra}


CONFIG = {
    "name": "unrevoke",
    "app": "build/clean-env/WeChatUnrevoke.app",
    "env": {"UNREVOKE_DEFAULTS_DOMAIN": "{test_domain}", "WECHATTWEAK_KEEP_PRIVACY_GRANTS": "1"},
    "protect": [str(REAL_WECHAT), "/Applications/WeChatUnrevoke.app"],
    "commands": [
        # —— 1. 第一次打开，什么都没设 ——
        cli("first_run.version", "version", "--json", expect={"ok": True, "version": {"$truthy": True}, "build": {"$truthy": True}},
            save="version"),
        cli("first_run.default_settings", "settings", "--json",
            expect={"ok": True, "domain": "{test_domain}", "variant": "keeptip", "variant_saved": False, "auto_repatch": True,
                    "auto_repatch_saved": False, "ever_protected": False, "last_build": None,
                    "wechat_path": str(REAL_WECHAT), "wechat_path_overridden": False}),
        cli("first_run.bundled_patch_library", "config", "--json",
            expect={"ok": True, "source": "bundled", "entries": {"$gt": 0}, "cache.exists": False,
                    "cache.path": SUPPORT + "/config.json",
                    "path": {"$endswith": "/.app.noindex/WeChatUnrevoke.app/Contents/Resources/config.json"}}),
        cli("first_run.no_write_history", "logs", "--json", expect={"ok": True, "exists": False}),
        cli("first_run.no_second_wechat", "second", "status", "--json",
            expect={"ok": True, "exists": False, "path": "{home}/Applications/WeChat2.app", "main_path": str(REAL_WECHAT)}),
        {"name": "first_run.app_config_status", "run": ["{exe}", "config", "status", "--json"],
         "expect": {"ok": True, "keys": [], "sync_enabled": False}},

        # —— 2. 联网：补丁库与检查更新；exit 不管（读到 0，读不到 1），steps 里按结果判 ——
        cli("network.patch_library_refresh_ran", "config", "refresh", "--json", exit=[0, 1], timeout=60, save="refresh",
            expect={"action": "config refresh"}),
        cli("network.patch_library_offline", "config", "refresh", "--json", exit=1, timeout=45, offline=True, save="refresh_offline",
            expect={"ok": False, "result": "failed", "message": {"$contains": "联网失败"}}),
        cli("network.update_check_ran", "update", "check", "--json", exit=[0, 1], timeout=60, save="update",
            expect={"command": "update check", "source.repository": "zengtianli/WeChatUnrevoke"}),
        cli("network.update_check_offline", "update", "check", "--json", exit=1, timeout=45, offline=True,
            expect={"ok": False, "error.code": "check_incomplete", "error.message": {"$truthy": True}}),

        # —— 3. 体检她装的微信（只读；protect 挡着写）——
        cli("her_wechat.doctor", "doctor", "--json", timeout=90, save="her_doctor",
            expect={"ok": True, "app_path": str(REAL_WECHAT), "is_main_wechat": True, "overall": {"$in": VERDICTS},
                    "build": {"$truthy": True}}),
        cli("her_wechat.versions", "versions", "--json",
            expect={"ok": True, "app_path": str(REAL_WECHAT), "current_build": {"$truthy": True}, "supported_count": {"$gt": 0}}),
    ],
    "absent": ["{home}/Personal", "{home}/.personal_env", "{home}/Applications/WeChat2.app"],
}


def fingerprint(app: Path) -> dict:
    """真实微信的几处关键文件（inode、大小、修改时间、摘要）；只读。"""
    out = {}
    for rel in ("Contents/Info.plist", "Contents/MacOS/WeChat", "Contents/Resources/wechat.dylib",
                "Contents/_CodeSignature/CodeResources"):
        p = app / rel
        if not p.is_file():
            out[rel] = None
            continue
        st = p.stat()
        digest = hashlib.sha256()
        with p.open("rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                digest.update(chunk)
        out[rel] = [st.st_ino, st.st_size, st.st_mtime_ns, digest.hexdigest()]
    return out


def git_head(repo: Path) -> str | None:
    r = subprocess.run(["git", "-C", str(repo), "rev-parse", "--short", "HEAD"], capture_output=True, text=True)
    if r.returncode:
        return None
    dirty = subprocess.run(["git", "-C", str(repo), "status", "--porcelain", "--untracked-files=no"],
                           capture_output=True, text=True).stdout.strip()
    return r.stdout.strip() + ("+dirty" if dirty else "")


def prepare(ce):
    """她这台 Mac 上装着的微信：真实微信做一份 APFS 克隆放隐藏目录（只读来源），补丁只打在克隆上。"""
    ce.notes["real_wechat_before"] = ce.vars["real_before"] = fingerprint(REAL_WECHAT)
    holder = Path(ce.work) / ".wechat.noindex"
    holder.mkdir()
    copy = holder / "WeChat.app"
    r = subprocess.run(["/bin/cp", "-cR", str(REAL_WECHAT), str(copy)], capture_output=True, text=True, timeout=300)
    cloned = r.returncode == 0 and (copy / "Contents/MacOS/WeChat").is_file() and \
        (copy / "Contents/MacOS/WeChat").stat().st_ino != (REAL_WECHAT / "Contents/MacOS/WeChat").stat().st_ino
    ce.check("copy.cloned", cloned, r.stderr.strip()[-300:] if not cloned else str(copy))
    ce.vars["wechat"] = copy


def patch_flow(ce):
    w = str(ce.vars["wechat"])
    run = ce.run
    run(cli("copy.doctor_before", "doctor", "-a", w, "--json", timeout=90,
            expect={"ok": True, "is_main_wechat": True, "running": False, "overall": {"$in": VERDICTS}}))
    run(cli("copy.restore_needs_yes", "restore", "-a", w, "--json", exit=2,
            expect={"ok": False, "reason": "confirmation_required"}))
    run(cli("copy.restore_to_stock", "restore", "-a", w, "--yes", "--json", timeout=600,
            expect={"ok": True, "result": {"$in": ["restored", "already_stock"]}, "gui_target": False}))
    run(cli("copy.stock_verified", "doctor", "-a", w, "--json", timeout=90,
            expect={"ok": True, "overall": "unprotected", "entitlements_ok": True}))
    # 开启防撤回：什么都没设，用默认的 keeptip；不要管理员（副本在她自己能写的地方）
    run(cli("copy.patch_default", "patch", "-a", w, "--json", timeout=600,
            expect={"ok": True, "result": "patched", "variant": "keeptip", "variant_source": "default", "via": "direct",
                    "after.overall": {"$in": ["protected", "antiRevokeOnly"]}, "after.entitlements_ok": True}))
    run(cli("copy.patch_again_noop", "patch", "-a", w, "--json", timeout=90,
            expect={"ok": True, "result": "already_protected"}))
    run(cli("copy.keeptip_verified", "doctor", "-a", w, "--json", timeout=90,
            expect={"ok": True, "overall": "protected", "anti_revoke_keeptip": "patched", "entitlements_ok": True}))
    run(cli("copy.restore_keeptip", "restore", "-a", w, "--yes", "--json", timeout=600,
            expect={"ok": True, "result": "restored", "after.overall": "unprotected", "after.entitlements_ok": True}))
    # 设置里改防撤回方式：存进偏好，下一条命令读到，计划与开启都用它
    run(cli("settings.set_variant_silent", "settings", "set", "variant", "silent", "--json",
            expect={"ok": True, "value": "silent", "changed": True}))
    run(cli("settings.kept", "settings", "--json", expect={"ok": True, "variant": "silent", "variant_saved": True}))
    run(cli("copy.patch_plan_uses_saved_variant", "patch", "-a", w, "--dry-run", "--json",
            expect={"ok": True, "result": "would_patch", "variant": "silent", "variant_source": "saved", "via": "direct",
                    "needs_admin": False}))
    run(cli("copy.patch_saved_variant", "patch", "-a", w, "--json", timeout=600,
            expect={"ok": True, "result": "patched", "variant": "silent", "variant_source": "saved",
                    "after.overall": {"$in": ["protected", "antiRevokeOnly"]}, "after.entitlements_ok": True}))
    run(cli("copy.silent_verified", "doctor", "-a", w, "--json", timeout=90,
            expect={"ok": True, "overall": "protected", "anti_revoke_silent": "patched", "entitlements_ok": True}))
    # 还原
    run(cli("copy.restore", "restore", "-a", w, "--yes", "--json", timeout=600,
            expect={"ok": True, "result": "restored", "after.overall": "unprotected", "after.entitlements_ok": True}))
    run(cli("copy.restored_verified", "doctor", "-a", w, "--json", timeout=90,
            expect={"ok": True, "overall": "unprotected", "entitlements_ok": True}))


def check_network(ce):
    refresh = ce.vars.get("refresh") or {}
    support = Path(str(ce.home)) / "Library/Application Support/Unrevoke/config.json"
    if refresh.get("ok"):
        ok = refresh.get("result") in ("updated", "refreshed", "unchanged") and refresh.get("http_status") == 200 \
            and support.is_file() and refresh.get("path") == str(support)
        ce.check("network.patch_library_refresh", ok, json.dumps({k: refresh.get(k) for k in ("result", "http_status", "path")},
                                                                ensure_ascii=False))
        got = ce.run(cli("network.patch_library_from_cache", "config", "--json",
                         expect={"ok": True, "source": "cache", "path": str(support)}))
        ce.check("network.cache_in_her_support_dir", got.get("cache", {}).get("exists") is True, str(support))
    else:
        # 读不到（她的网络打不开 GitHub）：要给一句人话原因，缓存不动，随包那份照用
        message = str(refresh.get("message") or "")
        ok = refresh.get("result") in ("failed", "rejected") and len(message) >= 4 and "Traceback" not in message
        ce.check("network.patch_library_unreachable_says_why", ok, message[:300])
        ce.run(cli("network.patch_library_still_bundled", "config", "--json", expect={"ok": True, "source": "bundled"}))
    offline = ce.vars.get("refresh_offline") or {}
    ce.check("network.offline_keeps_cache", offline.get("ok") is False and "联网失败" in str(offline.get("message")),
             str(offline.get("message"))[:300])

    update = ce.vars.get("update") or {}
    if update.get("ok"):
        ok = update.get("state") in ("up_to_date", "update_available", "ahead_of_channel") and bool(update.get("message")) \
            and bool((update.get("latest") or {}).get("version"))
    else:
        reason = str((update.get("error") or {}).get("message") or "").split("：", 1)[-1].strip()
        ok = (update.get("error") or {}).get("code") == "check_incomplete" and len(reason) >= 4
    ce.check("network.update_check", ok, json.dumps({k: update.get(k) for k in ("ok", "state", "message", "error")},
                                                   ensure_ascii=False, default=str)[:600])
    ce.notes["network"] = {"patch_library": {k: refresh.get(k) for k in ("ok", "result", "message")},
                           "update": {k: update.get(k) for k in ("ok", "state", "message")}}


def steps(ce):
    check_network(ce)
    her = ce.vars.get("her_doctor") or {}
    ce.notes["her_wechat"] = {k: her.get(k) for k in ("short_version", "build", "overall", "config_known", "running")}
    if ce.checks.get("copy.cloned"):
        patch_flow(ce)
        seal = subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(ce.vars["wechat"])],
                              capture_output=True, text=True, timeout=300)
        ce.check("copy.signature_valid_after_restore", seal.returncode == 0, (seal.stderr.strip().splitlines() or [""])[-1][:200])
        lsregister = ("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
        subprocess.run([lsregister, "-u", str(ce.vars["wechat"])], capture_output=True, timeout=30)  # 万一被登记，删前注销
    after = fingerprint(REAL_WECHAT)
    ce.check("real_wechat.unchanged", after == ce.vars["real_before"],
             "" if after == ce.vars["real_before"] else json.dumps({"before": ce.vars["real_before"], "after": after})[:1200])

    app = Path(str(ce.app))
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    engine = app / "Contents/Resources/wechattweak"
    ce.notes["package"] = {
        "source": str(ce.source), "version": info.get("CFBundleShortVersionString"), "build": info.get("CFBundleVersion"),
        "engine_sha256": hashlib.sha256(engine.read_bytes()).hexdigest() if engine.is_file() else None,
        "unrevoke_commit": git_head(REPO), "engine_commit": git_head(REPO.parent / "vendor/WeChatTweak")}


if __name__ == "__main__":
    sys.path.insert(0, str(SHARED))
    import clean_env
    sys.exit(clean_env.main([__file__, *sys.argv[1:]]))

#!/usr/bin/env python3
"""Exercise the current AppModel and real engine on a disposable WeChat copy."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

from _common import BUILD, ROOT, detail, run, xcode_env


class Unavailable(Exception):
    pass


def fingerprint(app):
    """Guard the installed inputs against accidental writes; no account data read."""
    result = {}
    for relative in ("Contents/Info.plist", "Contents/MacOS/WeChat",
                     "Contents/Resources/wechat.dylib", "Contents/_CodeSignature/CodeResources"):
        path = app / relative
        if not path.is_file():
            result[relative] = None
            continue
        st = path.stat()
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        result[relative] = (st.st_ino, st.st_size, st.st_mtime_ns, st.st_mode, digest.hexdigest())
    return result


def clean(message):
    return str(message).replace(str(ROOT), "<repo>").replace(str(Path.home()), "~")


def main():
    scratch = None
    source = Path(os.environ.get("UNREVOKE_ACCEPT_WECHAT", "/Applications/WeChat.app")).resolve()
    before = None
    code = 0
    fields = {}
    summary = ""
    try:
        engine = Path(os.environ.get("UNREVOKE_ACCEPT_ENGINE",
                      "/Applications/WeChatUnrevoke.app/Contents/Resources/wechattweak")).resolve()
        config = Path(os.environ.get("UNREVOKE_ACCEPT_CONFIG", str(engine.parent / "config.json"))).resolve()
        if not (source / "Contents/MacOS/WeChat").is_file():
            raise Unavailable("需要已安装的真实 WeChat.app，或用 UNREVOKE_ACCEPT_WECHAT 指定只读来源。")
        if not engine.is_file() or not os.access(engine, os.X_OK) or not config.is_file():
            raise Unavailable("缺少已构建的 wechattweak/config.json；用 UNREVOKE_ACCEPT_ENGINE 和 UNREVOKE_ACCEPT_CONFIG 指定现有文件。")
        env = xcode_env()
        before = fingerprint(source)
        scratch = Path(tempfile.mkdtemp(prefix="functionality-", dir=BUILD))
        app = scratch / "UnrevokeFunctionality.app"
        macos, resources = app / "Contents/MacOS", app / "Contents/Resources"
        macos.mkdir(parents=True)
        resources.mkdir()
        identifier = "io.github.zengtianli.unrevoke.accept.functionality." + scratch.name.split("-", 1)[1]
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": identifier,
            "CFBundleExecutable": "UnrevokeFunctionality",
            "CFBundlePackageType": "APPL",
            "LSUIElement": True,
        }))
        shutil.copy2(engine, resources / "wechattweak")
        shutil.copy2(config, resources / "config.json")
        executable = macos / "UnrevokeFunctionality"
        run(["xcrun", "swiftc", "-parse-as-library", "Sources/Models.swift",
             "Sources/Engine.swift", "Sources/ViewModel.swift", "tests/FunctionalityAcceptance.swift",
             "-o", str(executable)], env=env)
        copy = scratch / "WeChat.app"
        # APFS clone: separate inodes and copy-on-write data, never hard links.
        run(["/bin/cp", "-cR", str(source), str(copy)], timeout=180)
        if (copy / "Contents/MacOS/WeChat").stat().st_ino == (source / "Contents/MacOS/WeChat").stat().st_ino:
            raise RuntimeError("副本没有独立 inode，已拒绝写入。")
        report = scratch / "result.json"
        completed = subprocess.run([str(executable), str(copy), str(report)], cwd=ROOT,
                                   env=env, text=True, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, timeout=480)
        if completed.returncode:
            message = clean(completed.stdout.strip())
            if completed.returncode == 78:
                raise Unavailable(message)
            raise RuntimeError(message or f"验收进程退出 {completed.returncode}")
        fields = json.loads(report.read_text())
        fields["engine_sha256"] = hashlib.sha256(engine.read_bytes()).hexdigest()
        fields["scope"] = "当前 AppModel → Engine → 已构建的真实 wechattweak；真实微信独立副本；不启动微信或登录聊天"
        summary = "PASS: 真实微信副本经 AppModel 完成还原基线、默认防撤回补丁和再次还原；独立 doctor 核验通过。"
    except Unavailable as error:
        code, summary = 78, "BLOCKED: " + clean(error)
    except subprocess.CalledProcessError as error:
        code, summary = 1, "FAIL: " + clean(error.stdout or str(error))
    except (OSError, RuntimeError, subprocess.TimeoutExpired, ValueError) as error:
        code, summary = 1, "FAIL: " + clean(error)
    finally:
        if before is not None:
            try:
                if fingerprint(source) != before:
                    code, summary = 1, "FAIL: 来源微信关键文件在验收期间改变，不能证明来源未受影响。"
                else:
                    fields["source_key_files_unchanged"] = True
            except OSError:
                code, summary = 1, "FAIL: 无法复核来源微信关键文件。"
        if scratch is not None:
            shutil.rmtree(scratch, ignore_errors=True)
    detail("functionality", summary, **fields)
    return code


if __name__ == "__main__":
    sys.exit(main())

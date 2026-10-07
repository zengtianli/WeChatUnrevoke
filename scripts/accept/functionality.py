#!/usr/bin/env python3
"""Exercise the current AppModel and real engine on a disposable WeChat copy."""
from __future__ import annotations

import hashlib
import codecs
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import selectors
import subprocess
import sys
import tempfile
import time

from _common import BUILD, ROOT, detail, run, xcode_env


class Unavailable(Exception):
    pass


# Chapter stops the whole acceptor at 600 s; leave room for the compile, the clone and the installed-export part.
HARNESS_TIMEOUT = 480


def children(pid):
    table = subprocess.run(["/bin/ps", "-axo", "pid=,ppid="], text=True, stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL).stdout
    return [int(parts[0]) for parts in map(str.split, table.splitlines())
            if len(parts) == 2 and int(parts[1]) == pid]


def kill_tree(root):
    """Stop each process before listing its children (a stopped parent spawns nothing), then kill them all."""
    stopped, pending = [], [root]
    while pending:
        pid = pending.pop()
        try:
            os.kill(pid, signal.SIGSTOP)
        except ProcessLookupError:
            continue
        stopped.append(pid)
        pending.extend(children(pid))
    for pid in stopped:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def run_harness(args, *, env, timeout):
    """Run the harness; on timeout stop it together with the engine and codesign processes it started.

    subprocess.run(timeout=) kills only the harness: the engine kept re-signing the copy after the
    verdict, and the read of the shared stdout pipe blocked until it finished. Chapter's own kill
    covers the whole process group, so this stays in the caller's group and kills the tree itself."""
    proc = subprocess.Popen(args, cwd=ROOT, env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    chunks = []
    decoder = codecs.getincrementaldecoder("utf-8")("replace")
    deadline = time.monotonic() + timeout
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(proc.stdout, selectors.EVENT_READ)
            while selector.get_map():
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise subprocess.TimeoutExpired(args, timeout)
                for key, _ in selector.select(min(.2, remaining)):
                    chunk = os.read(key.fd, 65536)
                    if not chunk:
                        selector.unregister(key.fileobj)
                        continue
                    chunks.append(chunk)
                    sys.stdout.write(decoder.decode(chunk))
                    sys.stdout.flush()
            sys.stdout.write(decoder.decode(b"", final=True))
            sys.stdout.flush()
        proc.wait(timeout=max(0, deadline - time.monotonic()))
    except BaseException:
        kill_tree(proc.pid)
        proc.wait()
        raise
    finally:
        proc.stdout.close()
    return subprocess.CompletedProcess(args, proc.returncode, b"".join(chunks).decode("utf-8", "replace"))


def load_note():
    """The engine re-signs a 1+ GB bundle three times; on a saturated machine that alone exceeds the budget."""
    try:
        load = os.getloadavg()[0]
    except OSError:
        return ""
    return f"（1 分钟负载 {load:.0f}，{os.cpu_count()} 核）"


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
        print("Functionality: compiling the actual AppModel/Engine harness.", flush=True)
        run(["xcrun", "swiftc", "-parse-as-library", "Sources/Models.swift",
             "Sources/Engine.swift", "Sources/WriteHistory.swift", "Sources/ViewModel.swift", "tests/FunctionalityAcceptance.swift",
             "-o", str(executable)], env=env)
        copy = scratch / "WeChat.app"
        # APFS clone: separate inodes and copy-on-write data, never hard links.
        run(["/bin/cp", "-cR", str(source), str(copy)], timeout=180)
        if (copy / "Contents/MacOS/WeChat").stat().st_ino == (source / "Contents/MacOS/WeChat").stat().st_ino:
            raise RuntimeError("副本没有独立 inode，已拒绝写入。")
        print("Functionality: isolated clone prepared; checking patch and restore.", flush=True)
        report = scratch / "result.json"
        completed = run_harness([str(executable), str(copy), str(report)], env=env, timeout=HARNESS_TIMEOUT)
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
    except subprocess.TimeoutExpired as error:
        code, summary = 1, f"FAIL: 验收进程超过 {error.timeout:.0f} 秒，已连同引擎一起终止{load_note()}"
    except (OSError, RuntimeError, ValueError) as error:
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

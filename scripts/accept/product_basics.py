#!/usr/bin/env python3
"""Real product basics on the installed app, or an explicitly bound candidate.

Only disposable bundles, preference domains, update feeds and cloud directories
are written. The shipped app's own controls/CLI and shared installer execute.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
PRODUCT = "io.github.zengtianli.unrevoke"
FEATURES = ("settings", "shortcuts", "icloud", "updates")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def owner_state():
    """Observe digests, never export production preference values into evidence."""
    result = {}
    done = subprocess.run(["/usr/bin/defaults", "export", PRODUCT, "-"], capture_output=True)
    result["preferences"] = sha_bytes(plistlib.dumps(plistlib.loads(done.stdout), sort_keys=True)) if done.returncode == 0 else None
    for label, directory in (("configuration", Path.home() / "Library/Application Support/TianliApps/Configuration" / PRODUCT),
                             ("installed", Path("/Applications/WeChatUnrevoke.app"))):
        result[label] = {str(p.relative_to(directory)): sha(p) for p in directory.rglob("*") if p.is_file() and not p.is_symlink()}
    return result


def sha_bytes(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=os.environ.get("UNREVOKE_BASICS_APP", "/Applications/WeChatUnrevoke.app"))
    parser.add_argument("--receipt", type=Path, default=os.environ.get("UNREVOKE_BASICS_RECEIPT", str(ROOT / "perf/build-receipt.json")))
    args = parser.parse_args()
    app, receipt_path = args.app.resolve(), args.receipt.resolve()
    spec = json.loads(os.environ["SOP_PRODUCT_BASICS_SPEC"])
    assert os.environ["SOP_APP_ID"] == spec["app_id"] == "unrevoke-mac"
    out = Path(os.environ["SOP_OUT_DIR"]).resolve()
    assert out.is_relative_to(ROOT / "perf/acceptance")
    run = out / ("product-basics-" + uuid.uuid4().hex)
    run.mkdir(parents=True)
    checks, cases = {}, []
    before = owner_state()
    error = None
    suites = []
    identity = {}
    scope = "installed" if app == Path("/Applications/WeChatUnrevoke.app") else "candidate-not-installed"

    def check(name, condition):
        checks[name] = bool(condition)

    def command(words, predicate, code=0, environment=None):
        done = subprocess.run([str(executable), *words, "--json"], env=environment or env,
                              cwd=ROOT, capture_output=True, text=True, timeout=90)
        body = json.loads(done.stdout)
        passed = done.returncode == code and bool(predicate(body))
        cases.append({"argv": words, "exit": done.returncode, "passed": passed, "response": body, "stderr": done.stderr})
        if not passed:
            raise AssertionError(f"Product command failed: {words}: exit={done.returncode}, {body}")
        return body

    try:
        sys.path.insert(0, str(Path.home() / "Apps/chapter/engine"))
        import app_sop
        registered = app_sop.load_apps("unrevoke-mac")[0]
        valid, reason = app_sop.verify_build_receipt(registered, app, receipt_path=receipt_path)
        assert valid, reason
        receipt = json.loads(receipt_path.read_text())
        artifact = receipt["artifact"]
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        identity = {"scope": scope, "bundle_id": info["CFBundleIdentifier"],
                    "version": info["CFBundleShortVersionString"], "build": str(info["CFBundleVersion"]),
                    "executable_sha256": sha(app / artifact["executable"]),
                    "receipt_sha256": sha(receipt_path), "source_sha256": receipt["source"]["sha256"]}
        assert identity["bundle_id"] == PRODUCT and identity["executable_sha256"] == artifact["sha256"]
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True, capture_output=True)
        suite = PRODUCT + ".accept." + uuid.uuid4().hex
        suites.append(suite)
        clone = run / "Applications/WeChatUnrevoke.app"
        shutil.copytree(app, clone, symlinks=True)
        assert sha(clone / artifact["executable"]) == artifact["sha256"]
        info.update(CFBundleIdentifier=suite, LSUIElement=True)
        (clone / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        subprocess.run(["codesign", "--force", "--sign", "-", str(clone)], check=True, capture_output=True)
        executable = clone / artifact["executable"]
        env = {k: v for k, v in os.environ.items() if not k.startswith(("APP_LIFECYCLE_", "UNREVOKE_LIFECYCLE_", "UNREVOKE_TEST_", "UNREVOKE_BASICS_"))}
        feed = run / "cloud/TianliApps/Updates" / suite / "test/release.json"
        env.update(APP_LIFECYCLE_SUPPORT_DIR=str(run / "local"), APP_LIFECYCLE_CLOUD_DIR=str(run / "cloud"),
                   UNREVOKE_LIFECYCLE_SUITE=suite, UNREVOKE_TEST_UPDATE_CHANNEL="test",
                   APP_LIFECYCLE_NO_RELAUNCH="1", UNREVOKE_BASICS_OUT=str(run / "ui"))
        # A real signed copy of the product, marked only as a local test release.
        # The production installer will replace the disposable clone, not /Applications.
        next_app = run / "next/WeChatUnrevoke.app"
        shutil.copytree(clone, next_app, symlinks=True)
        next_info = dict(info, CFBundleShortVersionString="999.0.1", CFBundleVersion="1000")
        (next_app / "Contents/Info.plist").write_bytes(plistlib.dumps(next_info))
        subprocess.run(["codesign", "--force", "--sign", "-", str(next_app)], check=True, capture_output=True)
        package = feed.parent / "fixture.zip"
        package.parent.mkdir(parents=True)
        subprocess.run(["ditto", "-c", "-k", "--keepParent", str(next_app), str(package)], check=True, capture_output=True)
        release = {"bundle_id": suite, "version": "999.0.1", "build": "1000", "filename": package.name, "channel": "test",
                   "sha256": sha(package), "size_bytes": package.stat().st_size,
                   "release_url": "https://github.com/zengtianli/WeChatUnrevoke/releases", "notes": "Isolated acceptance fixture; never published."}
        write(feed, release)
        done = subprocess.run([str(executable), "--product-basics-self-test"], env=env,
                              cwd=ROOT, capture_output=True, text=True, timeout=60)
        (run / "ui.log").write_text(done.stdout + done.stderr)
        ui = json.loads((run / "ui/ui.json").read_text())["checks"]
        checks.update(ui)
        assert done.returncode == 0 and all(ui.values()), "Real offscreen UI checks failed"
        fresh = command(["settings", "status"], lambda b: b["variant"] == "silent" and b["auto_repatch"] is False)
        keys = command(["shortcuts", "status"], lambda b: b["enabled"] is True and b["key"] == "r" and b["modifiers"] == 1179648)
        check("settings.persisted_readback", fresh["variant"] == "silent" and keys["enabled"])
        exported = run / "export.json"
        command(["config", "export", "-o", str(exported)], lambda b: b["ok"])
        bad = run / "invalid.json"; bad.write_text("{broken")
        command(["config", "import", str(bad), "--yes"], lambda b: b.get("error", {}).get("code") == "import_rejected", code=1)
        command(["settings", "status"], lambda b: b["variant"] == "silent" and not b["auto_repatch"])
        retained_export = run / "retained-export.json"
        command(["config", "export", "-o", str(retained_export)], lambda b: b["ok"])
        check("settings.error_preserves_data", sha(exported) == sha(retained_export))
        imported = command(["config", "import", str(exported), "--yes"], lambda b: b["imported"])
        restored = command(["settings", "status"], lambda b: b["variant"] == "silent" and not b["auto_repatch"])
        check("settings.valid_transfer_readback", imported["imported"] and restored["variant"] == "silent")
        command(["shortcuts", "off", "--unexpected", "--yes"], lambda b: b["ok"] is False, code=2)
        rejected = command(["shortcuts", "status"], lambda b: b["enabled"] and b["modifiers"] == keys["modifiers"])
        check("shortcuts.invalid_arguments_preserve_binding", rejected["enabled"] and rejected["modifiers"] == keys["modifiers"])
        command(["shortcuts", "off", "--yes"], lambda b: not b["enabled"])
        command(["shortcuts", "status"], lambda b: not b["enabled"] and b["modifiers"] == keys["modifiers"])
        command(["shortcuts", "on", "--yes"], lambda b: b["enabled"] and b["modifiers"] == keys["modifiers"])
        check("shortcuts.disable_restore", ui["shortcuts.disable_restore"])

        def sync(environment=env):
            command(["config", "sync", "off", "--yes"], lambda b: not b["sync_enabled"], environment=environment)
            return command(["config", "sync", "on", "--yes"], lambda b: b["sync_enabled"], environment=environment)

        sync()
        cloud = run / "cloud" / (PRODUCT + ".json")
        pushed = json.loads(cloud.read_text())
        assert pushed["values"]["defaults.variant"] == "silent"
        remote_env = dict(env, UNREVOKE_LIFECYCLE_SUITE=suite + ".remote", APP_LIFECYCLE_SUPPORT_DIR=str(run / "remote"))
        suites.append(suite + ".remote")
        sync(remote_env)
        command(["settings", "status"], lambda b: b["variant"] == "silent" and not b["auto_repatch"], environment=remote_env)
        # A remote edit is applied by the product's actual reconciliation path.
        remote = json.loads(cloud.read_text()); remote["values"]["defaults.variant"] = "keeptip"
        write(cloud, remote)
        sync()
        command(["settings", "status"], lambda b: b["variant"] == "keeptip")
        check("icloud.push_pull", pushed["values"]["defaults.variant"] == "silent")
        offline = dict(env); offline.pop("APP_LIFECYCLE_CLOUD_DIR")
        command(["config", "sync", "off", "--yes"], lambda b: not b["sync_enabled"], environment=offline)
        unavailable = command(["config", "sync", "on", "--yes"], lambda b: b.get("error", {}).get("code") == "sync_incomplete", code=1, environment=offline)
        local = command(["settings", "status"], lambda b: b["variant"] == "keeptip", environment=offline)
        check("icloud.unavailable_local_fallback", unavailable.get("error", {}).get("code") == "sync_incomplete" and local["variant"] == "keeptip")
        cloud.write_text("{broken")
        command(["config", "sync", "off", "--yes"], lambda b: not b["sync_enabled"])
        corrupt = command(["config", "sync", "on", "--yes"], lambda b: b.get("error", {}).get("code") == "sync_incomplete", code=1)
        command(["settings", "status"], lambda b: b["variant"] == "keeptip")
        write(cloud, remote); sync()
        recovered = command(["settings", "status"], lambda b: b["variant"] == "keeptip")
        check("icloud.conflict_or_corrupt_recovery", corrupt.get("error", {}).get("code") == "sync_incomplete" and recovered["variant"] == "keeptip")
        cloud_before = sha(cloud)
        command(["config", "sync", "off", "--yes"], lambda b: not b["sync_enabled"])
        command(["settings", "status"], lambda b: b["variant"] == "keeptip")
        check("icloud.disable_preserves_data", cloud.exists() and sha(cloud) == cloud_before)

        command(["update", "options"], lambda b: b["options"]["automaticCheck"] is True)
        command(["update", "options", "--auto-check", "off", "--interval", "6", "--yes"], lambda b: b["options"]["intervalHours"] == 6)
        command(["update", "options"], lambda b: b["options"]["intervalHours"] == 6 and not b["options"]["automaticCheck"])
        command(["update", "options", "--interval", "0", "--yes"], lambda b: b.get("ok") is False, code=2)
        command(["update", "options"], lambda b: b["options"]["intervalHours"] == 6)
        check("updates.options_or_store_entry", ui["updates.real_options_control"])
        baseline = command(["settings", "status"], lambda b: b["variant"] == "keeptip")
        feed.unlink()
        command(["update", "check"], lambda b: b.get("ok") is False, code=1)
        feed.write_text("{broken")
        command(["update", "check"], lambda b: b.get("ok") is False, code=1)
        write(feed, release)
        body = command(["update", "check"], lambda b: b["update_available"] and b["latest"]["version"] == "999.0.1" and b["upgrade"]["in_app"])
        check("updates.check_result", ui["updates.real_check_result_in_window"] and body["update_available"])
        check("updates.failure_recovery", body["latest"]["version"] == "999.0.1")
        installed = command(["update", "install", "--yes"], lambda b: b["installed"] and b["state"] == "installed")
        assert plistlib.loads((clone / "Contents/Info.plist").read_bytes())["CFBundleShortVersionString"] == "999.0.1"
        after_upgrade = command(["settings", "status"], lambda b: b["variant"] == baseline["variant"] and b["auto_repatch"] == baseline["auto_repatch"])
        command(["shortcuts", "status"], lambda b: b["enabled"] and b["modifiers"] == keys["modifiers"])
        command(["update", "options"], lambda b: b["options"]["intervalHours"] == 6 and not b["options"]["automaticCheck"])
        check("updates.data_preservation", installed["installed"] and after_upgrade["variant"] == baseline["variant"])
        check("settings.interaction", ui["settings.real_control_actions"] and ui["settings.no_visible_windows_or_dock"])
        check("shortcuts.action_path", ui["shortcuts.real_refresh_action"])
        valid_after, reason = app_sop.verify_build_receipt(registered, app, receipt_path=receipt_path)
        check("settings.candidate_and_source_unchanged", valid_after and identity["executable_sha256"] == sha(app / artifact["executable"]))
    except Exception as exc:
        error = str(exc)
    finally:
        check("settings.production_data_unchanged", owner_state() == before)
        for suite in suites:
            subprocess.run(["/usr/bin/defaults", "delete", suite], capture_output=True)
    # Obligations are selected from the real policy and their values are actual
    # assertions above. Missing/false assertions always fail, including partial runs.
    features = {}
    raw = {"schema_version": 1, "app_id": "unrevoke-mac", "spec_digest": spec["digest"],
           "checks": checks, "cases": cases, "artifact": identity, "error": error,
           "scope": "Real compiled product; disposable identity and offscreen controls; isolated cloud-directory transport and actual isolated upgrade. Apple cross-device delivery is not verified."}
    raw_path = run / "raw.json"; write(raw_path, raw)
    for feature in FEATURES:
        names = [name for name in checks if name.startswith(feature + ".")]
        required = spec["features"][feature]["required_checks"]
        passed = error is None and all(checks.get(name) is True for name in required + names)
        features[feature] = {"result": "passed" if passed else "failed", "method": "ui_automation" if feature == "settings" else "real_product",
                             "checks": list(dict.fromkeys(required + names)), "evidence": str(raw_path.relative_to(ROOT)), "evidence_sha256": sha(raw_path)}
    detail = {"schema_version": 1, "app_id": "unrevoke-mac", "spec_digest": spec["digest"], "features": features,
              "artifact_scope": scope, "summary": "真实隔离四项基础行为验收" + ("失败：" + error if error else "完成"), "scope": raw["scope"]}
    write(out / "product_basics.detail.json", detail)
    print(detail["summary"], flush=True)
    return 0 if all(f["result"] == "passed" for f in features.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())

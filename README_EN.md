[中文](README.md) | **English**

<p align="center"><img src="icon/AppIcon.png" width="128" height="128" alt="WeChatUnrevoke icon"></p>
<h1 align="center">WeChatUnrevoke</h1>
<p align="center"><strong>Keep the message. Even after recall.</strong><br>A native SwiftUI app to check, apply and restore WeChat anti-recall patches on Mac.</p>
<p align="center"><a href="https://unrevoke.tianli.cyou/">Product website · Direct download</a> · <a href="#get-started">Get started</a> · <a href="https://github.com/zengtianli/WeChatUnrevoke/issues">Report an issue</a> · <a href="README.md">中文</a></p>
<p align="center">macOS 15+ · Apple Silicon + Intel · Free and open source · AGPL-3.0</p>
<p align="center"><img src="docs/screenshots/main-en.png" width="620" alt="Actual WeChatUnrevoke interface"></p>
<p align="center"><sub>Actual app screenshot using a WeChat build 269627 test copy, with anti-recall and update blocking active. Compatibility with other builds varies.</sub></p>

## Leave the commands to the engine

**[Visit the product website](https://unrevoke.tianli.cyou/)** for direct downloads, illustrated installation instructions and playable tutorials. No GitHub account is needed to download or use the app. The website and video captions are in Chinese; English instructions follow below.

Real recordings: [Enable anti-recall](https://unrevoke.tianli.cyou/media/enable.mp4) · [Check and restore](https://unrevoke.tianli.cyou/media/restore.mp4) · [Complete tutorial](https://unrevoke.tianli.cyou/media/tutorial.mp4). Recorded with v1.0.4 and a WeChat build 269627 test copy. Independent scenes and shortened waits are labeled. See [recording notes](docs/demo/README.md).

WeChatUnrevoke reads your WeChat build and lets you manage patches through a native interface. The embedded [WeChatTweak engine](https://github.com/zengtianli/WeChatTweak) performs the work and determines protection status.

| What you need | What the app provides |
|---|---|
| Preserve recalled messages | Keep notice mode retains messages and notices in private chats. Group chats preserve messages without notices. Silent mode suppresses notices. |
| Understand protection | Separate anti-recall, update-blocking and entitlement details. |
| Recover after updates | Automatic reapplication only when WeChat is closed, no password is needed, and full protection previously succeeded. |
| Builds whose updater cannot be blocked | Anti-recall and the update block run independently: anti-recall is still applied, and the reason the update block is missing is shown. |
| Restore or troubleshoot | Restore patch bytes or copy diagnostics with retained engine output and write errors. |

**No activation codes, no need to disable SIP, no kernel extension or persistent root helper.** Native SwiftUI with an embedded Swift CLI; no Python runtime. Patch configuration can update online; engine and interface changes still require app updates.

## Lightweight: measured numbers

| Download | Idle memory | Idle CPU | Open to status |
|---|---|---|---|
| **2.4 MB** (ZIP; 4.3 MB installed) | **30 MB** | **0.12%** (the check engine does not start while WeChat is unchanged; a full check every 30 minutes is included) | **2.8 s** |

The interface only displays state. All reading and writing of WeChat is done by the bundled command-line engine, which exits when done. While the window is open, it compares a file fingerprint of the WeChat bundle once a minute and starts the engine only when WeChat was updated, patched or restored, plus a full check every 30 minutes as a backstop. There is no background service, and checks stop when the window is closed.

<sub>Measured on v1.0.9 · Mac16,12 / Apple M4 / macOS 27.2 · WeChat build 269627 (direct-download edition), window open and idle · 2026-09-26. Memory is phys_footprint (same as the Memory column in Activity Monitor), median of 3 windows. CPU is CPU time of the interface and its subprocesses ÷ wall time over a 180 s idle window, averaged over 3 windows; a full check takes about 2.8 s and 0.70 s of CPU, counted once every 30 minutes. Launch time is the median of 5 background launches. The Mac was under heavy load while measuring (1-minute load average about 27); 1.0.8 measured side by side under the same conditions idled at 0.59% CPU and took 3.5 s from open to status. Raw data: [perf/lightweight.json](perf/lightweight.json).</sub>

## Get started

1. Download `WeChatUnrevoke-<version>.zip` from the **[latest release](https://github.com/zengtianli/WeChatUnrevoke/releases/latest)** and move **WeChatUnrevoke.app** into Applications. Quit the old version first. When upgrading from Unrevoke, move the old app to Trash to avoid duplicate launchers. Preferences and bundle ID remain unchanged.
2. Quit WeChat, open WeChatUnrevoke, select **Keep notice**, then enable anti-recall. Enter your administrator password if macOS requests it and wait for signing to finish. Press `⌘R` to refresh.
3. Expand **Details** and check that anti-recall is active and entitlements are intact. Open WeChat and verify with a real recalled message. Check again after WeChat updates.

Or use Homebrew:

```bash
brew install --cask zengtianli/tap/wechat-unrevoke
# Upgrade: brew update && brew upgrade --cask zengtianli/tap/wechat-unrevoke
```

Releases are ad-hoc signed, **without Apple Developer ID signing or notarization**. After confirming the download comes from this repository, remove its quarantine attribute if macOS blocks it:

```bash
xattr -dr com.apple.quarantine /Applications/WeChatUnrevoke.app
```

Anti-recall and the update block are independent: if one cannot be applied, the other still is. The App Store edition is updated by the App Store and has no in-app updater to block, and some builds' updaters are not covered yet. The status then reads **Anti-recall is on**, with the reason the update block is missing below it: for the App Store edition, turn off App Store automatic updates; for other builds, turn protection on again after a WeChat update when reminded.

If you see **`You don’t have permission to save ... wechat.dylib`**, `Permission denied`, or `Operation not permitted`, the file write was denied, even if the log already says `Matched config: build 269631`. In **System Settings → Privacy & Security → App Management**, allow **WeChatUnrevoke** to modify other apps. Use `+` to add the `WeChatUnrevoke.app` you are running if it is missing. Quit and reopen WeChatUnrevoke, then retry. CLI users should authorize the terminal application that launches the command.

An administrator password does not replace App Management permission; [Apple describes this setting](https://support.apple.com/guide/mac-help/change-privacy-security-settings-on-mac-mchl211c911f/mac) as allowing changes to other apps. The same error can also result from file ownership, ACLs, or locked files. If authorization does not resolve it, include the full diagnostic report for further investigation. From v1.0.5, the app shows these steps, preserves the original log, and pauses background write retries for the current run after a permission denial until you retry manually or restart the app. Every failed write still ends with a check of the actual patch state.

For problems, copy diagnostics into an [issue](https://github.com/zengtianli/WeChatUnrevoke/issues), including app version, last engine log and last write error. Remove personal paths you do not want to publish.

## Requirements and limits

- **macOS 15+, Apple Silicon or Intel.** Patch coverage depends on the WeChat build and architecture. A universal app does not imply every WeChat build has patches for both architectures.
- Compatibility work targets the latest stable release from WeChat's official website. Supported builds come from the [patch configuration](https://github.com/zengtianli/WeChatTweak/blob/master/config.json). If an older build is missing, update to the official stable build listed in the [support table](https://github.com/zengtianli/WeChatTweak#支持的版本); the App Store may distribute a different build. Reapply the patch after updating WeChat. Quit and reopen WeChatUnrevoke while online to refresh its patch configuration. Unsupported builds are reported explicitly.
- Group chats preserve messages without recall notices. Private-chat notices may not appear immediately next to the original message.
- Anti-recall-only mode leaves automatic updates enabled. Updates can remove patches.
- This is an unofficial tool, unaffiliated with Tencent. It modifies your local WeChat client; understand and accept the associated risks. It does not read or upload chat content. Configuration updates connect to GitHub; help links open the project website.

## Open source, feedback and sharing

Maintained by [zengtianli](https://github.com/zengtianli). If the app helps you, **star this repository** or share the [download page](https://github.com/zengtianli/WeChatUnrevoke/releases/latest). Reproducible reports, compatibility fixes and documentation contributions are welcome.

Use the [press kit](docs/press-kit.md) for the canonical name, icon, bilingual descriptions, real screenshots and download link. Screenshots demonstrate the interface, not compatibility with every WeChat build.

## Build from source

```bash
git clone https://github.com/zengtianli/WeChatTweak
git clone https://github.com/zengtianli/WeChatUnrevoke
cd WeChatUnrevoke
ENGINE_REPO=../WeChatTweak ./build.sh
```

An appropriate Xcode toolchain and `python3` (for the included build check) are required. Select Xcode with `xcode-select` or `DEVELOPER_DIR`; no maintainer-only tools are needed. The build embeds the universal engine and configuration, signs ad-hoc and installs the app. Use `INSTALL_APP=0 ENGINE_REPO=../WeChatTweak ./build.sh` to build without installing, and `bash tests/run.sh` for regression checks. `release.sh` packages both architectures straight from the build product; it does not install or replace the app on the build machine. The stable bundle ID is `io.github.zengtianli.unrevoke`; the display name and archive use WeChatUnrevoke.

Maintainers: validate GUI writes on a WeChat copy, update the version and release notes, commit, then run:

```bash
python3 scripts/publish.py docs/releases/1.0.5.md
```

This runs regression tests, builds, pushes, uploads a draft, verifies the downloaded archive, publishes, updates Homebrew and deploys the product site from the latest public release. A failed site deployment does not undo the published GitHub release; resume with `bash scripts/deploy-site.sh`. This does not replace GUI validation or post issue comments.

## Credits and license

Based on [sunnyyoung/WeChatTweak](https://github.com/sunnyyoung/WeChatTweak), with the engine maintained at [zengtianli/WeChatTweak](https://github.com/zengtianli/WeChatTweak). The 4.x keep-notice approach references [fzlzjerry/wechat-antirecall](https://github.com/fzlzjerry/wechat-antirecall).

Code is licensed under [AGPL-3.0](LICENSE). The icon was generated with Seedream; see [provenance](icon/provenance.json).

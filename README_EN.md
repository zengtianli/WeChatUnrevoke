<p align="center"><img src="icon/AppIcon.png" width="128" height="128" alt="WeChatUnrevoke icon"></p>
<h1 align="center">WeChatUnrevoke</h1>
<p align="center"><strong>Keep the message. Even after recall.</strong><br>A native SwiftUI app to check, apply and restore WeChat anti-recall patches on Mac.</p>
<p align="center"><a href="https://unrevoke.tianli.cyou/">Product website · Direct download</a> · <a href="#get-started">Get started</a> · <a href="https://github.com/zengtianli/WeChatUnrevoke/issues">Report an issue</a> · <a href="README.md">中文</a></p>
<p align="center">macOS 15+ · Apple Silicon + Intel · Free and open source · AGPL-3.0</p>
<p align="center"><img src="docs/screenshots/main-en.png" width="620" alt="Actual WeChatUnrevoke interface"></p>
<p align="center"><sub>Actual app screenshot using a WeChat build 269627 test copy, with anti-recall and update blocking active. Compatibility with other builds varies.</sub></p>

## Leave the commands to the engine

**[Visit the product website](https://unrevoke.tianli.cyou/)** for direct downloads, illustrated installation instructions and playable tutorials. No GitHub account is needed to download or use the app. The website and video captions are in Chinese; English instructions follow below.

Real recordings: [Enable anti-recall](https://unrevoke.tianli.cyou/media/enable.mp4) · [Anti-recall only](https://unrevoke.tianli.cyou/media/partial.mp4) · [Check and restore](https://unrevoke.tianli.cyou/media/restore.mp4) · [Complete tutorial](https://unrevoke.tianli.cyou/media/tutorial.mp4). Recorded with v1.0.4 and a WeChat build 269627 test copy. Independent scenes and shortened waits are labeled. See [recording notes](docs/demo/README.md).

WeChatUnrevoke reads your WeChat build and lets you manage patches through a native interface. The embedded [WeChatTweak engine](https://github.com/zengtianli/WeChatTweak) performs the work and determines protection status.

| What you need | What the app provides |
|---|---|
| Preserve recalled messages | Keep notice mode retains messages and notices in private chats. Group chats preserve messages without notices. Silent mode suppresses notices. |
| Understand protection | Separate anti-recall, update-blocking and entitlement details. |
| Recover after updates | Automatic reapplication only when WeChat is closed, no password is needed, and full protection previously succeeded. |
| Work around an unsupported updater | Explicit anti-recall-only action with confirmation. |
| Restore or troubleshoot | Restore patch bytes or copy diagnostics with retained engine output and write errors. |

**No activation codes, no need to disable SIP, no kernel extension or persistent root helper.** Native SwiftUI with an embedded Swift CLI; no Python runtime. Patch configuration can update online; engine and interface changes still require app updates.

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

If you encounter `XAppUpdateManager not found` (for example, build `269136`), the updater layout does not match the current blocking rules. Choose the **anti-recall-only** action and confirm the update risk. This can produce a **partial** status because updates remain unblocked; it does not mean anti-recall failed. SIP can stay enabled.

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

An appropriate Xcode toolchain and `python3` (for the included build check) are required. Select Xcode with `xcode-select` or `DEVELOPER_DIR`; no maintainer-only tools are needed. The build embeds the universal engine and configuration, signs ad-hoc and installs the app. Use `INSTALL_APP=0 ENGINE_REPO=../WeChatTweak ./build.sh` to build without installing, and `bash tests/run.sh` for regression checks. `release.sh` packages both architectures. The stable bundle ID is `io.github.zengtianli.unrevoke`; the display name and archive use WeChatUnrevoke.

Maintainers: validate GUI writes on a WeChat copy, update the version and release notes, commit, then run:

```bash
python3 scripts/publish.py docs/releases/1.0.4.md
```

This runs regression tests, builds, pushes, uploads a draft, verifies the downloaded archive, publishes, updates Homebrew and deploys the product site from the latest public release. A failed site deployment does not undo the published GitHub release; resume with `bash scripts/deploy-site.sh`. This does not replace GUI validation or post issue comments.

## Credits and license

Based on [sunnyyoung/WeChatTweak](https://github.com/sunnyyoung/WeChatTweak), with the engine maintained at [zengtianli/WeChatTweak](https://github.com/zengtianli/WeChatTweak). The 4.x keep-notice approach references [fzlzjerry/wechat-antirecall](https://github.com/fzlzjerry/wechat-antirecall).

Code is licensed under [AGPL-3.0](LICENSE). The icon was generated with Seedream; see [provenance](icon/provenance.json).

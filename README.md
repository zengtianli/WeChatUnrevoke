<p align="center">
  <img src="icon/AppIcon.png" width="128" height="128" alt="WeChatUnrevoke 应用图标">
</p>
<h1 align="center">WeChatUnrevoke</h1>
<p align="center"><strong>撤回之后，消息仍在。</strong><br>为 Mac 微信保留被撤回的消息。原生 SwiftUI，一屏完成检查、开启与还原。</p>
<p align="center">
  <a href="https://github.com/zengtianli/WeChatUnrevoke/releases/latest">下载 Mac 版</a> ·
  <a href="#三步开始">使用指南</a> ·
  <a href="https://github.com/zengtianli/WeChatUnrevoke/issues">反馈问题</a> ·
  <a href="README_EN.md">English</a>
</p>
<p align="center">
  <a href="https://github.com/zengtianli/WeChatUnrevoke/releases/latest"><img src="https://img.shields.io/github/v/release/zengtianli/WeChatUnrevoke?style=flat-square&amp;color=648569" alt="最新版本"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-252b26?style=flat-square&amp;logo=apple" alt="macOS 15 及以上">
  <img src="https://img.shields.io/badge/Apple_Silicon_%2B_Intel-Universal-648569?style=flat-square" alt="支持 Apple Silicon 与 Intel">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-648569?style=flat-square" alt="AGPL-3.0"></a>
</p>

<p align="center"><img src="docs/screenshots/main-zh.png" width="620" alt="WeChatUnrevoke 中文实机界面：保护状态、保留提示、自动重打与诊断"></p>
<p align="center"><sub>真实应用截图：微信 build 269627 测试副本，防撤回与更新拦截均已生效。其他版本支持情况以检查结果为准。</sub></p>

## 把命令行留给引擎

不用手动查构建号，也不用记住补丁命令。WeChatUnrevoke 读取你的微信状态，告诉你能做什么，再把操作交给内嵌的 [WeChatTweak 引擎](https://github.com/zengtianli/WeChatTweak)。适合希望保留聊天消息、又想用图形界面检查和管理补丁的 Mac 用户。

| 你想做的事 | 应用怎么帮你 |
|---|---|
| 保留消息，也知道对方撤回过 | 默认「保留提示」：私聊保留消息和撤回提示；群聊保留消息，暂不显示提示。 |
| 安静地保留消息 | 切换「静默」，不显示撤回提示。 |
| 看清是否已生效 | 状态由引擎统一判定，详情分别显示防撤回、更新拦截和签名权限。 |
| 减少更新造成的补丁丢失 | 默认尝试拦截自动更新；满足无需密码、微信已退出、曾完整保护成功等条件时，自动重新打补丁。 |
| 旧版本拦截更新失败 | 自行选择「仅开启防撤回…」，确认更新风险后继续，不会静默降低保护。 |
| 撤销操作或报告问题 | 一键还原补丁字节；失败后保留日志，可复制完整诊断报告。 |

**免费开源，无激活码。无需关闭 SIP，无内核扩展，无常驻 root helper。** 原生 SwiftUI 前端，内嵌 Swift CLI，没有 Python 运行环境。补丁库可联网更新；引擎规则或界面有变化时仍需更新应用。

## 三步开始

### 1. 安装最新版

**[下载最新 Release](https://github.com/zengtianli/WeChatUnrevoke/releases/latest)** 中的 `WeChatUnrevoke-<版本>.zip`，解压后将 **WeChatUnrevoke.app** 拖进「应用程序」。升级前退出旧版；从旧名 Unrevoke 升级时，把旧 app 移到废纸篓，避免出现两个入口。设置沿用原 bundle ID，不需要重新配置。

也可以使用 Homebrew：

```bash
brew install --cask zengtianli/tap/wechat-unrevoke
# 已安装：brew update && brew upgrade --cask zengtianli/tap/wechat-unrevoke
```

发布物采用 ad-hoc 签名，**没有 Apple 开发者 ID 签名或公证**。确认来源是本仓库后，若 macOS 阻止打开，可按以下方式移除这份 app 的下载隔离标记：

```bash
xattr -dr com.apple.quarantine /Applications/WeChatUnrevoke.app
```

### 2. 退出微信，点击开启

打开 WeChatUnrevoke，保持「保留提示（推荐）」，点击「开启防撤回」。系统要求时输入管理员密码，等待重签名结束。`⌘R` 可以重新检查状态。

若提示 `XAppUpdateManager not found`（例如 build `269136`），是旧微信的更新模块不符合当前拦截规则。点击 **「仅开启防撤回…」**，阅读并确认更新风险后继续。无需关闭 SIP。

### 3. 检查结果，再打开微信

展开「详情」，确认 **防撤回：已生效**、**签名权限：完整**。仅防撤回模式可能显示 **「部分保护已生效」**，这是更新未被拦截的状态，并不等于防撤回失败。自行打开微信，用一条真实被撤回的消息验证。

微信更新可能清除补丁，更新后请重新检查。遇到问题，点击「复制诊断报告」，在 [Issues](https://github.com/zengtianli/WeChatUnrevoke/issues) 附上 app version、last engine log 和 last write error；发布前删去不想公开的个人路径。

## 运行要求与边界

- **macOS 15+，Apple Silicon / Intel。** 补丁支持按微信 build 和架构而异，以引擎实际检查结果为准；universal 安装包不代表所有微信版本均有双架构补丁。
- **版本覆盖由补丁库决定。** 当前随包配置见 [config.json](https://github.com/zengtianli/WeChatTweak/blob/master/config.json)。没有收录的版本会明确提示，不猜地址写入。
- **群聊暂不显示撤回提示。** 即使选「保留提示」，群聊也只保留消息。私聊提示位置也不保证紧贴原消息。
- **仅防撤回不拦截自动更新。** 此模式不等于完整保护；更新后需要重新检查。
- **不是微信官方产品，与腾讯无隶属关系。** 本工具修改本机微信客户端，请自行了解并承担客户端修改和使用风险。它不读取或上传聊天内容；补丁库更新请求访问 GitHub，点击帮助链接会打开项目主页。

## 开源、反馈与传播

由 [zengtianli](https://github.com/zengtianli) 维护。觉得有用，可以 **Star 本仓库**，把[下载页](https://github.com/zengtianli/WeChatUnrevoke/releases/latest)分享给同样使用 Mac 微信的朋友。版本适配、可复现问题和文档改进欢迎提交 issue 或 PR。

介绍本项目可直接使用 [产品素材包](docs/press-kit.md)：统一名称、图标、中英简介、真实截图和下载链接。截图展示应用功能，不代表每个微信 build 都已验证。

## 从源码构建

```bash
git clone https://github.com/zengtianli/WeChatTweak
git clone https://github.com/zengtianli/WeChatUnrevoke
cd WeChatUnrevoke
ENGINE_REPO=../WeChatTweak ./build.sh
```

需要适用的 Xcode 工具链。`build.sh` 构建并嵌入 universal 引擎、打包配置、ad-hoc 签名并安装应用；双架构发布使用 `release.sh`。bundle ID 保持 `io.github.zengtianli.unrevoke`，显示名与发行包统一为 WeChatUnrevoke。

维护者发布前先做 GUI 副本验收，更新 `Info.plist` 版本和 `docs/releases/<版本>.md`，提交后运行：

```bash
python3 scripts/publish.py docs/releases/1.0.3.md
```

发布入口运行回归测试、构建、打包、推送、草稿上传、下载校验、公开发布及 Homebrew 同步。已有同版本 Release 不会覆盖；不替代实机验收，也不会自动发送 issue 评论。

## 致谢与许可

基于 [sunnyyoung/WeChatTweak](https://github.com/sunnyyoung/WeChatTweak)，引擎维护于 [zengtianli/WeChatTweak](https://github.com/zengtianli/WeChatTweak)。4.x 保留提示思路参考 [fzlzjerry/wechat-antirecall](https://github.com/fzlzjerry/wechat-antirecall)。感谢提供兼容性反馈与复现日志的使用者。

代码采用 [AGPL-3.0](LICENSE)。图标由 Seedream 生成，来源记录见 [icon/provenance.json](icon/provenance.json)。

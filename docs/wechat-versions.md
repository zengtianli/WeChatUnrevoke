# 微信版本与安装包校验 / WeChat versions and installer checksums

报告问题或记录新适配时，请同时写 **渠道、完整版本、build、处理器架构**。例如：`官网 / 4.1.13.59 / build 269627 / arm64`。营销版本 `4.1.13` 不能唯一确定一个安装包。

| 信息 | 微信包中的来源 | 用途 |
| --- | --- | --- |
| 营销版本，例如 4.1.13 | `CFBundleShortVersionString` | 设置里常见的版本号 |
| 完整版本，例如 4.1.13.59 | `WeChatBundleVersion` | 区分同一营销版本的不同发行；缺失时写营销版本 + build |
| 构建号，例如 269627 | `CFBundleVersion` | WeChatTweak 的补丁库匹配键 |
| 安装包 SHA256 | 原版 DMG 的实际字节 | 确认取样的是哪一个安装包 |

社区的 [zsbai/wechat-versions](https://github.com/zsbai/wechat-versions) 保存官网 Mac 安装包，Release 附带完整版本与 SHA256，可用于找到样本、对照发行记录。它**不包含 App Store 版**。目录中出现新版本或校验和相同，都不能代替本工具的补丁支持与原始指令字节验证；支持范围以 [引擎补丁库](https://github.com/zengtianli/WeChatTweak/blob/master/config.json) 和实际体检为准。

在本仓用只读辅助脚本提取当前微信版本：

```sh
python3 scripts/wechat-version.py --app /Applications/WeChat.app
```

有原版安装包时，同时计算、比对其 SHA256：

```sh
python3 scripts/wechat-version.py --app /path/to/WeChat.app \
  --installer /path/to/WeChat.dmg --expected-sha256 <来源记录的64位SHA256>
```

SHA256 不匹配时命令退出 1；未提供安装包时输出 `installer_sha256: null`，不会拿已安装 App 或打过补丁的 dylib 冒充原版 DMG 摘要。指定 App 与 DMG 是两份独立证据：记录适配样本时，App 必须实际从该 DMG 解出，再验证 build、架构、补丁写入和还原。辅助脚本供源码维护和诊断使用，GUI 运行仍不需要 Python。

后续适配记录采用：`渠道 / 完整版本 / build / 架构 / 原版DMG SHA256 / 样本来源 / 实测范围`。App Store 样本没有官网 DMG，明确写不适用；没有拿到原件的摘要写未验证。

### 构建成功仍显示未收录

构建 GUI 和通过测试只证明程序能构建、已有行为通过检查，不会自动生成新微信版本的补丁点。先看诊断报告的 `build`、`host arch`、`config known`；同一营销版本、不同构建或架构不能互套补丁。

反馈帖中 4.1.15.55 / 270135 的 Intel 用户，构建日志显示成功安装，但内嵌补丁库仍是 45 个构建，诊断显示 `config known: false`，与 issue #9 同因。应更新经过验证的引擎补丁库，而非反复构建 GUI。GUI 优先读取下载缓存，再回退内嵌配置；本地修改引擎 config 后，仅重新打包也不能证明 GUI 已选中它。可用引擎 `doctor -a /path/to/WeChat.app -c /path/to/config.json --json` 显式核验候选配置。

34888 对应 4.1.7.57；其撤回逻辑仍在 `Contents/MacOS/WeChat`，没有新版的 `Contents/Resources/wechat.dylib`，当前三代自动定位签名均未匹配。不要用相邻版本地址或仅改构建号。

## English

### A successful build can still report an unsupported WeChat build

Building the GUI and passing tests do not generate new patch locations. Check the diagnostic build, host architecture and config-known fields. The Intel 4.1.15.55 / 270135 report in issue #1 shows a successful build with the old 45-build configuration, the same missing-data issue as #9. The GUI prefers downloaded configuration over its bundled snapshot; rebuilding alone does not prove it selected a locally edited configuration. Use the engine's explicit `doctor -a /path/to/WeChat.app -c /path/to/config.json --json` to check a candidate. Build 34888 is 4.1.7.57 and keeps the logic in the main executable; the current three locator generations do not match it.

Include **channel, full version, build and architecture** in reports and patch release notes, for example `official website / 4.1.13.59 / build 269627 / arm64`. Read the full version from `WeChatBundleVersion`, the marketing version from `CFBundleShortVersionString`, and the patch lookup key from `CFBundleVersion`. If the full version is absent, use the marketing version plus the build.

[zsbai/wechat-versions](https://github.com/zsbai/wechat-versions) archives official website installers and publishes full versions and SHA256 checksums. It does not include App Store builds. Archive availability and checksum equality do not establish patch support; the engine's configuration, expected bytes and actual verification determine support.

The read-only commands above identify a supplied app and optionally hash an original DMG. A mismatched expected checksum returns exit code 1; an absent installer produces a null checksum. The tool does not establish that the supplied app came from that DMG. Extract the sample from the verified installer before recording patch results. The GUI continues to run without Python.

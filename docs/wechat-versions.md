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

## English

Include **channel, full version, build and architecture** in reports and patch release notes, for example `official website / 4.1.13.59 / build 269627 / arm64`. Read the full version from `WeChatBundleVersion`, the marketing version from `CFBundleShortVersionString`, and the patch lookup key from `CFBundleVersion`. If the full version is absent, use the marketing version plus the build.

[zsbai/wechat-versions](https://github.com/zsbai/wechat-versions) archives official website installers and publishes full versions and SHA256 checksums. It does not include App Store builds. Archive availability and checksum equality do not establish patch support; the engine's configuration, expected bytes and actual verification determine support.

The read-only commands above identify a supplied app and optionally hash an original DMG. A mismatched expected checksum returns exit code 1; an absent installer produces a null checksum. The tool does not establish that the supplied app came from that DMG. Extract the sample from the verified installer before recording patch results. The GUI continues to run without Python.

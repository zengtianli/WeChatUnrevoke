# 第二个微信（多开副本）—— WeChatTweak #11（2026-11-11）

本人 2026-11-11 同意：功能做进 WeChatUnrevoke，实现走「复制整包 + 换包名重签」，不走按版本打补丁。

## 做了什么
- 引擎 `~/Apps/vendor/WeChatTweak`（本地提交 `38aaa39`、`0bf422e`，未推送）：新子命令 `wechattweak clone [--to] [--bundle-id]`。
  整包 APFS 克隆 → 关副本的内置更新器（复用 patch 的更新拦截，防撤回字节原样继承）→ 改 `CFBundleIdentifier` →
  重签（根对象用新标识；所有代码对象去掉沙盒、腾讯 application-identifier、应用组、temporary-exception）。
  在目标旁做好再改名就位，失败不留半成品；旧副本进废纸篓；目标位置是别的东西就拒绝。
  官网版微信的构建未收录（关不掉更新器）时拒绝创建。`doctor` 认得副本（`is_copy`、`bundle_id`），不再判成 brokenBundle。
- GUI：主窗口新增「第二个微信」一栏（创建 / 更新副本 / 打开 / 移除…），固定 `~/Applications/WeChat2.app`、
  包名 `com.tencent.xinWeChat2`（偏好 `secondWeChatPath` 可改，测试用）。中英文案 20 条。
- 命令行：`unrevoke second [status|make|open|remove --yes] [--dry-run] [--json]`，与界面同参数（`tests/test_dispatcher.py` 钉住）。
- 验收脚本给第二个微信也指到一次性位置（`native_ui.py`、`render-current-guide.py`），不读本机真实副本。

## 实测（Mini，SIP 关闭，微信 4.1.15.22 / 270102 官网版 arm64）
- 引擎做出的副本与正在运行的主微信同时开 30 秒：主进程、WeChatAppEx 都在，无崩溃报告，数据写到自己的
  `~/Library/Containers/<包名>/`。对照：给副本主程序保留沙盒（不带腾讯应用组）→ 启动即崩。所以必须去沙盒。
- 去沙盒的副作用：副本把崩溃记录和日志写到 `~/Documents/app_data/`（聊天数据仍在容器目录）。已写进引擎 README。
- 已装的命令行 + 引擎在临时位置跑通「创建 → 重做（签名身份不变）→ 移除进废纸篓」；本机原有 WeChat2 未动。
- 引擎 `swift test` 63 项（新增 CloneTests 6 项）、GUI `tests/run.sh`（pytest 129 项 + Swift 各组）全过；
  离屏界面验收中英各 13 项。
- 本机已装含此功能的构建（版本号仍是 1.0.16，未升）。

## 没验证的
- SIP 开启的机器（同 #13）。
- 用新流程做出的副本扫码登录后的长期使用。本机现用的 WeChat2 是 9 月手工按同一思路做的（4.1.13），一直在用；
  界面现在显示它「落后」，本人点「更新副本」就是这条路的真实验证（聊天数据在包外不受影响，可能要重新扫码、
  重新授权截屏等）。没有替本人点。

## 待本人点头（对外）
1. 推送 WeChatTweak master（公开仓，2 个提交）。
2. appship 发 WeChatUnrevoke 1.0.17（升版本 + `docs/releases/1.0.17.md`，发布说明草稿见下）。
3. 在 WeChatTweak #11 回复并关闭（草稿见下）。Docket 尚无对应任务。

### 1.0.17 发布说明草稿
第二个微信 / Second WeChat
- 新增「第二个微信」（WeChatTweak #11）：一键做出一份微信副本（`~/Applications/WeChat2.app`），有自己的登录和聊天记录，
  可与原来的微信同时打开；不额外占磁盘，主微信不受影响、创建时可以开着。副本继承当前的防撤回状态。
- 微信升级后，界面会提示副本版本落后，点「更新副本」按新版重做；聊天记录在副本之外，不受影响。
- 「移除…」把副本移到废纸篓，聊天记录保留。命令行同步提供 `unrevoke second`。
- 限制：官网版微信须是已收录的版本（副本要能关掉内置更新器，否则下次更新后会打不开）；副本首次用到截屏、麦克风、
  摄像头时各授权一次。SIP 开启的机器尚待反馈。

### #11 回复草稿（发版后发）
@zhouyulong1 你好，这个功能做好了，放在图形界面版 WeChatUnrevoke 里：v1.0.17 起主窗口有「第二个微信」，
点「创建第二个微信」会在 `~/Applications/WeChat2.app` 做出一份副本，有自己的登录和聊天记录，可以和原来的微信同时开，
不用再手动复制整包，也不额外占磁盘。微信升级后点「更新副本」即可。只用命令行的话是 `wechattweak clone`（见 README）。

两点说明：副本要能关掉微信的内置更新器才留得住，所以官网版微信需要是已收录的版本；我这边是在 SIP 关闭的机器上验证的，
SIP 开启的机器如果遇到副本打不开，请把「复制诊断」贴上来。下载：https://github.com/zengtianli/WeChatUnrevoke/releases

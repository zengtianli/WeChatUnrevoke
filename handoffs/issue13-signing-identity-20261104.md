# #13 打补丁后微信截屏/录屏被拒 —— 改用本机固定签名身份（2026-11-04）

## 根因（实测）
- wechat.dylib 在微信主进程里调 `CGPreflightScreenCaptureAccess`；TCC 按签名的 designated requirement 认身份。
- ad-hoc 重签后 DR = `cdhash H"…"`，随内容变：同一份微信 silent ↔ keeptip 来回切，主程序 CDHash 在 `977a3b…` / `4a4887…` 间跳（副本实测）。微信升级后重打同理。
- 结果：系统设置里「微信」开关仍亮，但记录的身份已对不上 → 微信弹「录屏权限未开启」。麦克风/摄像头同机制。
- 未解释的一点：用户说「移除再加回」也没用；按此机制加回后应恢复。可能加回后又被重打/切换，或系统设置移除不干净。回复里请对方用 `tccutil reset` 验证。

## 修复（引擎 vendor/WeChatTweak 提交 ddc756c，本地，未推送）
- `LocalIdentity.swift`：首次打补丁在 `~/Library/Application Support/WeChatTweak/signing/signing.keychain-db` 生成自签代码签名身份（/usr/bin/openssl=LibreSSL；空口令钥匙串，0600；不进搜索列表；root 运行时归还 SUDO_USER/控制台用户）。DR 变为 `identifier "com.tencent.xinWeChat" and certificate leaf = H"…"`，重打/切换不变。
- `LaunchProbe.swift`：签完把 App 与内嵌 .app 的可执行文件以 POSIX_SPAWN_START_SUSPENDED 启动，让 AMFI 审一遍后立刻杀掉；任一被拒 → 自动退回 ad-hoc。本机实测：ad-hoc/自签 + 微信同款权限都通过；带 `com.apple.developer.*` 的被 SIGKILL（探针能识别）。
- DR 变化时 `tccutil reset ScreenCapture/Microphone/Camera com.tencent.xinWeChat` 清掉失效授权（`WECHATTWEAK_KEEP_PRIVACY_GRANTS=1` 跳过，测试/副本用）。
- `--signing local|adhoc`，默认 local；doctor 的 Signature 行写明身份类型。
- 测试：57 项全过（新增 DR 稳定性、探针接受/拒绝）。GUI `tests/run.sh` 全过（需 `PYTHON=~/Dev/.venv/bin/python`，系统 python3.15 无 pytest）。
- GUI 源码未改，`./build.sh` 重新内嵌引擎；已本机装到 /Applications/WeChatUnrevoke.app（1.0.15 版本号未升）。

## 未验证
- SIP 开启的机器：手头没有（Mini SIP 关；GitHub macOS runner 也是 SIP 关，私有临时仓 zengtianli/wechattweak-sip-check 的那次运行无效，可删）。探针在 AMFI 层把关，失败会自动退回 ad-hoc。
- 真实微信上「授权一次后重打补丁仍有效」的端到端：需要本人或用户实机点一次授权。

## 待办
1. 本人同意后推送 WeChatTweak master（公开仓）。
2. appship 会话发 WeChatUnrevoke 新版（内嵌新引擎）。
3. #13 回复草稿经本人过目后发；#12 关闭指向 #13。Docket T20261104-1 / -4。

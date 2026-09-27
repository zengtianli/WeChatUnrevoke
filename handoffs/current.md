# Chapter 固定验收交接（2026-09-28）

本轮仅补 `unrevoke-mac` 的 functionality、recovery、privacy、native_ui。使用 3 个并发子 agent，恢复项完成后接续隐私项；主 agent 集成、复核截图、执行正式验收并提交。未推送、发版、装机、部署或修改共享模块。没有重新做性能采样。

## 本轮改动

- `scripts/accept/_common.py` 提供 Xcode 环境、子进程与 detail 输出；四个同目录脚本独立、非交互运行。
- `tests/FunctionalityAcceptance.swift` 使用当前 AppModel/Engine 和真实内嵌引擎操作独立微信副本，独立 doctor 回读，复核来源关键文件未变。
- `tests/RecoveryAcceptance.swift` 验证 9 项真实控制器故障恢复，外部引擎用受控故障 fixture；从不批准退出真实微信。
- `tests/PrivacyAcceptance.swift` 验证 6 项真实配置请求与本地边界，URLProtocol 截获请求，系统沙盒禁止联网，使用隔离 home 与偏好；不代表 vendor 引擎内部审计。
- App 新增 `--ui-self-test`：真实 ContentView 离屏渲染，直接调用刷新/关闭路径；9 项断言、5 张 PNG。该入口只接受独立测试 bundle，不显示窗口、不合成输入、不使用剪贴板。正式 UI 外观不变。
- 本机 `project.yaml` 已登记四项 `sop.accept` 与 `ui_self_test_flag`。它按现有 `.gitignore` 约定只留本机；公开可复用的登记片段在 `scripts/accept/README.md`。

## 验证与证据

正式验收结果由 Chapter 写入 `perf/delivery-evidence.json`，主 agent 未手写。各项运行回执在 `perf/acceptance/`；这些目录开工前已有他人未跟踪产物，全部保留，不纳入本次提交。

主 agent 统一运行结果：四项全部 `passed`，且已复核证据文件与运行日志的 SHA-256。

| 验收 | 本轮实际结果 |
| --- | --- |
| functionality | 真实 build 269627 独立副本：还原基线 → `protected`（防撤回和拦截更新均 `patched`）→ `unprotected`；权限保留、写后刷新、来源关键文件不变 |
| recovery | 9 项运行时故障恢复检查通过 |
| privacy | 6 项网络请求/缓存/隔离数据边界检查通过 |
| native_ui | 9 项状态与动作断言、5 张离屏截图；主 agent 复核正常与最小尺寸 |

```bash
~/Dev/.venv/bin/python ~/Apps/chapter/engine/app_sop.py accept --app unrevoke-mac \
  --check functionality --check recovery --check privacy --check native_ui --json
~/Dev/.venv/bin/python ~/Apps/chapter/engine/app_sop.py run --app unrevoke-mac \
  --stage test --test-only --now --offline --json
```

回归测试已通过并绑定当前代码；实际 Xcode Debug 工程构建通过（`CODE_SIGNING_ALLOWED=NO`，产物仅在 `build/accept/xcode/`）。原始日志与本轮测试检查结果在 `build/accept/xcode-build.log`、`build/accept/chapter-test-result.json`。

原生截图已由主 agent 检查正常及最小尺寸，测试数据明确为 fixture。恢复/隐私通过仅覆盖回执所述路径；不声称已验证真实账号聊天撤回、系统授权弹框、Finder/Dock 图标或新安装版本。Chapter 已排队的只读重检留给 Chapter 执行；原性能数字仍属于既有 1.0.9 安装版，未改日期或冒充本轮采样。

本轮四项自动化缺项无剩余阻塞。测试阶段检查仍将源码变化对应的 perf/media/ship 标为待重检，不能把四项通过扩写成已安装、已发布或全部维度完整通过；后续只读重检沿 Chapter 已排队动作执行。

## 需要本人处理的前置材料

### 管理员免密摘要（本轮未重试 availability）

当前安装版 1.0.9，内嵌引擎 SHA-256：

```text
738c112e09e9c032a61adb348b1d4e20ca601937a26cdebb2e2bdcc1cf5c2bb4
```

进仓后先重新计算（以后装机会变化），再由管理员用 visudo 编辑原有规则中指向该引擎的 4 行摘要，保留原有命令范围，不能改成通配免密：

```bash
shasum -a 256 /Applications/WeChatUnrevoke.app/Contents/Resources/wechattweak
sudo visudo -f /etc/sudoers.d/claude-nopasswd
sudo visudo -c -f /etc/sudoers.d/claude-nopasswd
```

语法通过后，在不修改微信的前提下检查免密 doctor：

```bash
sudo -n /Applications/WeChatUnrevoke.app/Contents/Resources/wechattweak doctor --json
```

这条只证明已登记的 doctor 命令免密可用，不代替 patch 权限与后台自动重打实测；不要据此手改 availability 证据。后续重验仍需满足微信已退出、确曾成功保护、可写三个前提。

### 装机图标

正式源图 `icon/AppIcon.png` / `icon/AppIcon.icns` 保持不变，本轮离屏测试已使用正式图标。本人在 Chapter 确认实际 Finder/Dock 显示即可；本轮未装机，未替写 installed_icon。该项没有等价的 CLI 视觉验收，不把资源存在或哈希相同当成已确认。

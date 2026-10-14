# Unrevoke · 四项基础能力收口

2026-10-15 05:46（上海）；本轮仅 `unrevoke-mac` 的 product_basics 代码与候选验收阶段。派出身份 `--pid 52799 --session chapter-task:6c6b1b7f0463531e9420239d4c2972f5`，写前逐路径核 Chapter 原 claims，未另开、未释放。开工暂存/工作区为空，保留现有提交、后台和其他产品工作；没有推送、部署、发版、公证、上传更新源或安装应用。

源码提交：**`a59b679`**，精确 12 个路径：四份总部生命周期副本、AppShortcuts 副本、ProductLifecycle 产品工厂、ProductBasics 产品设置与进程内自检、UnrevokeApp 接线、pbxproj 两个新增源的四处接线、原 build.sh、固定 product_basics 验收器、startup 隔离域回归。共享生产实现仅经原 vendor-lifecycle 分发，未改总部、Chapter、其他产品或微信补丁引擎；发布物/站点/版本源未改。

## 实现与登记

- 设置：菜单「配置与更新…」接入真实产品偏好：防撤回提示方式、自动重打偏好；沿总部窗口/配置层导入导出、可选 iCloud 与更新设置。产品新增文案中英并排。修改只保存偏好并通知原模型，不执行微信写动作或申请权限。
- 快捷键：复用总部 AppShortcuts；默认应用内 ⌘R 重新检查，设置里可选择 ⇧⌘R/⌥⌘R、关闭/恢复。动作走原 `consoleRefresh`；保留组合、拒绝系统保留键和已有菜单冲突，CLI 的无效/重复参数先拒绝再决定写入。
- iCloud：同一真实产品工厂的白名单包含保护偏好、快捷键和更新选项；微信路径、成功保护状态、登录项、凭证、权限与业务记录不在迁移白名单。使用原 AppConfiguration 的同步、基线、恢复与备份，不复制同步引擎。
- 更新：刷新原共享 UI/CLI 到总部当前版，提供真实检查、获取/升级入口、自动行为选择和检查间隔；公开产品的正式源继续为原 GitHub 渠道。测试渠道仅在显式隔离环境且一次性验收 bundle ID 下启用，没有发布测试 feed。
- `project.yaml` 同时补齐 `sop.product_basics` 四项 entry/readback/inputs 与 `sop.accept.product_basics`。该文件按既有 `.gitignore` 作为本机内部登记保留，未强制加入公开仓；Chapter 实际读取并执行新登记。
- 原 `build.sh` 支持 `BUILD_ONLY=1`、指定独立 DerivedData 和候选输出，原常规流程保持；完整编译日志留原 build/，不再丢失被 tail 隐去的错误。复用已公开 ZIP 中已核 SHA 的 universal 引擎，不重编引擎。

## 当前真实候选与输入

候选（未安装）：**`/Users/tianli/Apps/unrevoke/build/product-basics/WeChatUnrevoke.app`**，bundle ID `io.github.zengtianli.unrevoke`，实际 **1.0.13 (111)**，当前 Mac 原生 Release GUI + 原 universal 引擎。111 来自原构建入口的 git-count，不是已发布 build；正式公开发行与已装应用没有替换。

真实构建回执：**`build/accept/product-basics-build.json`**，由原 `app_sop.py build-receipt` 包围实际成功构建写出，未补写或伪造。源码输入为 `Sources/**`、Info.plist、icon/**、Unrevoke.xcodeproj/**、build.sh 及原登记外部输入；构建前后源码一致，候选的可执行文件/图标/身份均核回执。

| 对象 | SHA256 |
| --- | --- |
| 候选 Contents/MacOS/Unrevoke | `7e93f5b1e8c7eb436b16e4efa9e70ef74c3604420883da6e5315a1b2fea0b9ba` |
| 构建源码输入 | `6073c783cbe6312de1f1d71e01b3bcf960405592d93a85db1d89da3fb2bbed5d` |
| build-receipt | `e6fbc697eb132b395a92981580a7b126bd092f807cbfa06a5b442bdbddd8ba46` |
| 固定验收原件 raw.json | `8bf4e03ebdab0e96c5a1d886349bfd6a2886a36caa26d7827d7509f95cd9af24` |

原构建命令（Chapter receipt 的实际 build-command）：

```sh
BUILD_ONLY=1 CONFIG=Release \
UNREVOKE_PREBUILT_ENGINE="$PWD/build/product-basics-input/wechattweak" \
UNREVOKE_DERIVED_DATA="$PWD/build/product-basics-derived" \
UNREVOKE_OUTPUT_APP="$PWD/build/product-basics/WeChatUnrevoke.app" bash build.sh
```

## 实际验收与原件

最终真实执行并退出 0：

```sh
cd /Users/tianli/Apps/unrevoke
UNREVOKE_BASICS_APP="$PWD/build/product-basics/WeChatUnrevoke.app" \
UNREVOKE_BASICS_RECEIPT="$PWD/build/accept/product-basics-build.json" \
chapter sop accept --app unrevoke-mac --check product_basics --json
```

固定脚本另提供 `--app`/`--receipt`；未显式给候选时仍验 `/Applications/WeChatUnrevoke.app` 与原装机回执。`artifact_scope` 明确为 **candidate-not-installed**，不把候选写成已装版。必须有真实、当前来源的 receipt 和有效完整签名才能启动隔离副本；来源不符直接拒用。

最终 Chapter 返回 `ok=true`、product_basics `status=passed`、`method=real_product`。政策来自原 PRD 和 `engine/product-basics.json`，**14 个 required_checks 逐个全部为严格 true**；总共 **31 项实际断言、45 次产品进程调用**。`perf/delivery-evidence.json` 由 app_sop 自己写入，未手写通过证据。

- 原验收记录：`perf/acceptance/run-s0op8inr/product_basics.json`，SHA256 `b3e3659df81869b3ea4fb4926d4e587c0a4b9ef2747f14d268bf9f661646d2c5`。
- 原件：`perf/acceptance/product-basics-224f57aa86774932ad77c9618994fdda/raw.json`；逐项 checks、产品 stdout/退出码、真实候选身份/回执/来源均保留。
- 真实设置浅/深离屏 PNG、进程内 UI checks/状态文字与日志在同一 run 的 `ui/`。不使用 CGEvent、AppleScript、模拟按键、剪贴板或前台窗口；`.prohibited`、全部窗口非 visible/key 的断言通过。
- 设置：真实控件 target/action 修改偏好，新进程读回；真实导出→合法导入→读回，坏 JSON 导入拒绝并核原配置字节相同。
- 快捷键：真实菜单 action 发出原刷新动作，真实 keyEquivalent/修饰键、关闭清空/恢复和新进程持久读回；保留组合/菜单冲突实际拒绝；错误 CLI 参数拒绝且配置不变。
- iCloud：隔离目录中的实际推送、第二个隔离本机配置域首次拉取、远端编辑应用；不可用时仍可本地读回，坏文件拒绝后修复可恢复；关闭保留两份数据。同步接收通过真实 reconcile，不拿幂等 `on` 的返回值当拉取完成。
- 更新：窗口真实控件调用原 checker 并显示测试发行结果，选项控件动作和新进程持久化；缺源/坏源实际失败后恢复。真实共享安装器对一次性 App 副本执行 ZIP/SHA/签名/版本验证和替换，升级后再次读取设置、快捷键及更新选项均保留；测试版本仅为隔离 fixture，没有替换正式 App 或发布更新。
- 生产保护：验收前后真实已装 App 文件与本机产品配置/偏好摘要一致，原候选与源码输入仍匹配回执；没有执行微信补丁、登录项或权限注册。

初次失败原件保留：本产品测试适配把本地 feed 当成 HTTPS manifest，被共享 checker 正确拒绝；改用已有隔离 privateCloud 测试渠道后检查真实成功。另一次测试把幂等 `sync on` 当作重新拉取，改为原产品实际 off→on reconcile 后远端值才应用。没有修改共享闸、政策、必测项或伪装成功。

## 必要回归与后续阶段

- `bash tests/run.sh` 最终退出 0：**60 项 Python 测试**和三组 Swift 回归全部通过，含登录命令 83 个 fixture 断言，无真实登录项注册。startup 回归沿产品实际 bundle ID，新增隔离偏好域，保留早期生命周期防崩溃语义。
- 原 vendor-lifecycle `--check` 确认五份共享副本逐字节一致；`bash -n build.sh`、`git diff --check` 通过。
- 验收/构建产物、receipt、delivery-evidence 和本机登记保持原忽略策略，不入本轮公开源码提交；保留原凭证扫描/提交消息钩子，手工提交单次省掉自动两机推送的 post-commit，未改全局配置。

**本轮代码与当前源码候选的 14 项行为验收完成，未安装。** Chapter 后续独立 install 阶段沿原产品装机流程执行，再由默认固定验收器核实际已装版；不得把上述候选通过称作装机完成。iCloud 当前证明的是本机两个隔离配置域之间的真实目录同步、回落与恢复；**Apple 服务器跨设备上传/下载未验证**，不能据此称另一台设备已收到。两者均是本轮范围说明，不需用户手工确认，也未追加其他旧 SOP。

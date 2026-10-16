# Unrevoke · 四项基础能力收口

## 已装版接续 · 2026-10-15 06:03（上海）

本阶段得到 Chapter 的一次本机快装授权，派出身份更新为 `--pid 3831 --session chapter-task:6c6b1b7f0463531e9420239d4c2972f5`；沿原 claims 逐路径核写入，没有另开或释放声明。只改产品配置核心/GUI 接线、原构建日志模板和本 handoff；没有改共享实现、引擎、站点、正式发行版本或更新源，没有推送、发布、部署、公证或上传。本节是当前已装结果，下文保留前一阶段候选的历史事实。

源码提交：**`0ca4033`**，仅 `Sources/ProductLifecycle.swift`、`Sources/ProductBasics.swift`、`build.sh`。配置核心继续由原 CLI 构建复用，GUI 命令接线移到原 GUI 文件；快捷键迁移键通过实际 App 自检核总部 schema 一致。修正 macOS `mktemp` 要求模板末尾为 `XXXXXX` 的重复构建故障，原旧日志保留，没有删除其他会话产物。

沿原快构建入口产出当前源码候选，再沿原本机装机入口保留现有组件完成 **一次安装**。实际 `/Applications/WeChatUnrevoke.app` 为 **1.0.13 (113)**、bundle ID `io.github.zengtianli.unrevoke`，原生 arm64；113 是本机原入口的构建号，正式公开发行未变。最终包使用本机可用的 **Apple Development 稳定开发者证书**，`codesign --verify --deep --strict` 通过，designated requirement 绑定证书身份与原 bundle ID，未以 ad-hoc 包替换正式运行版；测试副本继续仅在隔离目录签名。

原 `app_sop.py build-receipt` 包围实际签名与原装机步骤写出 `perf/build-receipt.json`，装后及源码提交后按原 verifier 核实际可执行文件、图标和当前输入；候选编译回执也保留。没有手写来源回执。

| 当前已装对象 | SHA256 |
| --- | --- |
| Contents/MacOS/Unrevoke | `f26ab3a776ffd50e26ed7324b0f8efc2d768c96d7de54e5c612644a43bb67a77` |
| 实际源码输入 | `d79143da5c518bb997aa25c0bf49d5d397158019306dd123d9ac98bfb3e5f909` |
| 原装机 build-receipt | `0baeef016b2fe98a0bd8bedf198041c912cd0dd36b70ccc687eae55141d21949` |
| 已装版固定验收 raw.json | `3b1e904ab6ea0ad01cb2fbdfc5ddf0d3a44c5b52b4185e1c84550362c00be968` |

实际执行默认已装版入口、退出 **0**（未指定候选环境变量）：

```sh
cd /Users/tianli/Apps/unrevoke
env -u UNREVOKE_BASICS_APP -u UNREVOKE_BASICS_RECEIPT \
chapter sop accept --app unrevoke-mac --check product_basics --json
```

Chapter 返回 `ok=true`、`passed`、`method=real_product`，原件 `artifact_scope=installed`；**14 项必测行为全部严格 true，32 项实际断言、45 次实际产品进程调用**。原记录 `perf/acceptance/run-7ti0_1r9/product_basics.json`，SHA256 `90e5c32315805c2855645cc2eab6f089cb83941f3edaf0194b8e3b596a79153f`；raw 原件 `perf/acceptance/product-basics-70aad27071d94f14a662b48728a31e30/raw.json`。`perf/delivery-evidence.json` 仍由 Chapter 写入，没有手写通过证据；另一轮 app_sop 正在运行的提示仅说明总报告刷新由原任务回读，不影响本次已写出的验收原件。

安装后核原用户配置项 SHA 与装前一致、原引擎 SHA 未变、原命令链接未变、原后台仍为原 PID/启动时间，旧版与旧 receipt 保留可回溯。登录项用正确的 `--login status --json` 读取，返回与装前一致的 `notFound/service_unavailable`，未调用注册/注销；系统 TCC 只读查询无本 bundle 的既有辅助功能/App 管理授权记录，未写权限数据库。

读回注意事项：一次登录项读回误用了 `login`，进入普通 App 启动路径，发现后仅终止本轮进程；它新增了 `appUpdateState` 检查缓存。先核从当前偏好去掉这一新增键后可精确恢复装前 SHA，再只移除本轮新增缓存，当时完整偏好摘要一致；没有合成输入。随后观察到该进程退出后仍有新的更新检查历史写入，最终保留这份动态缓存，没有继续覆盖其他后台动作；排除仅这一运行历史键后，全部原用户配置的 SHA 仍与装前精确一致。固定 product_basics 验收自身全部为隔离离屏窗口，`no_visible_windows_or_dock` 为 true，不把这次读回误启动称作离屏验收。

回归：本阶段 `bash tests/run.sh` 退出 0，**60 项 Python 测试、三组 Swift 回归、登录 CLI 83 个 fixture 断言**通过；当前源码 GUI 与原 CLI 实际构建均通过，`bash -n build.sh`、`git diff --check` 通过。只提交三个源码路径与本说明；本机登记/回执/证据沿原忽略策略保留，单次提交保留原凭证扫描与消息钩子，省掉自动推送 post-commit，没有修改全局配置。

**本产品四项实现和默认已装版验收已完成，无需用户补测。** iCloud 已验证真实产品在本机隔离目录的同步往返、不可用回落和损坏恢复；**Apple 服务器跨设备传输未验证**。本轮只执行获授权的一次本机安装，仍未公开发布或部署，不扩大其他旧 SOP。

## 前一阶段 · 当前源码候选（历史记录）

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

## 发行产物与构建回执

固定验收先核最终产物与原构建回执；绑定不一致时先沿既有构建、交付与安装流程查清原因，再执行同一条验收。不放宽摘要核对，也不用历史批次的通过覆盖当前产物。

公开版本继续沿现有 ad-hoc 签名与发行流程。回执维护不改变签名身份；本机配置、自用构建和验收现场继续保存在私有维护入口。

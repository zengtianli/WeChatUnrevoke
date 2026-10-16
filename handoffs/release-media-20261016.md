# 2026-10-16 · 当前构建发行与素材接续

## 第二轮接续（2026-10-16，进行中）

本次复用 Chapter `--pid 89000 --session chapter-task:ff67e3f3a11940a59cf9f049cb215584` 的声明，原声明不释放。以下新接口和结果覆盖下文上一轮的资源门阻塞与恢复步骤：直接调用 `sim_lane.build`，由其内部并行槽准入，不再套 FIFO/acquire/heavy_builds，也不以压力 2 中止。

本轮具体写入范围：原 `build.sh` 的 SDK 接口及独立后处理、`release.sh` 显式产物路径、Release 工程的 universal 设置、离屏导览生成器及三屏复核原件/元数据、专项测试、本 handoff；不改共享 SDK、Chapter、引擎、产品业务界面或旧实机录像。完成标准为真实三屏复核、原完整发行门通过、新 GitHub 发行与 cask/网站回读、必要本机来源对齐和原更新源回读；不重复 perf，不重发已存在 Release。

三屏离屏渲染已完成，`docs/demo/reviews/20261016/` 保存新图与真实差异统计，旧视频 SHA 保持 `8123a2dc9934ee9b328dd3a316a1c614c4f98904e4f7f1d87b63e71f6c89ad9f`。五个展示源码逐一与原记录相同；视觉检查三个状态的布局、文案、控件与行为相同。新图 sRGB、旧图 Display ICC，存在色彩/栅格差异，不称像素一致；复用仅限已展示范围，设置/快捷键/iCloud/更新窗口不在导览中。复核绑定当前原 Chapter 的 UI 输入摘要。

SDK 接入首轮定位并修复两个真实问题：输出/预构建引擎变量不得传入源码隔离器；新接口不接原命令行 universal 参数，因此 Release 工程明确 arm64+x86_64 和 ONLY_ACTIVE_ARCH=NO。保留原包内 12 项白名单、签名、引擎、双架构及真实启动门；SDK 原始产物不修改，后处理只用副本。新的复用选项只经 SDK `reuse_build` 校验当前源码和二进制，不接受仅有 receipt 的缓存。

此处尚未宣称新发行完成，最终回读见本节后续结果。

补充：仅把 ARCHS 写进工程仍被 SDK 的 `platform=macOS,arch=arm64` 本机 destination 收窄；已明确为 universal 产品构建选择 SDK 的 `generic/platform=macOS` destination，仍直接调用原 `sim_lane.build`，不改共享文件。此原因改变后才重新构建；两次单架构候选均被原门拒绝，未上传。

本轮任务：Chapter `6835da139e6c4eaa926df5b6b68064e5`，仅 unrevoke-mac 的 media、release、update-feed；性能及 input-binding 留原调度，不重复采样。写前复用 `--pid 47746 --session chapter-task:6835da139e6c4eaa926df5b6b68064e5` 核原 claims，不另开或释放声明。开工工作区/暂存为空，保留已有提交和后台。

有限步骤与完成标准：

1. 回读装机/原 receipt/正式 GitHub，预计 5–10 分钟；已核已装 1.0.13 (116) 与当前输入匹配，公开 1.0.13 (99)。
2. 用户指定渠道的产物与回执保持在本机原登记和忽略目录，不写入公开材料；沿原发布器与既有身份边界，不改签名政策、不新增绕闸。
3. 按实际变化复核既有教程，预计 10–20 分钟；当前 ContentView/模型/引擎显示源码未变，设置及生命周期接线变化，先核对真实离屏画面。原实机录像保留历史版本和范围，不将虚构状态导览称为补丁操作录像。
4. 公开发行递增 1.0.14，沿原 release.sh/publish.py 测试、universal 打包、白名单、签名与双架构启动门，预计 15–30 分钟；原队列/构建锁冲突由原调度接续。推送前审阅领先提交与触发器，执行原隐私扫描；GitHub 草稿下载核 SHA 后正式发布，Homebrew 与站点沿原流程回读，站点只由 Lintel 发布。
5. 收尾按受影响范围用固定验收和 Chapter 只读整体重检；已通过项复用，不重测无关旧项。写实际提交、线上版本、原件和剩余步骤；不送 App Store 审核，不触碰真实微信写入、用户配置、其他组件服务或后台。

本轮所有发布仍需完成后分别记录，不把预检或本地构建称作已发布。

## 前置检查（尚未发行 1.0.14）

- 当前准备文件仅 Info.plist 的 1.0.14 版本递增、对应双语 release notes、原导览生成器的仅截图对比选项、素材范围说明和本 handoff；App 生产 Sources 未改。
- 原隐私发行扫描通过，当前公开源码/原公开包白名单无命中；发布预检回归 2 项、启动门回归 4 项通过。快照模式拒绝直接写正式素材目录的实测退出 2，通过预期的破坏性输出防护。
- 本仓无 ci_scripts、GitHub workflows 或 Xcode Cloud 脚本，GitHub API 回读 Actions 0 条、webhooks 0 条；Homebrew tap API 回读 Actions 0 条。原 publish.py 的明确对外步骤仍为源码 push、新 Release、对应 cask 更新及 Lintel 站点发布，不触发 App Store 送审。
- 三张当前视图编译/对比接原 sim-lane FIFO 与门槛；初次准入等待 60 秒后返回 75，未启动渲染或编译。现接同一资源队列等待，不改锁持有者或门槛；其他产品构建、常驻进程和原素材均保留。

## 本轮结果与接续（2026-10-16 16:50）

**已交付：** 本轮选定的更新渠道沿原发布入口完成，manifest、包大小/SHA、ZIP 内身份/版本/主程序与实际装机逐项一致，产品自身检查更新也读到本机当前构建；未声称另一设备已收到。详细原回执保留本机忽略的 `build/personal-publish-20261016.log`，不公开该构建或安装内容。Chapter 原 `run --app unrevoke-mac --check-only --json` 退出 0，明确将 update-feed 判为 ok，原件 `build/release-media-final-check-20261016.json`；没有手写 delivery-evidence。

源码准备提交 **`fd950be`**，精确五个路径，尚未推送。两组专项回归共 6 项、原隐私检查 46 项、共享生命周期五份副本 `--check`、Python AST 和 `git diff --check` 通过；完整发行测试/双架构构建未开始，不称本轮完整验收通过。

**受阻：media 与 release。** 原 FIFO 曾轮到本产品，但准入读到内存压力等级 2（要求 1），退出 75；接回原门作 180 秒有界等待后仍为 2，再次退出 75。两次均未启动渲染或任何 SDK 编译，未改压力阈值、未取消其他队列/后台。本轮不在同因不变时继续重试。原素材字节、公开 GitHub 1.0.13 及其资产、Homebrew 和线上站点均未替换；本轮未安装、未 push、未部署、未送审。1.0.14 只是已提交的准备版本，media/release 仍未通过。

编译环境恢复后，由原 Chapter 再派本产品接续（不扩大旧 SOP）：

```sh
cd /Users/tianli/Apps/unrevoke
chapter agent-send --app unrevoke-mac --fix-stage all --message '接续 handoffs/release-media-20261016.md，仅完成 media、release 和新版本装机后的原更新渠道同步；先核原 sim-lane 的内存压力恢复至 1，复用 FIFO/负载/编译竞争门，不重测 perf；先真实三图对比后原 publish.py，失败只续缺失阶段，不重发已有 Release。' --json
```

后续固定执行入口和约束：

1. 沿原 sim-lane FIFO 包围 `python3 scripts/render-current-guide.py --snapshots-only --out build/media-review-20261016`；实际生成三张离屏视图后逐像素/视觉对比原 `current-*.png`。只有确实相同才由真实对比原件生成 `current-guide.json` 的 reused_for/ui_reviews，绑定原 app_sop 的当前 UI 输入摘要，保留原视频 SHA、原拍摄时间和「不演示配置窗口」范围；若有实际画面变化，仅更新受影响部分，不手写 unchanged 或重录整套录像。
2. 公开引擎已从官方 1.0.13 ZIP 核摘要/大小后提取为 `build/release-input-20261016/wechattweak`，出处与 SHA 在同目录 provenance.json；原公开引擎仍为 ad-hoc、universal，config.json 与当前原版相同。**不要用本机带开发者签名的引擎替代公开字节。** 公开发布时沿原队列运行 `UNREVOKE_PREBUILT_ENGINE="$PWD/build/release-input-20261016/wechattweak" python3 scripts/publish.py docs/releases/1.0.14.md`，先查是否已存在该 Release；原隐私闸、测试、ZIP 白名单、双架构启动门、草稿下载 SHA 与 cask 回读均保留。当前只是准备，无新包可上传。
3. 源码/素材先完成必要检查并限定提交，推送前重读领先提交和原隐私扫描；当前 Actions/webhook 读取结果见前节，不为恢复而 force。网页交原 Lintel ship/check，不能直接 deploy-site.sh；发布器非零先查 GitHub/cask/正式 HTTPS，已公开部分不重做。
4. 新版本出来后沿原本机安装入口保留原安装内容与引擎摘要，回读真实 build-receipt、版本和后台；按用户要求运行固定 installed_icon，以及构建变化造成失效的必要固定验收，再发布实际已装版本的原更新渠道。不把公开包覆盖安装到原有本机变体，不将本机叠加内容放入公开 ZIP。
5. 收尾再读原 Chapter 整体状态，只补本轮真实变化引起的必要回归；perf/input-binding 仍由原采样队列处理，不把环境 75 改为通过。

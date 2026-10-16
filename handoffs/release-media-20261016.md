# 2026-10-16 · 当前构建发行与素材接续

**收尾完成（2026-10-16 18:41）**：本轮三项 media、release、update-feed 已由 Chapter 原检查读为 ok；公开与装机同为 **1.0.14 (123)**。以下保留中间失败的真实记录，旧的资源门阻塞和「尚未发布」段落均为历史过程，不是待办。最后接续使用 Chapter `--pid 63153 --session chapter-task:ff67e3f3a11940a59cf9f049cb215584`，未释放其声明。

## 第二轮接续（2026-10-16，已完成）

本次复用 Chapter `--pid 89000 --session chapter-task:ff67e3f3a11940a59cf9f049cb215584` 的声明，原声明不释放。以下新接口和结果覆盖下文上一轮的资源门阻塞与恢复步骤：直接调用 `sim_lane.build`，由其内部并行槽准入，不再套 FIFO/acquire/heavy_builds，也不以压力 2 中止。

本轮具体写入范围：原 `build.sh` 的 SDK 接口及独立后处理、`release.sh` 显式产物路径、Release 工程的 universal 设置、离屏导览生成器及三屏复核原件/元数据、专项测试、本 handoff；不改共享 SDK、Chapter、引擎、产品业务界面或旧实机录像。完成标准为真实三屏复核、原完整发行门通过、新 GitHub 发行与 cask/网站回读、必要本机来源对齐和原更新源回读；不重复 perf，不重发已存在 Release。

三屏离屏渲染已完成，`docs/demo/reviews/20261016/` 保存新图与真实差异统计，旧视频 SHA 保持 `8123a2dc9934ee9b328dd3a316a1c614c4f98904e4f7f1d87b63e71f6c89ad9f`。五个展示源码逐一与原记录相同；视觉检查三个状态的布局、文案、控件与行为相同。新图 sRGB、旧图 Display ICC，存在色彩/栅格差异，不称像素一致；复用仅限已展示范围，设置/快捷键/iCloud/更新窗口不在导览中。复核绑定当前原 Chapter 的 UI 输入摘要。

SDK 接入首轮定位并修复两个真实问题：输出/预构建引擎变量不得传入源码隔离器；新接口不接原命令行 universal 参数，因此 Release 工程明确 arm64+x86_64 和 ONLY_ACTIVE_ARCH=NO。保留原包内 12 项白名单、签名、引擎、双架构及真实启动门；SDK 原始产物不修改，后处理只用副本。新的复用选项只经 SDK `reuse_build` 校验当前源码和二进制，不接受仅有 receipt 的缓存。

此处尚未宣称新发行完成，最终回读见本节后续结果。

公开候选 1.0.14 (121) 已由 `sim_lane.build` 构建 universal GUI，并用原 `app_sop build-receipt` 写 `build/accept/public-candidate-20261016.json`。第一次固定 product_basics 真实验收定位到 Xcode 27/AppKit 延迟启动在事件循环后恢复 LSUIElement 激活策略，离屏条件失败；仅在自检入口补 `finishLaunching` 后重新固定 prohibited，并增加窗口/策略原始诊断，未削弱断言或改变用户窗口流程。源码原因改变后重建，`chapter sop accept --app unrevoke-mac --check product_basics --json` 的候选模式通过，证据由 Chapter 写 `perf/acceptance/run-bcbodw3q/product_basics.json`。原推送前隐私扫描 46 项再次通过。

SDK 的 `reuse_build` 实测拒绝 form: mac 自身线（错误来自共享 `lane_inputs` 的测量绑定限制）；本轮不改共享代码，也不使用该可选缓存入口。原发布器与本机底包构建均直接经 `sim_lane.build`，保留所有原门，不把单元测试假文件当真实缓存可用证据。

原 publish.py 首次完整测试通过（63 项 Python，三个 Swift 套件含 83 项登录 fixture），但原 release.sh 的 `/bin/bash` 3.2 解析 SDK 的双引号 heredoc 替换遇到注释中的单引号而退出 2；候选使用 PATH 的新版 Bash 未暴露。此时尚未构建发行包、push 或创建 Release。修正为赋值自身已保留空白的命令替换，并增加系统 `/bin/bash -n` 专项回归；仍沿原入口再次完成必要发行门，不绕过测试。

### 已正式公开 1.0.14 (123)

源码冻结提交 `e888bbe476afd57ed5e8694a29e0e8f0f80d2113`，原发布器完整 64 项 Python 与三个 Swift 套件通过，公开包 exact 12 项、strict/deep 签名、双架构引擎/GUI、arm64 与 x86_64 各 8 秒实际静默启动通过；主程序没有安装到真实微信路径，也没有任何 patch/restore。

- 正式 Release：<https://github.com/zengtianli/WeChatUnrevoke/releases/tag/v1.0.14>，draft=false，target 为上述冻结提交；未重发或覆盖已有 Release。
- 唯一公开 ZIP `WeChatUnrevoke-1.0.14.zip`，**3,037,994 bytes**，SHA256 **`e677b6f5314e7c9ce57a8f7c74e7f481d29472ec8e12dfac618212730fd31fa9`**；草稿下载逐字节 SHA 门与正式 GitHub digest/size 回读一致。
- 公开引擎保留 SHA256 `61efbc17fc1aed5f31dac97853d6ad9062ddebe8e5e924aa9b1f085d2c5a85b6`，仍为 ad-hoc/universal；未加入本机叠加内容、开发者签名引擎或新公证。
- Homebrew cask 已由原发布器更新到 1.0.14，version/SHA 回读匹配；本轮源码领先提交均为本任务，推送前已审阅，Actions 0/webhooks 0，不触发 App Store 送审。
- 原发布器随后退出 3，仅站点阶段失败。已定位为旧导览复用记录原要求是带 build/SHA/source map 的对象，本轮最初写成文字；修正真实记录并保持严格闸，错误类型输入改为明确拒绝；4 项专项回归和原 build contract 18 项通过。中英 README 仅将旧表明确标为 1.0.13 (99) 历史实测与 1.0.14 待测，未重测或改原数字。
- `scripts/build-site.py` 重建 `dist/site` 成功，原 Lintel `site check --site unrevoke --out dist/site --json` 为 ok，站点没有安装包。正式站点尚待下面的原 ship 单独接续；**不要重跑 publish.py**。本机底包已构建为同一 1.0.14 (123)，后续只走原安装事务与真实回执。

### 最终回读与范围

- 原 Lintel `site ship --site unrevoke --work ~/Library/Caches/unrevoke-site-ship --json` 已单独接续成功，`shipped=true / published=true / verified=true`；桌面与窄屏 1 页、3 段视频及字幕经过原 capture/review，正式 HTTPS **20/20 文件 SHA256 一致**，无 mismatched。原回执为本机忽略的 `build/site-ship-1.0.14-20261016.json`，构建目录仍为 `dist/site`，正式页 <https://unrevoke.tianli.cyou/>。站点只提供 GitHub Release 获取入口，没有 ZIP/DMG/App 等安装包镜像，教程样例与视频保留。
- 原本机事务已完成同版 **1.0.14 (123)** 安装，bundle 身份、原安装内容与引擎摘要保留，strict/deep 签名和真实 build-receipt 匹配；未改登录项、用户配置或常驻服务，登记后台回读仍在运行。安装/所选更新渠道的详细产物与摘要只保留本机忽略目录和原私有入口，不加入公开 ZIP 或受控交接材料。
- 实际已装版再次通过原 `chapter sop accept --app unrevoke-mac --check product_basics --json`：四项功能 **14 项必测、32 个原始 checks、45 次真实命令**，所有 checks 为 true；原 `installed_icon` 固定离屏验收通过。证据均由 Chapter 写入，不手写 delivery-evidence。iCloud 功能证据是本机隔离传输，未声称 Apple 跨设备传输通过。
- 原更新发布器已对实际装机发布同版，manifest、包字节数/SHA、包内主程序与装机一致，App 自身 `update check --json` 返回 1.0.14 (123) / up_to_date。只确认本机提交和回读，未声称另一台设备已收到。最初普通 check-only 复用了旧阶段缓存；确认真实 feed 输入已从旧版变化后，沿原 `run --stage ship --retry --check-only` 只刷新发行观察，没有重复发包。
- 最终 Chapter 回执 `build/release-media-final-ship-check-20261016.json`：**media / release / update-feed / install / build-receipt 均为 ok**。源码发行提交 `e888bbe`、页面/复用记录修复 `0e74329` 已推送；GitHub 正式资产仍为上述唯一 SHA，无重复 Release、重签公证或 App Store 送审，未改任何共享组件代码。
- 本轮真实测试是原完整发行 **64 项 Python + 3 个 Swift 套件**，以及页面修改后的原 build contract **18 项**与新增导览合同 **4 项**，均通过；原隐私发行扫描 **46 项**通过。Chapter 的测试登记缓存仍显示 stale，未以手写状态冒充登记；原队列后续可用 `chapter sop run --app unrevoke-mac --test-only --json` 记录。性能和其输入绑定的 stale 保留原采样队列，本轮明确未重测；不把这些既有提醒追加为本轮三项结束条件，也不声称全部 SOP 已绿。

本轮有限范围已完成，没有需要本人决定或操作的事项。后续不要重新运行 App 发布器；仅按原队列处理测试登记和性能采样。

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

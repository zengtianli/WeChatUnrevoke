# Chapter 源码与测试交接（2026-10-08）

## 2026-10-08：当前构建装机

本人授权安装一次后，已装 **1.0.11 (74)**，包内主程序与构建来源回执的 SHA256 一致；bundle ID、原引擎摘要、偏好和既有常驻配置保留，没有操作真实微信写入或退出。

固定验收由 app_sop 执行并写证据：installed_icon、cli_entry、agent_cli、native_ui 全部 passed；命令对照 26 项中命令 21 项、真人/窗口 5 项、暂缺 0 项，原生自检 9 项 / 5 张离屏截图。八项登记已据已装入口改为 command，没有手写通过记录。

本轮只完成本机安装，没有发布、推送或推广页动作；配置和回执沿原入口保留，后续阶段由 Chapter 重检。

## 2026-10-08：命令模式与诊断记录源码

本轮仅修改源码和测试，本地提交；没有装机、发版、推送或部署，未修改签名身份、bundle ID 和公开范围。

- 共享生命周期命令层通过总部 vendor 脚本取得逐字节副本；`ProductLifecycle` 统一界面与命令使用的配置白名单（仅 variant / autoRepatch）和更新渠道。
- 包内主程序新增 `--login status|on|off` 命令模式，界面启动前分派；写入需要显式确认，支持 JSON 和 dry-run，系统需要批准时只报告状态，不打开窗口或设置。
- 界面写入完成并刷新后，保存原始引擎日志与写入错误；本机记录采用 0700 目录 / 0600 原子文件，不参与配置导出或同步，读取和保存错误不替代真实写入结果。
- Xcode 工程及独立编译入口已接入新源文件；现有写后无条件体检及引擎单一判决规则保留。

Mini 在独立快照中执行本仓测试：23 项 Python、15 项 Swift 运行检查、83 项登录断言、6 组日志检查全部通过；Xcode Debug 工程未签名编译通过。没有使用真实登录项登记、剪贴板、微信写入或退出动作。

收尾续轮再次核对当前代码与测试快照一致，并重跑 `tests/run.sh`，退出 0；只提交本轮上述源码、测试、编译接线和交接。原 Chapter 写入声明继续由 Chapter 持有，没有自行释放。

安装版尚未包含本轮入口，登记继续保持 missing，原因已更新为源码就绪但未装机；这轮不把源码测试扩写为装机验收。复验入口仍为 `bash tests/run.sh`，后续装机必须沿现有授权和回执入口。

本轮复用 Chapter 原 pid/session claims 身份，不自行释放其声明；保留开工前已有改动。

## 2026-10-01 无人值守资源实测登记

- 起因：版本一变，Chapter 的自动测量就报「启动测量缺少 App 路径」（`sop.measure` 只有 `inputs`）。现在本机 `project.yaml` 登记了 `archive: release`、`start_args: ['-autoRepatch', 'NO', '-everProtected', 'NO']`、`in_use: true`，公开示例见 `scripts/accept/README.md`。
- 共享改动：Apps 仓 `8073ace`（共享测量脚本把 `start_args` 带到每次冷启动并在方法里写明；参数格式不对就在解包、启动之前失败；解出的发行副本测完从 LaunchServices 注销并删除；副本也记 `measured_artifact`）；Chapter `ec9e41b`（发布记录写了本地 `download` 时就测这一个文件，且须与记录的 sha256 一致）。
- 隐藏启动实测（`in_use` 的依据）：一次单独试启动，加上正式测量全程的被动观察（只读窗口列表和前台 App，不碰输入）。副本的主窗口创建了，但从未上屏、从未成为前台 App；子进程只有 `wechattweak doctor`（正式测量 5 次启动各 1 次），没有 sudo/osascript；微信包 5 个路径的指纹、本 App 偏好前后不变；测完无残留进程，副本已删除。
- 正式测量走 Chapter 自己的测量动作（`app_sop.measure`，持全局锁，过采样门），提交 `acd7cb4` 并推送：1.0.10 (34)，空闲 33.0 MiB（页面 34.6 MB）、CPU 0.0%，冷启动到窗口出现中位 289 ms（5 次），安装包 2,449,790 字节。标签从 `1.0.10` 变成 `1.0.10 (34)`，按共享规则旧的状态检查计时、30 分钟检查折算 CPU、后台任务记录移入 `history`；之后每次换版本都会这样。
- 产品页生成器原先写死了人工测量才有的字段（`cold_start_to_status`、`background.status_check`、`cpu_pct_with_checks`），也按字符串比较 `1.0.10 (34)` 和 `1.0.10`，自动实测后建站失败。现在所有数字都取自共享渲染器的摘要，版本按发行号比较；新增回归测试用自动实测的证据格式建页。README 正文里写死版本和日期的那句改成不带版本，版本和日期只留在生成块里（测试同步改）。`perf/lightweight.json` 的 `data`/`data_en` 改成不带版本号的测量说明。
- `chapter sop run --app unrevoke-mac --stage perf --now --json`：perf、size、budget、speed、test 都是 ok，没有 input-binding 失效项。

## 2026-10-01 免密复核

- 管理员已于 2026-09-30 刷新 `/etc/sudoers.d/claude-nopasswd`（文件时间 09-30 10:53）；`perf/lightweight.json` 的 `availability.local_unattended_engine` 当日已记为 `verified`（以 root 对微信副本真实 patch 并核验）。
- 本轮复核：`sudo -k` 后 `sudo -n <已装引擎> patch --help` 不要密码、退出码 0；已装引擎 SHA256 仍为 `738c112e…`。现有证据比这次只读复核更强，未改实测文件、README 和页面，因此没有新的部署。下文「管理员免密引擎摘要」一节的步骤已执行完毕，仅作记录。

## 2026-10-01 功能验收超时的根因与修复

- 现象：Chapter `functionality` 在 2026-10-01 00:16 记为失败，公开仓部分「超过 480 秒」。本轮单独复跑同样超时（共 581 秒）；同一时段整机 1 分钟负载约 400–620（10 核），三次写入各要对 1.3 GB 的微信副本完整重签，整条进程链只拿到约 41 秒 CPU。根因是整机过载，不是 AppModel 或引擎逻辑出错。负载降到约 120 时，单独计时引擎还原 83 秒、补丁 84 秒。
- 验收脚本自身的缺陷：`subprocess.run(timeout=)` 只杀测试进程，引擎和 codesign 子进程会继续重签副本，同时 `finally` 在删临时目录，结果残留了 `build/accept/functionality-*`。`scripts/accept/functionality.py` 改为超时（或任何中断）时先逐个停住、再整棵杀掉测试进程树，仍留在调用方进程组里，Chapter 的整组超时照样有效；超时摘要附上当时负载。用合成进程树验证过：超时 2 秒触发，无残留进程。两份残留临时副本已删除。
- 复跑：`chapter sop accept --app unrevoke-mac --check functionality` 用时约 5 分钟，passed（微信 build 269627 的独立副本：还原基线 → protected → unprotected；防撤回与更新拦截都是 patched，权限保留，来源关键文件未变）。`installed_icon` 由内置离屏验收判定 passed（不再用本人确认）；`native_ui`、`cli_entry` 复跑 passed。`bash tests/run.sh` 全部 PASS。

## 2026-09-29 主页数字文件上线

- apps-site 会话提交了 `2f4df4b`：`scripts/build-site.py` 从本产品 perf 与发行记录生成 `facts.json`（门户卡片与 Chapter 读它）。本轮 `bash tests/run.sh` 19 项 + Swift 检查通过后，按 `bash scripts/deploy-site.sh` 部署；线上 `https://unrevoke.tianli.cyou/facts.json` 200，与本地构建逐字节一致（1.0.10 (34)，空闲 CPU 0.03%，内存 32.5 MB 为 31 MiB 的十进制换算）。日志 `build/accept/facts-deploy.log`。

## 2026-09-29 1.0.10 资源实测（05:38，空闲门开：空闲 13878 秒、负载 4.8）

- 对象：公开 1.0.10 发行 ZIP（SHA256 25d1a22f…）解到 /tmp 的隔离副本，主程序 SHA256 与 release.json 一致；`open -n -g -j`，参数域 `autoRepatch=NO`、`everProtected=NO`，未执行任何补丁；测完用 SIGTERM 退出，无残留进程。
- 结果（整机负载约 4.5）：空闲 31 MB / 界面 CPU 0.02%，含每 30 分钟完整检查折算约 0.03%；后台打开到首个状态检查结束中位 1862 ms，到窗口出现中位 281 ms（各 5 次）；完整检查 `wechattweak doctor` 中位 1640 ms / CPU 0.26 s；安装包 2,449,790 字节，装好后 4,316 KiB。原始数据 `perf/raw/current-1.0.10.json`，1.0.9 记录移入 `history`。
- README 中英版由共享 perf_block 重写并改掉「待测」说明；`tests/test_build_contract.py` 的相关断言改为按实测版本通用；`bash tests/run.sh` 19 项 + Swift 检查通过。
- 按 `bash scripts/deploy-site.sh` 部署，线上 200、ZIP/教程 SHA256、4 段视频 Range 通过，线上页面显示「资源实测：v1.0.10，2026-09-29」，Chapter `numbers_on_page` 无缺项。日志 `build/accept/perf-1.0.10-deploy.log`。

## 2026-09-29 复查轮

- `cli_entry` 重新走固定验收：passed（Chapter 报的「验收材料与缓存不一致」源于检查报告缓存早于最新证据；app_sop check-only 当时返回 busy，由 Chapter 排队的只读重检刷新）。
- 1.0.10 资源实测：空闲门未开（`app_sop.steady()` 先后返回「有构建在跑」、03:4x「负载 13.8 ≥ 10」），按快节奏约束未采样；接手命令仍见下文「1.0.10 运行资源待空闲补测」。
- 管理员免密摘要：已装引擎 SHA256 仍为 `738c112e…`，未执行 sudo。

## 2026-09-29：发行包清单门

- `release.sh` 在解压自检处新增「文件清单白名单」门：公开 ZIP 的条目（含目录项）必须恰好等于批准的 12 条，多一条、少一条或重复都拒绝发布；`tests/test_release_manifest.py` 直接抽取 `release.sh` 里的同一段门代码，对正常、多出、缺少、重复四种 ZIP 做回归。当前 1.0.10 公开 ZIP 正好 12 条，门通过。
- `bash tests/run.sh`：19 项 Python + Swift 运行时检查通过。公开 ZIP、Release、cask、官网本轮都没有变化，没有发版或推送。
- 本机装机来源与维护方式记在本机私有指引（不入库）；装机后 `cli_entry`、`native_ui` 两项固定验收通过，构建回执与装机一致。

## 最新一轮：安装占用缺项与性能补测

- 两个子 agent 并行负责页面小修与性能入口只读核查，复用已有 `scripts/accept/_common.py`；主 agent 集成、执行完整测试和既有部署入口，未修改共享模块。
- 页面缺项根因是“当前发行 ZIP 展开文件长度总和”与“历史已装占用”共用 `installed` 指标标记；现在可见地分别注明当前 **1.0.10 / 4.402604 MB** 与历史 **1.0.9 / 2026-09-26 / 4.3008 MB**。两项对象、版本和方法不同，不隐藏数值、不修改历史证据或共享检查器。
- 主 agent `bash tests/run.sh`：**18 项 Python + 13 项 Swift 检查通过**，日志 `build/accept/page-fix-tests.log`。新增回归检查直接调用 Chapter 的页面解析器，避免复制另一套判定。
- 已按 `bash scripts/deploy-site.sh` 重建并部署；线上 HTTP 200、ZIP/教程 SHA256、4 段视频 Range 请求核验通过，日志 `build/accept/page-fix-deploy.log`；主 agent 回读线上 HTML 并调用 Chapter `numbers_on_page` 返回空缺项列表，页面快照 `build/accept/page-fix-online.html`。
- 受影响的桌面/手机固定验收均于 14:36 通过（1440px / 390px，无溢出、4 张图片均加载），主 agent 复核截图及回执/日志哈希；结果见 `build/accept/page-fix-acceptance.json`，证据只由 app_sop 写入 `perf/delivery-evidence.json`。App 源码、图标、视频和业务输入未变化，不重复此前其他通过项。
- 线上发行、本机安装和 build-receipt 回读仍一致为 **1.0.10 (34)**，没有重复发版或装机；本轮只推送页面生成器、回归测试和交接。仓库无 GitHub Actions、ci_scripts 或 Xcode Cloud 配置，推送本身不触发 CI；既有 app_sop 后台监听保留。
- 性能空闲门实测未通过（用户 0 秒前有操作），依本轮要求直接跳过长采样；当前没有完整测量脚本或 `sop.measure`，仅有候选 idle 入口，不能把旧版资源值改成当前通过。
- Chapter 的 test-only 登记返回 **75 / busy**；没有终止其他作业或重复抢锁，独立测试通过结果保留，锁释放后的登记命令在下方“受阻与 CLI 接手”。
- 管理员免密摘要和本人装机图标确认仍属范围外，原有前置材料保留；`memory/` 未变化，跳过备份。

## 上一轮发布与素材记录

上一轮按 2026-09-28 起的长期授权，完成本产品的素材更新、1.0.10 (34) 发版、推送、本机装机和官网部署。三个子 agent 分别负责素材、发版前置检查、页面资源口径；主 agent 集成、执行发布/装机/部署、复核截图并统一验收。此前的四个固定验收入口已随本版发布。

## 已交付

- 发行：<https://github.com/zengtianli/WeChatUnrevoke/releases/tag/v1.0.10>；源码提交 `54a8ea65806f2441ca3010f30ca3664d7cae9db7`，版本 **1.0.10 (34)**；GitHub 回读非草稿、资产摘要一致，既有发布脚本同步了本产品 Homebrew cask。
- 官网：<https://unrevoke.tianli.cyou/>；线上 release.json、下载 ZIP、当前教程 SHA256 与本地发行记录一致，4 段视频 Range 请求为 206。
- 装机：`/Applications/WeChatUnrevoke.app` 已安装校验过的公开发行 ZIP 内容；主程序 SHA256 与发布记录及 Chapter build-receipt 三方一致，adhoc 签名通过；保留 bundle ID、用户数据、偏好、登录项配置，没有强退用户实例。
- 当前教程：用真实生产 ContentView 离屏重新生成三种状态、21 秒字幕视频；虚构状态说明界面，页面明确其范围，旧 1.0.4 实机补丁录像仍标为历史操作演示。正常 UI 未改，重新渲染的图片/视频字节与旧素材相同，元数据已核验当前源码和版本。
- 页面和双语 README：当前包体数据来自校验后的发行 ZIP；1.0.10 内存/CPU/速度明确待测，1.0.9 历史实测单独说明。后台 app_sop 提交 `6ae4a1a` 曾覆盖标记内提示，现已移到生成标记外并加回归检查；保留该后台提交。
- 发行包 2,449,790 字节（2.45 MB）；展开文件总和 4,402,604 字节（4.40 MB），后者不是文件系统实际分配空间。

发行 ZIP SHA256：`25d1a22fe526dda96635d15707fbc1eeec41ed3d76c89dc94503e4bbed1e8b56`。

已装主程序 SHA256：`245ddfbbea2bf431e5f62c56538ee4ddeab2d08aa42ad48d638fb162102c4f98`。

第一次单独 Release 重建的主程序字节与公开 ZIP 不同，未把它当成同一发行物；随后改为安装校验过的发行 ZIP。最终 `perf/build-receipt.json` 由 app_sop 包装安装命令生成，绑定发行源码、引擎输入和实际已装主程序。源码输入共 34 个文件，摘要 `43eb91e6e0b20ca255166221df41dcffeeddcc140c71a447b757c62b6d12fadd`。之后仅 README、测试及交接变化，不重复发版。

## 主 agent 验收

以下 7 项固定验收全部 passed，回执由 app_sop 写入 `perf/delivery-evidence.json`。主 agent 核验每项回执/日志哈希，复核桌面/手机页面及当前原生界面截图，未手写证据。

| 验收 | 实际范围 |
| --- | --- |
| functionality | 微信 build 269627 独立副本：还原基线 → protected → unprotected；防撤回/更新拦截均 patched，权限保留，来源关键文件未变 |
| recovery | 9 项真实控制器恢复路径，受控故障引擎 fixture |
| privacy | 6 项网络请求/缓存/隔离边界；不是 vendor 引擎内部审计 |
| native_ui | 进程内直接调用动作，9 项断言、5 张离屏截图，无合成输入 |
| homepage_desktop | 1440px，HTTP 200，无横向溢出，4 张图片均加载 |
| homepage_mobile | 390px，HTTP 200，无横向溢出，4 张图片均加载 |
| media_playback | 4 个本地视频全量解码通过，推广页 3 个视频真实无界面播放 |

完整结果：`build/accept/release-acceptance.json`，最后 functionality 于 2026-09-28 13:43 通过。更早为替换安装来源而主动中断的一次验收记录，已由最终验收自动更新。

最终 `bash tests/run.sh` 通过：16 项 Python 测试、13 项 Swift 运行时检查，日志 `build/accept/final-tests.log`；发布前同套测试、universal 构建、解包后两架构和签名检查也通过。Xcode 的 Intel 弃用提示不改变已检查的引擎 minos 12.0；App 支持仍为 macOS 15+。

```bash
~/Dev/.venv/bin/python ~/Apps/chapter/engine/app_sop.py accept --app unrevoke-mac \
  --check functionality --check recovery --check privacy --check native_ui \
  --check homepage_desktop --check homepage_mobile --check media_playback --json
```

`icon_review` 输入未变，复用原结果；`installed_icon` 不替本人确认。没有验证真实账号聊天撤回，没有重试管理员免密业务。

## 自动化与改动边界

- `project.yaml` 沿本仓约定仅留本机，登记四个 sop.accept、ui_self_test_flag 和 12 个引擎源码/配置依赖；公开登记示例在 `scripts/accept/README.md`。
- `perf/acceptance/`、`perf/delivery-evidence.json`、`perf/build-receipt.json` 是本机生成回执，已忽略且未提交；开工前他人已有产物保留。
- 推送前检查全部领先提交，均为本组件完成内容；未 force、改历史或公开范围。GitHub Actions 数量为 0，无 ci_scripts、工作流或 Xcode Cloud 配置；推送无 CI 部署钩子，发布脚本显式更新 Release/cask 并部署本产品。现有每小时及 /Applications 监听的 app_sop 作业保留，可能刷新 README、推送及部署。
- 只修改本组件；为既有构建入口已用 claims 声明引擎仓 `.build` 缓存写入，没有修改共享模块或 vendor 引擎源码（保持 `111e3d4` 且工作树干净）。
- `memory/` 自指定备份以来无变化，跳过备份。

## 受阻与 CLI 接手

### Chapter 汇总检查锁（可自动重试，owner: chapter）

最终 test-only/check-only 返回 exit 75 / busy：另一轮 app_sop 全局作业占锁，未终止或绕过它。产品测试和 7 项 accept 已独立通过，仅缺 Chapter 汇总/测试绑定更新，不能声称所有维度全绿。原已排队的只读重检可在锁释放后执行，进本仓后的命令：

```bash
~/Dev/.venv/bin/python ~/Apps/chapter/engine/app_sop.py run --app unrevoke-mac --stage test --test-only --now --offline --json
~/Dev/.venv/bin/python ~/Apps/chapter/engine/app_sop.py run --app unrevoke-mac --check-only --json
```

### 1.0.10 运行资源待空闲补测（已于 2026-09-29 05:38 完成，以下为原接手记录）

遵照本轮快节奏约束，没有做长时间采样、反复 A/B 或架构优化；`perf/lightweight.json` 仍属 1.0.9 / 2026-09-26，未改版本或日期。当前没有 `sop.measure`，不能直接用 batch_measure 声称可完整测量；页面已明确待测。

CLI 接手需排定延迟执行后离开键盘（现场输入命令会重置闲置时间），空闲门要求接电源、用户至少 10 分钟无操作、低负载、无构建；任一失败即停止。以下只启动本次禁用自动写入的测量进程，不修改默认偏好，不操作已有实例：

```bash
(
  sleep 610
  ~/Dev/.venv/bin/python -c 'import sys; sys.path.insert(0,"/Users/tianli/Apps/chapter/engine"); import app_sop; ok,why=app_sop.steady(); print(why); raise SystemExit(0 if ok else 75)' || exit 75
  if pgrep -x Unrevoke >/dev/null; then
    echo "已有 Unrevoke 实例，停止以避免混测。"
    exit 75
  fi
  open -n -g -j /Applications/WeChatUnrevoke.app --args -autoRepatch NO
  sleep 45
  ~/Dev/.venv/bin/python -c 'import sys; sys.path.insert(0,"/Users/tianli/Apps/chapter/engine"); import app_sop; ok,why=app_sop.steady(); print(why); raise SystemExit(0 if ok else 75)' || exit 75
  python3 /Users/tianli/Apps/.claude/skills/app-lightweight/scripts/measure.py \
    --out build/accept/idle-1.0.10.json --product unrevoke-mac --version 1.0.10 \
    idle Unrevoke --seconds 60 --with-helpers
)
```

该命令只补内存/空闲 CPU 候选；还需沿原方法补齐启动和周期状态检查样本，核对当前发行版本、原始数据和辅助进程口径后再正式更新 perf 和页面，不把部分候选作为完整通过。

## 需要本人处理的前置材料（本轮范围外）

### 管理员免密引擎摘要

**2026-09-30 已完成**：本人执行了下列步骤，规则已钉 `738c112e…`；随后 `sudo -n` 以 root 对 WeChat（269627）的 APFS 副本执行 `patch -v keeptip`，防撤回与拦截更新均 applied、重签严格校验通过、doctor 为 protected，正在运行的微信未动；`perf/lightweight.json` 的 `availability.local_unattended_engine` 已改为 `verified`。以后引擎摘要再变时，把 OLD/NEW 换成当时的值，照同样步骤执行。

在本机（Tianli MacBook Air M4）的「终端」里由管理员执行，要输入 Mac 登录密码；不要在聊天里发密码。`/etc/sudoers.d/claude-nopasswd`（root 0440，最后修改 2026-09-25）有 4 条规则用 sha256 钉住本机引擎的 `patch`、`patch *`、`restore`、`restore *`，旧值是 1.0.8 引擎 `af9c60d5…`；当前已装引擎（自用构建沿用公开 1.0.10 ZIP，未重签）为 `738c112e…`。本 Agent 读不了该文件，旧值来自 `build/refresh-installed-engine-digest.py`，因此第 2 步先核对。该脚本硬编码 1.0.9 界面摘要，对当前装机会拒绝执行，不要用。规则不含 `doctor`，验证用无副作用的 `patch --help`。

```bash
ENGINE=/Applications/WeChatUnrevoke.app/Contents/Resources/wechattweak
OLD=af9c60d50eaea331fd6bf5909907a2f8a1cac8a2076265a99f4b87fddba808a7
NEW=738c112e09e9c032a61adb348b1d4e20ca601937a26cdebb2e2bdcc1cf5c2bb4
shasum -a 256 "$ENGINE"                                               # 1. 必须等于 $NEW
sudo grep -c "sha256:$OLD $ENGINE" /etc/sudoers.d/claude-nopasswd     # 2. 必须是 4；不是就停，先 sudo grep -n wechattweak 看现值
sudo cp -p /etc/sudoers.d/claude-nopasswd /var/root/claude-nopasswd.before-unrevoke-1.0.10   # 3. 备份
sudo sed "s/sha256:$OLD /sha256:$NEW /" /etc/sudoers.d/claude-nopasswd | sudo tee /var/root/claude-nopasswd.new >/dev/null
sudo diff /etc/sudoers.d/claude-nopasswd /var/root/claude-nopasswd.new                     # 4. 只应有这 4 行摘要不同
sudo visudo -c -f /var/root/claude-nopasswd.new                                            # 5. 必须 parsed OK
sudo install -m 440 -o root -g wheel /var/root/claude-nopasswd.new /etc/sudoers.d/claude-nopasswd && sudo rm /var/root/claude-nopasswd.new
sudo -k; sudo -n "$ENGINE" patch --help >/dev/null && echo "免密生效"                        # 6. 不应再要密码
```

回滚：`sudo install -m 440 -o root -g wheel /var/root/claude-nopasswd.before-unrevoke-1.0.10 /etc/sudoers.d/claude-nopasswd`。只读 `patch --help` 免密成功不等于后台自动重打通过；业务验证仍须满足微信已退出、确曾成功保护、可写等条件，不据此手改 availability 证据。

### 装机图标

正式图标资源未改，1.0.10 已装好，安装回执含图标摘要。本人在 Chapter 确认 Finder/Dock 实际显示；没有等价 CLI 视觉确认，未替写 installed_icon。

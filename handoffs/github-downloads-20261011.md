# GitHub Release 下载收尾 · 2026-10-11

## 16:17 当前 build 99 性能收口，候选待统一发布

Bark 主会话 `01a129e6-0029-7861-8546-6f69f1bc685d` 的追加授权。原失败 job `b4271a44e4d64687b4cf13c34452c6bd` 只有登记下载包路径不存在这一项起点错误；本地 `project.yaml` 的 `sop.measure.download` 已改为 **`dist/WeChatUnrevoke-{short}.zip`**，保留真实装机回执、os_log、静默启动与只读参数。该舰队登记文件原已由 `.gitignore` 排除，修改留在本地原文件，没有强制纳入公开仓。

沿原 `chapter enqueue --app unrevoke-mac --action perf --retry` 入队，再由原 `work --app unrevoke-mac --until-idle` 接续同一 job **`e9802847f53647828784c350a12c504c`**：先因共享 SOP 锁忙等待，16:11:28 实际启动、**16:13:51 succeeded / 当前性能证据通过**。原日志为 `~/Library/Logs/app-sop/unrevoke-mac-measure-20261011-161130.log`，原队列日志为 `~/Library/Application Support/app-sop/workbench/logs/e9802847f53647828784c350a12c504c.log`。没有另造调度、测量或通过回执。

实际新指标来自 **1.0.13 (99) 当前装机 GUI 的 LSUIElement 隔离副本**：

| 项目 | 原实测 |
| --- | --- |
| 下载包 | 正式 Release ZIP，2812556 bytes（2.812556 MB） |
| 安装后占用 | 本机装机 GUI，5914624 bytes（5.914624 MB） |
| 空闲内存 | phys_footprint 合计峰值 28 MiB（页面十进制 29.4 MB） |
| 空闲 CPU | 60 秒窗口 CPU 时间 / 墙钟，0.00% |
| 冷启动到首屏就绪 | os_log 五次中位数 2211 ms；样本 2828/2202/2251/2043/2211 ms |

静置 45 秒后采样 60 秒，按原辅助/子进程合计口径；本次采样窗只见主进程。五个实际启动样本均为 version 1.0.13/build 99、quiet=true、window_on_screen=false、focus_taken=false、errors=[]。实际装机主程序、真实构建回执、当前源码输入与测量原件摘要已逐项回读，未只凭输入绑定写通过。当前原件为 `~/Library/Caches/app-lightweight/measurement-candidates/ebf2f160342d47079a1c9b2522ce09d0.raw.json`，SHA256 **`b4f9e66063fe5d9676a0042745597e61d67b56b6040febcf4f99eb890e0631b8`**；原件逐字节保留，公开轻量文件只把本机路径表示为 `~`/`<scratch>`，不改任何历史或本次实测数值。

来源边界：装机 GUI 的主程序与正式 ZIP 不同，运行指标仅描述上述装机 GUI；**不把本次测量称为正式 ZIP 同一主程序的运行实测**。ZIP 内独立核为 1.0.13 (99)，GitHub 官方 asset ID 629593980、size 2812556、digest 与本地原件相符，SHA256 仍为 **`99389c8448375282f0bb555ca6716b07c80d059615d55dd788026af02ef1839d`**。下载大小与本机装机占用分别标注；中英 README 的旧历史前言已修正范围，版本/日期/指标仍由原渲染器从单一轻量证据生成。没有构建、装机、重签、公证、改版本或写微信补丁。本轮未改变原 App 与安装包。

原 SOP 自动本地提交 **`f8e9311`**（真实新性能数据）；既有后台另生成 **`6f41a09`**（中英 README 表格数字），两机 `git_follow` 随后产生 **`77a2960`** 合并，均保留。本次手工限定提交 **`736c88b`** 只含轻量证据路径归一和中英测量范围说明，保留凭证与提交消息检查、单次关闭自动 post-commit。GitHub `origin/main` 仍为 `42a4690`；本会话未执行 push 或 deploy，没有改共享脚本。

源码完成后按原入口重建 **`/Users/tianli/Apps/unrevoke/dist/site`**，20 个站点文件、安装包 **0**，下载按钮仍为对应 GitHub Release 页。37 项相关回归（build_contract 18、site_release_assets 12、verify_site 7）通过，`git diff --check` 通过。两条原 check 均 exit 0 / **ready=true**：apps 产品入口 issues=[]；独立站 issues=[]、warnings=[]、pending=[]。这次候选未发布，visual_verified/playback_verified=false，主会话最终冻结后统一复查与 site ship。

当前候选 SHA256：index.html **`2767e491009dba27781416e5bf596860a6406f4217f19e3458c11794d912d7b2`**；release.json **`4caa3f3f1cc7198966742877922921d1c44143fda20cd932c4b46cd6474257be`**；site-manifest.json **`6690043595b4bdb03c6067627a16d959cc856843fd08373219dfb1776213cb9c`**；perf/lightweight.json **`d8ba63c61be9470e8a2a1c71e0e4ff6cc4399605d6fe7bc42db32df988453a03`**。本节候选取代下文旧冻结 SHA；线上仍是主会话此前已发布的页面。

本次写前按 Chapter **`--pid 84330 --session chapter-task:28e33a42258540759caf867f2927fa8a`** 逐路径核 claims；未另开、未释放。剩余边界：本轮固定 perf 的当前装机 GUI 范围已通过，正式 ZIP 同一主程序的运行实测仍不能由此替代；若主会话要求该更窄范围，需沿其正式产物来源另续，不伪造回执或扩其他平台。

## 16:07 部署回读修复完成，待主会话收尾原 ship 回执

同一任务的 10 分钟接续，源码提交 **`b92afbb`**：仅修改原 `scripts/verify-site.py` 与新增专项 `tests/test_verify_site.py`。原 `scripts/deploy-site.sh` 不变，Lintel gate、rsync `--delete`、备份、原子交换、回滚原件与原有 SHA 闸均保留。本次没有部署、重建页面、修改公开 release.json/安装包/版本/素材、推送或新增 GitHub 发行动作，也未改共享 Lintel/Portal。

主会话已执行原 site ship，新站已经应用。原回执 `/Users/tianli/Library/Caches/lintel-github-downloads-ship-unrevoke.json` 的 HTTPS 回读为 **20/20 文件字节一致、online_matches=true**，但 `shipped=false`：发布阶段末尾的原回读脚本把完整 GitHub URL 加上产品域名，curl 失败退出 1；不是文件传输失败。该回执保留原状态，本次没有重写或替代它。

修复后站内文件仍使用 `https://unrevoke.tianli.cyou/`；外部安装包仅接受本仓精确、版本对应的官方 GitHub asset URL，并核 repo/tag/来源/文件名与登记版本一致，下载实际字节数和 SHA256 必须都匹配。错误仓库、版本、地址、scheme、查询、fragment、路径穿越、无效摘要/大小，以及截断或同长度篡改字节均拒绝。原 local/remote metadata 相等、旧素材版本绑定、页面历史标注、教程摘要和四段视频 Range 门继续执行。

- 必要测试按文件并行：新增 verify_site **7**、原 site_release_assets **12**、原 build_contract **18**，**共 37 项全部通过**；`bash -n scripts/deploy-site.sh` 和 `git diff --check` 通过。
- 只读运行原 `/Users/tianli/Dev/.venv/bin/python scripts/verify-site.py`，**exit 0**：线上 release metadata 与本地相同；官方 [v1.0.13 资产](https://github.com/zengtianli/WeChatUnrevoke/releases/download/v1.0.13/WeChatUnrevoke-1.0.13.zip) **2812556 bytes**、SHA256 **`99389c8448375282f0bb555ca6716b07c80d059615d55dd788026af02ef1839d`** 实际回读通过；当前教程 SHA256、四段视频 HTTP 206/Content-Range、历史素材版本绑定与标签通过。该入口不部署，也不保存新的安装包镜像。
- 原登记目录仍为 `/Users/tianli/Apps/unrevoke/dist/site`，无站点安装包。主会话最终目录的 `index.html` SHA256 为 `d3dc709fd7d6deebeed2cabed1d26a727e236ceaa7cfa4b1b0c0d1300b661870`，`release.json` 为 `4caa3f3f1cc7198966742877922921d1c44143fda20cd932c4b46cd6474257be`，`site-manifest.json` 为 `855ab5390781277750d8a5ca5832f222ff7289bef8a7189217d5f7f60e1f40fa`；本次未改变这些字节。
- 写前逐路径复用 Chapter **`--pid 72223 --session chapter-task:759edf1082d74c80a50b6bcbe4a4778a`** 核 claims，通过；未另开、未释放声明。限定提交保留原凭证扫描与提交消息检查，单次省掉自动推送 post-commit 钩子，未改全局配置。

本产品回读缺口已修，无剩余源码阻断。**主会话核线上后按原 ship 流程接续回执收尾；本会话没有再次发布。** 下文为 15:57 首次候选的构建验收历史，首次候选的未发布状态已由本节更新。

## 15:57 首次候选记录

任务：`lintel-github-release-downloads-20261011`。本产品 ID：`unrevoke-mac`。首次候选仅维护产品页面、原站生成器、必要测试与本交接；预算 30 分钟，2026-10-11 15:57（上海）代码、重建与检查完成。当时尚未发布，没有部署、site ship、推送或新增 GitHub 发行动作。本节取代旧交接里“站点登记并保留历史安装包”的发行策略。

代码提交：**`3092bf9`**（基于 `42a4690`；只含 `scripts/build-site.py`、`site/index.html`、`tests/test_build_contract.py`、`tests/test_site_release_assets.py`）。原提交与其他人的工作均保留；没有修改 configs、Portal、Lintel、共享源码、App 版本或更新渠道，没有构建/安装 App、重新公证或重录素材。

## 当前候选与下载入口

- 原登记构建入口：`/Users/tianli/Dev/.venv/bin/python scripts/build-site.py`。
- 构建目录：**`/Users/tianli/Apps/unrevoke/dist/site`**。
- 正式下载与校验入口：[GitHub Release v1.0.13](https://github.com/zengtianli/WeChatUnrevoke/releases/tag/v1.0.13)。三个安装按钮和一处校验链接均由最新稳定发行记录生成，使用同一 `{{RELEASE_URL}}`，不写死页面版本或实测数字；按钮无 `download` 属性，说明引导到该页 Assets 下载与查看 SHA256。
- 只读 `apps-portal show unrevoke-mac --json` 核实：本行 download 同为该 Release URL；本行由主会话独占登记，本轮未写配置。
- 原生成器仍先核官方 `gh api repos/zengtianli/WeChatUnrevoke/releases/latest` 的公开稳定状态、仓库与版本对应的 Release/资产 URL、唯一同名资产 ID、digest、size，再用本地已公开 ZIP 核 SHA256/bytes/Info.plist/主程序和展开字节。缺本地当前 ZIP 时只恢复该正式 Release 的当前同名资产；不再读取、下载或要求历史包。
- `release.json` 保留真实当前发行 **1.0.13 (99)**、GitHub repo/tag/asset ID、Release 来源、包内数据与 SHA256。`download` 为官方 GitHub 资产 URL，供机器核对资产摘要；页面的所有安装入口均为 Release 页。`assets` 仅登记这个外部当前资产，站点不再提供安装包镜像或站内 SHA256SUMS 下载。
- 干净重建已移除包括无链接历史包在内的全部站内安装包，**站点安装包数量为 0**，无 `downloads/` 目录。源发行 `dist/` 的既有 **16 个 ZIP/DMG 原件逐字节不变**。教程视频、字幕、截图及示例文件仍可发布；manifest 门拒绝未链接的安装 ZIP、DMG、PKG、App 等，允许普通教程示例 ZIP 与视频。

官方资产证据：`WeChatUnrevoke-1.0.13.zip`，GitHub asset ID **629593980**，**2812556 bytes**，SHA256 **`99389c8448375282f0bb555ca6716b07c80d059615d55dd788026af02ef1839d`**；本轮原生成器核该官方 digest/size 与本地 ZIP 相符，没有新增或替换公开资产。

## 必要回归与实物检查

- 在 Mac mini 按文件并行运行全部 9 个 Python 测试文件：build_contract 18、functionality_runner 2、launch_check 4、publish_engine 4、publish_preflight 2、release_manifest 1、site_release_assets 12、startup 3、wechat_version 7，**共 53 项全部通过**；测试中的预期失败 fixture 不代表实际失败。未运行 App 安装或真实微信写入验收。
- 专项测试改为 GitHub 外部发行契约：仓库/稳定版本/唯一资产/digest/size/ID 验证，损坏下载与 ZIP 内版本/build 拒绝，完整原生成器清除旧站镜像并保留原件，隔离 ROOT 只需当前包，所有安装按钮使用对应 Release 页，教程视频与普通示例 ZIP 保留，未链接的安装包也被 manifest 门拒绝。旧站内镜像白名单测试随该策略退役；性能数字的分版本语义保持。
- 实际登记构建退出 0。独立解析 HTML 核三个安装按钮及校验链接，确认无本地安装包链接、无直接资产按钮，视频下载链接保留。19 个公开文件逐个核 SHA256/bytes 与 site-manifest 一致；另有 manifest 自身，共 20 个站点文件。
- `lintel site check --site apps --product unrevoke-mac --bundle /Users/tianli/Apps/unrevoke/dist/site --json`：**exit 0，ok=true，ready=true，issues=[]**。
- `lintel site check --site unrevoke --out /Users/tianli/Apps/unrevoke/dist/site --json`：**exit 0，ok=true，ready=true，issues=[]，warnings=[]，pending=[]**。`visual_verified=false/playback_verified=false`，本轮只读静态检查，不替主会话统一实看实播与发布。
- `git diff --check` 通过。没有为缺包保留备用镜像，没有移除共享内容/校验闸；本候选未触发 Portal 校验值误判，故没有本产品待修的共享问题。

首次候选 SHA256（主会话随后按原入口重建，最终 manifest 见本交接顶部）：

| 文件 | SHA256 |
| --- | --- |
| index.html | `d3dc709fd7d6deebeed2cabed1d26a727e236ceaa7cfa4b1b0c0d1300b661870` |
| release.json | `4caa3f3f1cc7198966742877922921d1c44143fda20cd932c4b46cd6474257be` |
| site-manifest.json | `3699b45c16ac3e378152b5b6e5414c77f3ebea4da774cb584da431a59b0b36e4` |

## 剩余动作与边界

首次候选无阻断性问题，当时的剩余动作是主会话统一 site ship；该动作与回读修复的当前状态见本交接顶部。本轮不扩资源测量、App 测试绑定等旧欠项。

写前逐路径复用 Chapter 原 `--pid 46936 --session chapter-task:e339c7a7b7524c19b15b382150a6b8d7` 核 claims，通过；未另开、未释放声明。提交保留凭证扫描与提交消息检查，单次省掉自动向另一台 Mac 推送的 post-commit 钩子，未改全局配置。验收产物、dist 与本地登记不入提交。

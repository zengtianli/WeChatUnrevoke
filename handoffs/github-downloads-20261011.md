# GitHub Release 下载收尾 · 2026-10-11

任务：`lintel-github-release-downloads-20261011`。本产品 ID：`unrevoke-mac`。本轮仅维护产品页面、原站生成器、必要测试与本交接；预算 30 分钟，2026-10-11 15:57（上海）代码、重建与检查完成。**尚未发布**：没有部署、site ship、推送或新增 GitHub 发行动作；后续由 Lintel 主会话汇总全部产品、冻结并统一发布。本节取代旧交接里“站点登记并保留历史安装包”的发行策略。

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

冻结候选 SHA256：

| 文件 | SHA256 |
| --- | --- |
| index.html | `d3dc709fd7d6deebeed2cabed1d26a727e236ceaa7cfa4b1b0c0d1300b661870` |
| release.json | `4caa3f3f1cc7198966742877922921d1c44143fda20cd932c4b46cd6474257be` |
| site-manifest.json | `3699b45c16ac3e378152b5b6e5414c77f3ebea4da774cb584da431a59b0b36e4` |

## 剩余动作与边界

本产品本轮无阻断性问题。**剩余动作是主会话冻结全部产品并统一 site ship；线上仍未应用本候选。** 本轮不扩资源测量、App 测试绑定等旧欠项。

写前逐路径复用 Chapter 原 `--pid 46936 --session chapter-task:e339c7a7b7524c19b15b382150a6b8d7` 核 claims，通过；未另开、未释放声明。提交保留凭证扫描与提交消息检查，单次省掉自动向另一台 Mac 推送的 post-commit 钩子，未改全局配置。验收产物、dist 与本地登记不入提交。

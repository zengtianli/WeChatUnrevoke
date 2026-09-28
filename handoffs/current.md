# Chapter 发布与素材交接（2026-09-28）

本轮按 2026-09-28 起的长期授权，完成本产品的素材更新、1.0.10 (34) 发版、推送、本机装机和官网部署。三个子 agent 分别负责素材、发版前置检查、页面资源口径；主 agent 集成、执行发布/装机/部署、复核截图并统一验收。前一轮的四个固定验收入口已随本版发布。

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

### 1.0.10 运行资源待空闲补测（可自动接续）

遵照本轮快节奏约束，没有做长时间采样、反复 A/B 或架构优化；`perf/lightweight.json` 仍属 1.0.9 / 2026-09-26，未改版本或日期。当前没有 `sop.measure`，不能直接用 batch_measure 声称可完整测量；页面已明确待测。

CLI 接手先执行空闲门（接电源、用户至少 10 分钟无操作、低负载、无构建；非 0 就停止）：

```bash
~/Dev/.venv/bin/python -c 'import sys; sys.path.insert(0,"/Users/tianli/Apps/chapter/engine"); import app_sop; ok,why=app_sop.steady(); print(why); raise SystemExit(0 if ok else 75)'
```

空闲门通过且没有既有 Unrevoke 进程时，用以下入口启动禁用自动写入的测量进程，不修改默认偏好：

```bash
open -n -g -j /Applications/WeChatUnrevoke.app --args -autoRepatch NO
```

静置 45 秒并再次通过空闲门后，第一步被动候选采样：

```bash
python3 /Users/tianli/Apps/.claude/skills/app-lightweight/scripts/measure.py \
  --out build/accept/idle-1.0.10.json --product unrevoke-mac --version 1.0.10 \
  idle Unrevoke --seconds 60 --with-helpers
```

该命令只补内存/空闲 CPU 候选；还需沿原方法补齐启动和周期状态检查样本，核对当前发行版本、原始数据和辅助进程口径后再正式更新 perf 和页面，不把部分候选作为完整通过。

## 需要本人处理的前置材料（本轮范围外）

### 管理员免密引擎摘要

已装 1.0.10 的内嵌引擎 SHA256 仍为 `738c112e09e9c032a61adb348b1d4e20ca601937a26cdebb2e2bdcc1cf5c2bb4`。`local_unattended_engine` 仍待管理员刷新旧摘要；本轮未执行 sudo、编辑 sudoers 或重试业务。先回读，再编辑该引擎原有 4 行摘要，保留命令范围：

```bash
shasum -a 256 /Applications/WeChatUnrevoke.app/Contents/Resources/wechattweak
sudo visudo -f /etc/sudoers.d/claude-nopasswd
sudo visudo -c -f /etc/sudoers.d/claude-nopasswd
sudo -n /Applications/WeChatUnrevoke.app/Contents/Resources/wechattweak doctor --json
```

只读 doctor 免密成功不等于 patch/后台自动重打通过；业务验证仍须满足微信已退出、确曾成功保护、可写等条件，不据此手改 availability 证据。

### 装机图标

正式图标资源未改，1.0.10 已装好，安装回执含图标摘要。本人在 Chapter 确认 Finder/Dock 实际显示；没有等价 CLI 视觉确认，未替写 installed_icon。

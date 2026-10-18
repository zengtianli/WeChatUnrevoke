# Mac TestFlight · 2026-10-18

状态：**本地改造已保存，构建/沙盒验收未通过完成，等构建槽及 ASC 记录；未上传。**

## 本轮边界

本人 2026-10-18 明确授权本产品进入 App Store Connect 和 TestFlight 内测。本轮不提交商店审核、Beta 外测审核，不修改价格或协议，不安装覆盖当前下载版。只本地提交；公开仓推送由 Chapter 在本轮之后生成本人决定卡。

负责文件为 `store/**` 和本交接；下载版 `Sources/**`、`Info.plist`、原工程、`build.sh` 不修改。共享资源只用原 `sim_lane.BuildSlot` 的并行构建槽；不持有全局构建锁，不退出其他 App、模拟器或后台。

完成条件仍是：SDK build 成功、沙盒下可用功能自检成功、真实启动不崩溃、上传后 ASC 回读 VALID 且进入内部测试组。**目前未满足这些完成条件。**

## 商店工程与权限

- `store/project.yml`：XcodeGen name/target/scheme `Unrevoke`，产品 `WeChatUnrevoke.app`，主程序 `Unrevoke`；macOS 13+，arm64 + x86_64。
- Bundle ID 沿用 `io.github.zengtianli.unrevoke`，团队 `B9LJH93LA4`，自动签名、App Sandbox、Hardened Runtime、`APP_STORE`。
- 营销版本 `1.0.14`；工程中的 build `1` 只是初始值，上传仍由共享入口从 ASC 实取下一个 build，不把它称为已上传 build。
- `ExportOptions.plist` 用 `app-store-connect` / automatic / upload。
- 正式图标复用 `icon/AppIcon.png`，生成 16–1024 像素的 10 张 RGB、无 alpha PNG。

| Entitlement | 理由 |
| --- | --- |
| `com.apple.security.app-sandbox` | 商店 App 沙盒 |
| `com.apple.security.files.user-selected.read-write` | 系统面板选择微信 App、导入诊断 JSON、导出报告 |

没有网络、自动化、临时例外、后台 helper 或特权 entitlement。不包含 `wechattweak` 二进制、CLI 软链、下载版自带更新器。共享源码只编译 `Models.swift`（原 doctor 解码契约）和 `LaneSignal.swift`（原静默启动/ready 信号）。

## 可用流程及下载版差异

`store/StoreApp.swift` 受 `APP_STORE` 条件保护，提供单独的商店界面和入口：

1. 用系统文件面板选择微信 App，只读 `Contents/Info.plist`，验证微信 bundle ID，显示实际版本/build，按精确 build 查询内置补丁库的条目、功能标识及架构。
2. 搜索内置补丁库快照（当前 45 个 build）。资源直接引用引擎仓 `config.json`，不复制第二份数据库；随此 TestFlight 包更新，不联网拉库。
3. 导入下载版引擎 `doctor --json` 的结果；复用原 `DoctorStatus` 和 `.convertFromSnakeCase`，原样展示 `overall` 及两项独立功能状态。历史报告与当前选择的微信分开展示，**不自行推导保护判决**。
4. 导出诊断文字，附当前版本查询、明确限制和原始导入 JSON；失败导入保留上一份成功报告。报告可能含本人所选文件路径，用户自行选择保存位置。

界面中英文均明确：不能开启/还原防撤回、拦截微信更新或自动重打；版本被收录不代表保护已生效；导入的历史判决不代表当前微信状态。没有启动补丁引擎、提权、强退微信、自动授权、通知或登录项动作。

**限制的运行证据尚未取得。** 当前仅实现了沙盒能力探针：尝试以写模式打开已安装微信的 Info.plist，立即关闭且不写任何字节，记录实际沙盒拒绝/允许结果；外层同时核该文件 SHA256 前后不变。必须等后续真沙盒验收后再确认写入限制，不能把上述实现说明当实测结论。

## 本轮实际验证

- `bash store/check.sh`：PASS，1.0.14、45 个兼容性 build、2 项 entitlement、10 张不透明图标。
- `spec_lint.py store`：PASS，1 个 target 规格干净。
- XcodeGen：最终工程已生成并包含 LaneSignal，生成工程与 Info.plist 被 `store/.gitignore` 排除，可由源码重建。
- `verify.py` AST、plist 解析、`bash -n`、数据库 build 唯一性：PASS。
- 首次 SDK 构建退出 **65**：生成工程未及时包含新接入的 LaneSignal；诊断为 `cannot find 'LaneSignal' in scope`。随后已重新生成正确工程，但未把静态修正称为编译通过。
- 使用 `BuildSlot(..., wait=0)` 再申请构建，退出 **75**，实际原因：`构建槽 4 个都占着`。没有继续重试或绕过槽；交原队列有限接续。
- 日志：`build/store-testflight-20261018/build.log`；第二次被拒发生在启动 xcodebuild 之前。
- 尚未运行真沙盒 `--store-self-test` / `--ui-self-test`、离屏图像验收或真实启动；尚无成功候选包，不以候选冒充已装版。

## 接续命令

原队列获得构建槽后，先在本仓执行：

```sh
cd /Users/tianli/Apps/unrevoke
/Users/tianli/Dev/.venv/bin/python store/verify.py
```

`verify.py` 只做本地验收：原 BuildSlot → SSOT Xcode 环境 → 双架构 xcodebuild → 独立 `.storetest` bundle ID 的 ad-hoc 真沙盒副本 → 两个架构的生产元数据读取/数据库查询/原 doctor 解码/错误恢复/报告导出读回/生产视图离屏渲染 → 原 App.main/delegate/window 路径静默存活 8 秒。退出 75 交原队列；其他错误读完整日志后修责任代码。它不上传、不装机、不修改正式容器，最终注销构建副本。

通过时证据为 `build/store-testflight-20261018/acceptance.json` 与同目录日志。`.storetest` 的 ad-hoc 验收不证明正式 ASC 签名身份可用；正式签名仍由原上传器归档导出验证。测试 PNG 由 App 写入其沙盒临时目录，路径在 self-test JSON 中；接续者须目视检查，不能仅凭 bitmap 非空声称版面通过。

## ASC 与上传

本轮两次 API 列表查询均未查到 `io.github.zengtianli.unrevoke`；另一次 `asc.py builds ... --platform macos` 明确返回没有此 App 记录。原建记录轮的回执亦为未创建：ASC 网页 App 列表空白，未取得新建表单。**等 ASC 记录**；本轮没有自行去网页创建。

待本地验收通过、原轮创建记录后先查：

```sh
cd /Users/tianli/Apps/unrevoke
~/Dev/.venv/bin/python3 ~/Dev/tools/dev/lib/tools/macapp/ios/asc.py apps | grep -i 'io.github.zengtianli.unrevoke'
chapter store testflight --app unrevoke-mac --platform macos --json
~/Dev/.venv/bin/python3 ~/Dev/tools/dev/lib/tools/macapp/ios/asc.py builds io.github.zengtianli.unrevoke --platform macos
```

上传仅走上述 Chapter 固定入口，不新建上传器。若上传发生后中断，先回读相同 build，再按原脚本给出的 `asc.py attach ... --testflight-only --build-number N --platform macos` 补挂；不重传成功包、不创建商店草稿。

本轮上传 build：**无**；VALID：**未取得**；内部组关联：**未取得**；商店/Beta 外测审核：**未提交**。

## 来源与推送

当前内置数据库 SHA256：`57fe2db9282a7f9c099ea37f2ef3db364a04e0906f6c26b6e2f92b4522d4c4cd`。后续若输入变化须重新绑定实际产物，不复用本轮未通过的构建证据。

`chapter xcode-cloud status --repo /Users/tianli/Apps/unrevoke --json` 回读 `push_allowed: true`，source `prerequisites`，本轮未推送。仓库为公开仓；只提交本轮路径，后续推送由 Chapter 原流程处理。claims 复用派出者 `chapter-task:934df3cf9b454a1a80dcbb216fa9ff18` / PID 14266，不释放其声明。

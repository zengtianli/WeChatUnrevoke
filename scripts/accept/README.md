# 固定验收

这些入口用于非交互验收当前源码，不安装 App、不启动微信、不显示前台窗口，也不使用键盘、鼠标或剪贴板。

| 入口 | 覆盖 |
| --- | --- |
| `python3 scripts/accept/functionality.py` | 当前 AppModel → Engine → 真实内嵌引擎，在独立微信副本上开启和还原，独立 doctor 复核 |
| `python3 scripts/accept/recovery.py` | 真实 AppModel/Engine 的故障注入、写后状态刷新、错误保留与重试恢复 |
| `python3 scripts/accept/privacy.py` | 隔离数据与偏好下验证配置请求及本地读写边界，具体覆盖见脚本回执 |
| `python3 scripts/accept/native_ui.py` | 当前 App 自带 `--ui-self-test`，真实 SwiftUI 视图离屏渲染、刷新和关闭路径 |

构建临时文件放 `build/accept/`，每项使用独立 bundle。普通运行输出细节到 `perf/acceptance/`；Chapter 调用时使用其 `SOP_OUT_DIR`。退出码 0 表示所述范围通过，78 表示前提不可用，其他非零表示失败。真实微信聊天中的撤回效果、系统授权弹框和 Finder/Dock 图标仍在该自动化范围之外。

本机 Chapter 的 `project.yaml`（按现有约定不入公开仓）登记如下：

```yaml
sop:
  accept:
    functionality: python3 scripts/accept/functionality.py
    recovery: python3 scripts/accept/recovery.py
    privacy: python3 scripts/accept/privacy.py
    native_ui: python3 scripts/accept/native_ui.py
  ui_self_test_flag: --ui-self-test
```

正式验收由 Chapter 执行；不要手写 `perf/delivery-evidence.json`：

```bash
~/Dev/.venv/bin/python ~/Apps/chapter/engine/app_sop.py accept --app unrevoke-mac \
  --check functionality --check recovery --check privacy --check native_ui --json
```

原有回归测试入口为 `bash tests/run.sh`。默认 `build.sh` 会装机，验收脚本不调用它。

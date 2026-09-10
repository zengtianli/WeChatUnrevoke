# 实机演示素材

录像使用 WeChatUnrevoke v1.0.4 的本机安装构建和微信 build 269627 测试副本。界面操作真实执行，补丁结果由内嵌引擎独立检查。中文、英文产品静态截图另见 `../screenshots/`。

| 成片 | 内容 |
|---|---|
| [enable.mp4](enable.mp4) | 点击开启、等待、完整保护、展开详情 |
| [partial.mp4](partial.mp4) | 仅开启防撤回、风险确认、部分保护与详情 |
| [restore.mp4](restore.mp4) | 详情与还原入口、确认框、等待、还原后状态 |
| [tutorial.mp4](tutorial.mp4) | 按上述顺序合并的三段独立教程 |

视频内烧录中文字幕，网页另提供 VTT 字幕轨道，可暂停、拖动、全屏或下载。中间等待有剪辑并明确标注，不作为性能测量。系统确认框单独捕获；还原结束状态在同一副本上重新打开应用后补拍，视频已注明。录制后帮助链接切换到产品主页，核心操作流程相同。

测试环境 SIP 为 disabled。签名权限由引擎验证为完整（19 项）；这不代表已经在 SIP enabled 机器上验证。工具不要求关闭 SIP。没有录制真实聊天、管理员密码输入或 build 269136 原始报错；「仅防撤回」片段演示的是该问题对应的 GUI 操作，不声称复现了那个版本。

原片和本机诊断保存在本地构建目录，不公开个人路径。字幕渲染与剪辑入口为 `scripts/render-demo.py`、`scripts/demo-caption.swift`。各片段的原片相对名称、切点与文案见 [edit.json](edit.json)。原片不随仓库分发；公开成片可以直接使用。

## 产品主页

[unrevoke.tianli.cyou](https://unrevoke.tianli.cyou/) 直接托管安装包、截图和视频，不需要 GitHub 账号。下载包来自公开 Release，部署前及线上下载后校验 SHA256；视频验证 HTTP Range，以支持拖动播放。

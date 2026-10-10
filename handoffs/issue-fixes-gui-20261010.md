# GUI issue 修复交接 · 2026-10-10

启动接线、分项权限说明、macOS 13 部署/API 分支及完整微信版本字段已完成；本轮只产生本地 GUI 候选，没有安装、推送或对外回复。（后续：已随 v1.0.12 build 92 发布；本页是发布前的记录。）

详细证据与验证范围见 [gui-fixes-20261010.md](../docs/gui-fixes-20261010.md)。原交接 ID：`20261010-1700-unrevoke-gui`，合同 notes/result 及候选摘要在对应任务 output。

集成接口：doctor 的可选字符串 `full_version`、`short_version`、`install_channel`。旧引擎缺字段正常解码并回落 build；GUI 不读取微信业务状态，不重算 overall。引擎由原责任方合入后再统一构建发行。

已验证：发行 ZIP 摘要与崩溃片 UUID、两架构同一 NSApp nil 指令路径、旧构造失败/新构造通过的回归、写入失败后刷新/恢复/独立功能/历史用例、universal Release、minOS 13.0 与新 API 弱链接、原生 ARM 与 Rosetta 离屏自检。

未验：macOS 13.7.8 真机、原生 Intel 真机、用户实际权限环境与真实聊天。README 明确区分当前源码 13+ 与已公开 v1.0.11 ZIP 15+。全量测试执行一次，其启动回归环境断言修正后仅针对性重跑，不重复无关全量。

恢复：沿本轮提交 `git revert <commit>`；测试和 GUI 候选为隔离产物，无真实微信或用户偏好需要还原。保留他人的 `handoffs/issue-1-20261010.md`，未纳入本次提交。

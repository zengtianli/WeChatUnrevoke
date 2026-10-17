# 2026-10-17：固定 test / perf / input-binding 失败修复

## 本轮边界与完成条件

- Owner 为 Chapter 当前派出轮次；复用派出者的 claims 身份，不新增或释放声明。
- 可写块限定为 `tests/test_build_contract.py` 的 Chapter 解析器加载、`tests/run.sh` 的 Python 并行入口、`scripts/accept/product_basics.py` 的来源校验、对应回归与本交接。
- 保留其他会话的修改、暂存和后台；共享 Chapter、测量器与其他仓库只读，不修改或启动本人 App。
- 完成条件为范围内修复、必要离线回归通过、本地提交；固定测试和性能证据由原 jobs 队列复验产出。
- 不推送、发版、装机、部署、改授权，不改写历史性能数字或手填通过。

## 原日志定位

- 本仓集成测试用文件路径加载 Chapter，未加入其 engine 目录，导入同目录 `xcode_cloud` 失败。
- 固定 test 的完整日志另有范围外依赖仓库的 4 项夹具失败；不通过删测试、跳过或放宽断言来消除失败。
- perf 在共享 `batch_measure.run → sim_lane.acquire → booted_udids` 查询模拟器状态时超时，尚未采样；目前只将 Busy 转为 Deferred，LaneError 超时仍被记为失败。
- perf/input-binding 的旧实测仍过期，需要原测量器修正环境超时分类并由原队列取得当前输入的新实测；本仓没有登记专用测量命令，不能靠本仓包装改变该共享路径。

## 修改与验证

- 集成测试在临时 Python 搜索路径中加入 Chapter engine 目录，加载真实解析器后恢复原路径；不替换解析器或跳过断言。
- 固定 `tests/run.sh` 使用 `pytest -n auto tests`；依赖为 pytest / pytest-xdist，Swift 回归入口保留。
- product_basics 在已装包模式接受 Chapter 提供的 `SOP_CODE_BINDING_SHA256` / `SOP_BUILD_CURRENT`，前后重新通过 Chapter 核对生产绑定；显式候选与独立运行使用共享 `code_only=True` 来源核验。
- 实际可执行文件、版本、图标与 receipt 对照、严格 codesign 均保留；生产输入、产物、签名任一变化仍拒绝，不把验收脚本和输出变动算成生产源码变化。
- 新增 8 项绑定回归覆盖测试来源漂移、未核当前构建、缺绑定、执行中生产输入变化、产物变化、坏签名、候选拒绝与独立运行。
- 本轮必要 Python 回归：`PYTHONDONTWRITEBYTECODE=1 python -m pytest -n auto tests --ignore=tests/test_startup.py -q`，实际 73 passed / 83 subtests passed，9.01 秒；`bash -n tests/run.sh`、`git diff --check` 通过。
- 对真实装机只读运行新绑定入口，生产绑定、receipt 中实际产物与严格签名均通过；未启动 App、未生成或改写 Chapter 通过证据。
- 未重编启动/Swift 回归：原日志这些项通过且生产源码未变；固定全量 test 与 perf/input-binding 仍由原 jobs 队列自动复验，本轮不重复运行全产品 SOP。

## 范围外接续

- Chapter：修正共享测量器在模拟器查询超时或忙时的 75/Deferred 分类，保留真实设备、采样安静门与原 next_attempt_at 有界重试；断言与业务错误仍失败，不在本仓复制测量器。
- 依赖测试所属组件：修复原固定日志中的 4 项夹具失败，不修改本仓聚合检查来隐藏它们。
- 环境恢复且共享修复落地后，由原 jobs 队列续本产品 test / perf；旧性能原件、数值和日期保留，取得新实测前不声称 input-binding 通过。

本轮没有需要本人决定的事项；只完成授权路径内修复与本地提交，完整固定检查尚待范围外问题处理和原队列复验。

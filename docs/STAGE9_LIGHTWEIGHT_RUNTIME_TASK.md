# Stage 9 / Windows 常驻运行轻量化任务卡

> 日期：2026-07-25
> 状态：自动验证完成，等待日常使用复验

## 目标

在不削减 Quota Watch 基础功能的前提下，减少常驻进程、内存占用和无效后台开销。
本轮只优化 Quota Watch 自己的运行链，不关闭 Windows 服务、不改注册表、不改变系统安全或电源设置。

## 当前基线

真实根目录启动器空闲运行时共有 7 个关联进程：

- Flutter 前端 1 个；
- 后端 venv 启动器与实际 Python 各 1 个；
- GUI 启动器 1 个；
- 生命周期 PowerShell 1 个；
- `conhost` 2 个。

5 秒采样结果：

- 总工作集约 **370.4 MB**；
- 总私有内存约 **264.8 MB**；
- 总 CPU 时间约 **31.2 ms / 5 s**。

结论：CPU 已较低，主要优化点是常驻 PowerShell、控制台宿主和无必要的进程层级。

## 本轮切片

让根目录 GUI 启动器在普通桌面启动时接管后端与前端生命周期：

1. PowerShell 只作为一次性引导，完成依赖/端口/健康检查、凭据映射并用 `pythonw.exe`
   启动后端，不再贯穿应用生命周期；
2. 一次性引导启动 Windows Release 前端，将前后端 PID 交接给 GUI 启动器后立即退出；
3. GUI 启动器保留单实例、已有窗口唤醒、端口保护和前端退出后的后端进程树清理；
4. 只把额度凭据映射到后端子进程，显式从 Flutter 子进程环境删除；
5. 开发/Smoke 等特殊参数仍可回退到原 PowerShell 工作流。

## 允许范围

- `scripts/launcher/QuotaWatchLauncher.cs`
- `scripts/start_quota_watch.ps1`
- `backend/tests/test_one_click_launcher.py`
- `scripts/build_windows_launcher.ps1`（仅在编译需要时）
- 对应任务卡、学习日志和交接文档

## 非目标

- 不修改 Provider 请求、额度数据或刷新语义。
- 不关闭 Windows Defender、索引、更新、动画或其他系统服务。
- 不降低进程优先级、不强制回收工作集、不使用“看起来省内存”的数字优化。
- 不改变桌面磁贴、托盘菜单、普通应用覆盖或 `Win+D` 行为。
- 不做单文件安装包；仓库、venv 与 Release 目录依赖保持不变。

## 完成条件

- [x] 普通根目录 EXE 启动不再常驻 PowerShell 或 `conhost`。
- [x] 关联常驻进程由 7 个降至 4 个。
- [x] 稳态工作集由约 370.4 MB 降至约 247.9 MB；CPU 采样仍处于可忽略量级。
- [x] 单实例、重复双击唤醒、端口占用保护、健康检查和前端退出后后端清理通过。
- [x] 自动测试确认 Flutter 子进程环境不包含 Kimi/GLM 凭据变量。
- [x] 后端 414 项、Flutter 50 项、启动器专项 9 项与 Windows Release 构建通过。
- [x] 根目录新版 EXE 实际重启并完成资源复测。

## 学习点

轻量化首先要区分 CPU、工作集、私有提交和进程数量。当前 CPU 已低，继续压缩轮询收益有限；
把 100 MB 级的常驻脚本宿主从生产生命周期中移除，才是更有意义且可验证的优化。

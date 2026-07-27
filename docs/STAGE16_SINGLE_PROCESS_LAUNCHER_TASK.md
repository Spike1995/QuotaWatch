# 阶段 16：合并启动器并验证单进程瘦身

## 目标

让根目录 GUI 启动器直接启动 Windows Release Flutter EXE 后退出，删除
生产启动链中的 PowerShell、FastAPI、Uvicorn 与 Python 常驻进程；用相同
机器上的可复现实测给出磁盘和内存收益。

## 所在交付链

Windows 登录启动项 / 用户双击 → **轻量 GUI launcher** → Flutter Release。
Provider 查询、凭据和聚合已在阶段 15 归入 Flutter，因此启动器只负责定位、
单实例唤醒、早期失败提示和启动。

## 允许范围

- 精简 `QuotaWatchLauncher.cs`，保留 GUI subsystem、单实例唤醒、凭据环境
  清理、错误弹窗和脱敏诊断日志。
- 重新构建根目录 `启动 Quota Watch.exe` 与 Windows Release。
- 保留 PowerShell/FastAPI 作为明确的开发工具，但生产 launcher 不引用它们。
- 运行进程、端口、发布目录、工作集和私有内存测量。

## 非目标

- 不修改 UI、悬浮窗布局或可见文案。
- 不删除后端源码与离线契约测试；它们仍用于 Web/Android 开发和迁移对照。
- 不读取、截图、记录或报告真实额度与 Key。
- 不自动修改用户的开机自启动开关。

## 完成条件

- 根 launcher 源码不含 PowerShell、Uvicorn、FastAPI 或 runtime handoff。
- launcher 启动 Release 后 1.5 秒健康观察完成并退出；再次双击唤醒已有
  Flutter 窗口。
- 生产启动稳定后只有一个 `quota_watch.exe`，无 launcher、PowerShell、
  Python/Uvicorn 子进程，8000 无监听；Codex 临时 app-server 查询后回收。
- Windows Release 和 launcher 均实际构建成功。
- 测出 Flutter 单进程内存、淘汰 runtime 磁盘体积，并用离线关闭 Provider
  的旧 Uvicorn 运行时测出可归因的内存节省。
- 全量回归、安全扫描与 diff 审计通过。

## 本卡学习点

- “launcher 合并”不是把更多逻辑塞进壳，而是当 Flutter 已拥有业务职责后，
  让壳缩回一次性启动与唤醒。
- 内存收益要把新应用自身、已删除的后端增量和临时 Provider 子进程分开测；
  不应把短暂 Codex app-server 算成常驻进程。

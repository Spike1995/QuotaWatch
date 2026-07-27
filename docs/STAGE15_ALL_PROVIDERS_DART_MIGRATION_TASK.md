# 阶段 15：GLM、Codex 与综合查询迁入 Dart

## 目标

完成剩余真实数据链迁移：GLM 官方插件契约 HTTPS、Codex 官方本机
app-server JSONL 协议、跨 Provider 并发聚合与最后成功缓存全部由 Windows
Dart 客户端承担。随后把凭据配置从 FastAPI 路由迁到本机 Dart/Win32，
使默认 `all_real` 不再依赖 Python。

## 所在交付链

本机登录 / Windows 凭据 → Dart Provider Client → Dart Parser →
统一聚合 Repository → 现有 Riverpod 状态 → 现有 UI。完成本卡后，Python
后端只保留为开发/历史回归资产，不再属于 Windows 发布运行时。

## 允许范围

- 迁移 GLM 解析器与固定官方 HTTPS Client，建立 Python/Dart 共享黄金结果。
- 迁移 Codex app-server 命令发现、无 shell 子进程、JSONL 握手、限长读取、
  超时清理、错误分类与模型解析。
- 新增 Dart 综合 Repository，三家并发且稳定排序、单家失败隔离、进程内
  最后成功回退。
- 迁移 WinCred 写入/删除和非敏感配置元数据；保持现有设置页视觉与交互。
- Windows 四个真实场景全部切到 Dart；Web/Android 保持原后端链。

## 非目标

- 不改 UI、布局、文案、悬浮窗行为或字体。
- 不读取 Codex `auth.json`、ZCode/worker 私有配置、Cookie、Token 缓存或
  原始流量；Codex 只走官方 `app-server`，GLM 只走已记录的官方插件端点。
- 不在测试中连接真实服务；不打印或提交凭据和原始响应。
- 本卡暂不删除 Python 源码与离线测试，删除的是发布运行依赖。

## 完成条件

- GLM/Codex 的脱敏样例和关键边界在 Python/Dart 中对等。
- Codex 子进程命令不经过 shell，stderr 丢弃，JSONL 单行限 1 MiB，
  超时后确定性终止；RPC 原始错误不进入 UI/日志。
- Windows `codex_real`、`kimi_real`、`glm_real`、`all_real` 均由 Dart
  Repository 提供；三家失败互不拖累。
- 设置页仍可读取、保存、替换、删除现有 WinCred 和手动 Codex 备注，Key
  请求完成后立即清空。
- Web/Android Repository 选择不变。
- 全量 Python/Flutter 测试、静态分析、Windows 原生构建和无秘密 diff
  审计通过。

## 本卡学习点

- 常驻后端可删除的判据不是“Provider 代码已复制”，而是默认路径中的网络、
  子进程、凭据、元数据、聚合和错误回退均有新归属。
- 临时 Codex app-server 子进程不同于常驻 FastAPI：它仅在刷新期间存在，
  完成请求后必须关闭，才能兑现常驻内存下降。

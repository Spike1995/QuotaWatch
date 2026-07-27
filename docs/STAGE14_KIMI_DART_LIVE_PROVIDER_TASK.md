# 阶段 14：Kimi 真实查询迁入 Windows Dart 客户端

## 目标

让 Windows 客户端在 `kimi_real` 场景中直接完成 Kimi Key 解析、官方 HTTPS
查询、响应限长、Dart 解析和统一错误/旧值回退，不再经过本机
Python/FastAPI。保留其他场景的现有链路，便于逐家迁移和回归。

## 所在交付链

Windows 凭据管理器 / 启动进程环境 → 原生白名单凭据读取 →
**Dart Kimi HTTPS Client** → 阶段 13 解析器 → `ProviderQuota` → 现有 UI。
这是“单家 Provider 迁入 Dart”的第一个完整纵向切片。

## 允许范围

- 在现有 Windows MethodChannel 上增加仅限 Kimi/GLM 白名单目标的只读凭据
  方法；本卡只消费 Kimi。
- 新增 Kimi Dart Repository 与平台 Repository 工厂。
- Windows 的 `kimi_real` 改走 Dart；Web、Android 和其他场景保持后端链路。
- 增加完全离线的 HTTP、凭据通道、错误映射、响应限长和缓存测试。

## 非目标

- 不修改 UI、布局、可见文案或悬浮窗行为。
- 不打印、持久化、截图或提交 API Key 与真实响应。
- 不在自动测试中调用 Kimi。
- 本卡不迁移设置页的凭据写入，也不删除 FastAPI；它仍服务 Codex、GLM
  与 `all_real`。

## 完成条件

- `kimi_real` 在 Windows 返回三个稳定顺序的 Provider 项，Kimi 来自 Dart。
- 请求固定为官方 HTTPS URL，拒绝重定向，响应上限为 1 MiB，状态码和异常
  只产生归一化安全文案。
- API Key 优先使用进程环境，否则只读现有 `QuotaWatch/Kimi` Windows
  凭据；缺失或非法 Key 时不发请求。
- 成功结果保存在进程内；刷新失败时返回旧窗口并标记“数据可能已过期”。
- Web/Android 和 Codex/GLM/`all_real` 的 Repository 选择不变。
- Windows release build、静态分析及全量测试通过，diff 不含秘密或 UI 改动。

## 本卡学习点

- 真正减少常驻进程，需要把“解析、网络、凭据边界”一起迁走；只复制解析器
  不会降低运行内存。
- 平台工厂可以只替换 Windows 的一个真实场景，让跨平台行为和其余 Provider
  在迁移期间保持稳定。

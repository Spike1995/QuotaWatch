# 阶段 13：Kimi 解析器迁入 Dart

## 目标

在不修改现有 Flutter UI、不改变真实联网链路、不接触凭据的前提下，把
Kimi `/coding/v1/usages` 的纯 JSON 解析逻辑迁入 Dart，并证明它与现有
Python 解析器在脱敏样例和关键边界上的输出一致。

## 所在交付链

Provider 原始响应 → **Dart 解析器** → 统一 `QuotaWindow` 模型 → 现有状态
与 UI。完成本卡后，下一卡可以把 Kimi 的真实 HTTP 调用和安全凭据读取迁入
Windows 客户端，最终删除这家 Provider 对 Python/FastAPI 的运行时依赖。

## 允许范围

- 新增 Dart Kimi 纯解析器与离线测试。
- 复用 `backend/fixtures/kimi` 的脱敏 JSON 样例。
- 为 Python/Dart 增加共享黄金结果，防止两端契约漂移。
- 记录验证证据和下一步。

## 非目标

- 不修改 UI、布局、文案或悬浮窗行为。
- 不发起真实 Provider 请求。
- 不把 API Key 写入 Flutter、测试、日志、截图或 Git。
- 本卡不删除 Python Kimi 适配器；真实链路切换前保留它作为对照基线。

## 完成条件

- Dart 能解析 usage、limits、remaining 回退、标签、数值字符串和 ISO
  reset 时间（含纳秒截断）。
- 非对象契约、缺字段、钳制和相对 reset 等关键边界有离线测试。
- 四个现有 Kimi Fixture 在 Python 与 Dart 中得到同一份规范化结果。
- `dart format`、`flutter analyze`、Flutter 测试和 Python 回归通过。
- 完整 diff 不含 UI 改动、凭据、真实响应或新增联网测试。

## 本卡学习点

- “迁移 Provider”可以先拆出无副作用的纯函数，以共享样例锁定输入输出，
  再迁移网络与凭据边界。
- 跨语言迁移不能只比较“页面看起来一样”；共享黄金结果能把字段优先级、
  数字容忍、时间精度和丢弃规则变成可重复验证的契约。

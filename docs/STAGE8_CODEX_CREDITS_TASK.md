# 任务卡：Codex credits（恢复额度）端到端接入

日期：2026-07-23
阶段：阶段 8 追加切片（经用户明确授权）

## 目标

把官方 app-server 快照中已确认的 `credits` 对象（`hasCredits`/`unlimited`/`balance`）
从后端解析一路接到 Flutter 卡片展示，全程沿用现有白名单解析与离线测试纪律。

## 依据

- 2026-07-23 脱敏结构实验（用户授权）：`rateLimits(.byLimitId.codex).credits`
  存在，含 `balance`(str)、`hasCredits`(bool)、`unlimited`(bool)；脚本
  `backend/tools/inspect_codex_structure.py`（只输出字段路径 + 类型）。

## 范围

1. 后端：`QuotaCredits` 契约模型、`parse_codex_rate_limits` 白名单解析、
   聚合器失败回退保留 credits、normal 场景演示值、pytest 解析/契约测试。
2. 契约：Flutter `QuotaCredits` + `ProviderQuota.credits` + codec 解析；fixture 演示值。
3. 前端：Codex 卡片窗口列表下方显示"恢复额度"一行（无限/余量/已用完三态）。
4. 验证：后端 pytest、Flutter analyze/test、Web 构建截图；
   真实 `codex_real` 路由只做"键路径 + 类型"级脱敏验证，不记录任何值。

## 非目标

- 不接订阅到期（JWT `chatgpt_subscription_active_until` 属另一授权切片）。
- 不调用 wham 内部端点；不读取/打印/保存 auth.json、token 或任何响应值。
- 不改 Kimi/GLM 适配器；不调整卡片其他布局。

## 完成条件

- [x] 后端 pytest 全部通过（440 个；含 credits 解析、6 种漂移拒绝、camelCase 序列化用例）
- [x] `flutter analyze` 无问题、`flutter test` 全部通过（49 个；含 credits 三态展示与契约解析用例）
- [x] Web 构建成功，截图证据显示 Codex 卡片出现"恢复额度"行
      （`docs/evidence/2026-07-23-ui-codex-credits.png`）
- [~] `codex_real` 真实路由键级验证：**被提供方限流阻断**——连续重试触发了 OpenAI 侧
      RateLimitError（app-server 响应耗时 ~21.5s）；早前 17:37 的脱敏结构实验已直接证明
      真实快照含 credits 三字段，路由管线由离线 fake-server 测试覆盖。待限流恢复后由用户
      一键启动实际查看即完成闭环。
- [x] 学习日志记录证据与边界

## 追加决策记录

- `CodexAppServerClient` 默认超时 8s → 15s：Windows 冷启动实测可超 8s，且提供方限流时
  响应会明显变慢；超时仍有界。若未来常态响应超过 15s，应检查 app-server 版本而非继续放宽。

## 学习点

- 同一字段穿过 后端模型 → JSON 契约 → codec → Dart 模型 → UI 的完整纵切片；
  每一层都有独立的"类型不符即失败"防线（pydantic / FormatException / 白名单解析）。

# 阶段 8 / GLM 真实额度契约漂移修复任务卡

> 状态：代码、自动回归和脱敏真实方向检查完成；等待用户最终页面对照
>
> 用户反馈：Quota Watch 的 GLM 数据与 ZCode 不一致；Codex、Kimi 和一键启动其余部分正常。
>
> 数据边界：用户截图中的任何额度值都不进入代码、Fixture、测试、日志或文档。修复只依赖官方资料
> 与直接请求得到的脱敏字段结构。

## 目标

修复 GLM 真实响应契约变化，让直接测量稳定返回：

1. 5 小时窗口；
2. 每周窗口；
3. 月度 MCP/工具调用窗口。

数据链保持为：

```text
官方 quota/limit → GlmUsageClient → parse_glm_usage → 统一 used/limit 契约 → Flutter 三窗口详情
```

## 已确认的原因

- 一次脱敏结构探针确认官方响应当前有 3 条 `limits`。
- 两条 `TOKENS_LIMIT` 分别为 unit 3 和 unit 6，当前只有 `number`、`percentage` 和重置时间，
  不再提供旧解析器依赖的 `usage/currentValue`。
- `TIME_LIMIT` 当前使用 unit 5，并带 `percentage`、`remaining`、`usageDetails` 等字段；旧代码只把
  unit 0 标成 MCP 窗口。
- 旧解析器因此把 5 小时窗口错误地套入历史默认 Token 上限、丢弃每周窗口，并给工具窗口错误标签。
- 第一轮曾依据 ZCode 页面“剩余额度”文案，把三类 `percentage` 都解释成剩余比例。用户实际对照后
  证明该推断对 `TOKENS_LIMIT` 错误：5 小时和每周的 `percentage` 是已用比例，不应取反。
- 第二轮先只修正已确认的 Token 两窗，保留工具窗口独立换算。用户随后明确确认工具调用也反了。
  最终证据表明当前三类窗口的 `percentage` 都是已用比例，均不得取反；`TIME_LIMIT` 的其他绝对字段
  不再用来推翻服务端 percentage。

## 允许范围

- 修正 `backend/app/providers/glm_parser.py`，同时兼容当前百分比契约与历史绝对值契约。
- 增加完全虚构数值的当前契约 Fixture 和离线解析/Adapter 回归测试。
- 修正 Flutter 详情页对 `percent`、`calls` 和时间单位的格式化。
- 更新 API 研究、任务记录与启动验收状态。
- 修复后重启一键应用，用脱敏探针只验证三类窗口、单位和重置字段，不输出额度值。

## 非目标

- 不读取 ZCode 私有数据库、缓存、凭据、日志或网络流量。
- 不把用户截图当作数据源，也不手工录入截图数值。
- 不调用模型生成接口，不查询账户明细，不保存 Provider 原始响应。
- 不修改 Codex/Kimi Adapter，不扩大公开部署或商业使用权限。

## 完成条件

- [x] 当前百分比契约稳定产生 5 小时、每周和工具调用三个窗口。
- [x] `TOKENS_LIMIT` 直接使用服务端 `percentage` 作为已用比例，不再反转。
- [x] `TIME_LIMIT` 同样直接使用服务端 `percentage` 作为已用比例，不再反转。
- [x] 历史 `usage/currentValue` 契约仍按绝对值解析。
- [x] unit 5 的 `TIME_LIMIT` 显示为月度 MCP/工具调用，不再显示未知 unit。
- [x] Flutter 详情页把百分比显示为 `%`、调用次数显示为“次”，不再误格式化成分钟。
- [x] 离线专项测试、后端完整 pytest、Flutter format/analyze/test 和 Web build 通过。
- [x] 脱敏真实复验只返回三类标签/单位/重置字段，不输出或保存实际额度。
- [x] 字体子集、Playwright、秘密扫描、任务文件空白和 diff 审查通过。
- [ ] 用户在一键应用中确认 5 小时、每周和工具窗口均与 ZCode 一致。

## 验证记录

- 解析器/Adapter 专项回归：**71 passed**；后端完整回归：**431 passed**。
- Flutter：format 无改动、`flutter analyze` 无问题、**45 tests passed**；Web Release 构建成功。
- Playwright 在独立端口完成 backend/partial 页面 E2E；第一次临时测试服务返回空响应，换用干净端口
  后通过，并恢复默认 Release 构建。
- 一键应用已重新启动，`/health` 返回 `ok`，Flutter/Dart 进程正常。
- 脱敏真实检查只验证三项布尔关系：5 小时、每周、工具调用的统一 `used` 都等于服务端
  `percentage`。检查不输出、不保存任何实际额度、套餐、Key 或原始响应。

## 学习点

- 为什么“HTTP 200”只能证明请求成功，不能证明字段语义正确。
- 为什么第三方契约漂移既可能导致报错，也可能产生更危险的“看起来正常但数值错误”。
- 为什么当前契约和历史契约要用字段形状区分，不能用真实账号数值写特例。
- 为什么自动测试证明映射规则，最终仍需用户用官方界面做不泄露数据的人工对照。

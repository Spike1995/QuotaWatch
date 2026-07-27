# 阶段 7 / GLM 默认关闭适配器与综合实际额度任务卡

> 状态：本卡代码与离线自动验证完成；后续另行授权的脱敏真实结构检查完成，待用户 UI 验收
>
> 用户授权：建立 GLM 任务卡，实现默认关闭的 `GlmProviderAdapter`，并增加
> Codex + Kimi + GLM 综合实际额度模式。
>
> 合规边界：本授权是项目级实现授权，不等于智谱官方许可。本卡只做代码与离线 HTTP 替身验证，
> 不读取真实 GLM Key、不发真实 GLM 请求。

## 目标

完成两条最小纵向切片：

1. `GLM 真实额度（本机）`
   `Flutter → FastAPI → GlmProviderAdapter → 既有 parse_glm_usage → 统一契约 → UI`
2. `综合实际额度（本机）`
   `Flutter → FastAPI → 分别查询已显式启用的 Codex/Kimi/GLM → 稳定三卡顺序 → UI`

综合模式不是把三个 Key 放进 Flutter，也不是让某一家失败拖垮整页。每家的既有环境开关仍独立生效；
未启用的服务返回 `unknown`，已启用的服务并发查询并保留各自错误/缓存边界。

## 当前证据与产品决定

- 智谱官方支持 ZCode；ZCode 官方“使用统计 → 编程套餐”可显示 BigModel 的 5 小时、每周和 MCP
  远端额度。
- 本机正在运行 ZCode 3.4.2，但 ZCode 文档没有提供额度导出、CLI 或本地只读 API。
- 本卡不读取 ZCode 私有数据库、缓存、Token、Cookie、日志或网络流量。ZCode 只用于用户最终人工对照；
  将来若出现正式导出接口，再另卡评估 `ZCodeQuotaAdapter`。
- `zai-org/zai-coding-plugins` 官方源码确认额度路径为
  `https://open.bigmodel.cn/api/monitor/usage/quota/limit`，请求为 GET，`Authorization` 使用
  Coding Plan Key 原值，并发送 `Accept-Language` 与 `Content-Type`。
- 官方 FAQ/订阅规则仍限制非指定工具。本卡因此保持真实开关默认关闭，真实调用等待官方许可或新的
  明确风险决定。

## 允许范围

- 新增 `backend/app/providers/glm_adapter.py`，复用现有 `parse_glm_usage`。
- 只从后端进程环境变量 `QUOTA_WATCH_GLM_API_KEY` 读取项目专用 Key。
- 新增默认关闭的 `QUOTA_WATCH_GLM_REAL=1`。
- 后端新增 `glm_real` 与 `all_real` 场景。
- Flutter 设置页新增“GLM 真实额度（本机）”与“综合实际额度（本机）”。
- 补齐 Adapter、路由、状态、Widget、文档与秘密扫描。

## 非目标

- 不发起真实 GLM 请求，不消费模型额度。
- 不读取或复用开发 worker 的 `GLM_API_KEY`、ZCode 凭据、浏览器 Cookie 或本地私有数据。
- 不修改 Codex/Kimi Adapter 的请求协议和凭据方式。
- 不把凭据写进 Flutter、Git、`.env`、日志、截图、Fixture 或响应。
- 不部署公开后端，不实现账号系统，不读取模型/工具用量历史明细。

## 安全设计

- 真实 GLM 路径同时要求 `QUOTA_WATCH_GLM_REAL=1` 与有效
  `QUOTA_WATCH_GLM_API_KEY`。
- 生产地址固定为官方 HTTPS quota endpoint，不接受地址覆盖、不跟随重定向。
- 超时 8 秒，响应上限 1 MiB；错误正文和原始 JSON 不进入异常、日志或前端。
- 拒绝空 Key、超长 Key 和含 CR/LF 的 Key；自动测试只用明显占位凭据与
  `httpx.MockTransport`。
- 不发送自定义 User-Agent；Header 契约跟随官方插件源码。
- `all_real` 不单独增加总开关：每家的原有开关就是授权边界。未启用项不调用 Adapter。

## 完成条件

- [x] GLM 正常响应复用既有解析器并返回统一额度窗口。
- [x] 缺 Key 时不发请求；401/403、404、429、5xx、超时、重定向、损坏/超大 JSON 和空窗口有离线测试。
- [x] `glm_real` 开关关闭时返回结构化 503 且不调用 Adapter。
- [x] `all_real` 稳定返回 Codex、Kimi、GLM；只调用已启用项，未启用项显示 `unknown`。
- [x] 综合模式中单家失败不阻止其他已启用服务返回。
- [x] Flutter 可选择 GLM/综合真实场景；Fixture 模式不会保留它们。
- [x] Codex/Kimi 既有真实场景和六种模拟场景回归通过。
- [x] 后端完整 pytest、Flutter format/analyze/test、Web build 通过（419 + 44）。
- [x] 字体子集重建，Key/秘密扫描和完整 diff 审查通过。
- [x] 本卡不进行真实 GLM 调用；用户最终核对留待后续验收卡。

## 后续用户授权的本机脱敏检查

本卡最初的离线边界完成后，用户另行确认风险并明确要求使用已有环境变量做一次本机真实读取。检查
只记录了 HTTP 200、`status=ok`、两个有效窗口、`fetchedAt` 存在且无错误；没有打印或保存额度值、
套餐、Key、账号信息或原始响应。这证明当前本机技术链路可读，不代表智谱已许可第三方公开监控。

后续用户发现这两个窗口与 ZCode 不一致。脱敏字段探针证明服务端实际返回三个窗口，旧解析器因契约
漂移丢失每周窗口并误用了历史默认上限；修复与最新证据见
`STAGE8_GLM_CONTRACT_DRIFT_FIX_TASK.md`。因此这里的“两个窗口”只保留为缺陷发现过程，不再作为
正确性证据。

## 学习点

- 为什么“ZCode 能显示”不等于“ZCode 提供了可供其他应用读取的接口”。
- 为什么每家环境开关比一个总开关更适合作为授权边界。
- 为什么综合查询要隔离单家失败并保持稳定顺序。
- 为什么公开源码能证明技术契约，却不能自动等同于第三方使用许可。

# 阶段 6 / Kimi 真实额度本地只读接入任务卡

> 状态：代码、自动验证与脱敏真实读取完成；等待用户 UI 验收/讲解
> 日期：2026-07-23
> 用户授权：接入 Kimi 实际额度；本卡不修改 Codex 查询方式，不接 GLM。

## 目标

把 Kimi Code 当前套餐额度从官方 Kimi Code API 读取出来，复用已有 `parse_kimi_usage` 转换为
Quota Watch 的 `ProviderQuota` 契约，并在 Flutter 的“本地 FastAPI”模式中通过“Kimi 真实额度
（本机）”场景显示。

本卡是一条独立真实数据纵切片：

`用户选择 Kimi 真实场景 → Flutter → FastAPI → Kimi Code usages → 既有解析器 → 统一契约 → UI`

## 2026-07-23 官方复核

- Kimi Code 官方文档明确允许会员创建 API Key，用于第三方开发工具和平台。
- 官方 OpenAI-compatible Base URL 是 `https://api.kimi.com/coding/v1`。
- 官方 `MoonshotAI/kimi-code` 当前源码把额度地址定义为 Base URL 加 `/usages`。
- 官方实现只发送 `Authorization: Bearer …` 与 `Accept: application/json`，8 秒超时；官方测试断言
  不发送自定义 `User-Agent` 或 `X-Msh-Platform`。
- Kimi Code CLI 0.28.1 已安装，但没有独立的非交互 usage 子命令；本卡不调用模型来查询额度。

## 允许范围

- 新增真实 `KimiProviderAdapter`，复用现有 `parse_kimi_usage`。
- 只从后端进程环境变量 `QUOTA_WATCH_KIMI_API_KEY` 读取 Kimi Code API Key。
- 新增默认关闭的 `QUOTA_WATCH_KIMI_REAL=1`。
- 在 `/api/v1/quotas` 新增 `kimi_real` 场景。
- Flutter 设置页新增“Kimi 真实额度（本机）”。
- 增加 401/403、404、429、5xx、超时、损坏 JSON、空窗口、开关关闭和请求 Header 测试。
- 用户本人设置项目专用环境变量后，执行一次不打印额度值和原始响应的本机真实验证。

## 非目标

- 不接入或修改 GLM。
- 不改变 Codex app-server Adapter 或 `codex_real` 场景。
- 不读取 Kimi CLI 配置、OAuth token、浏览器 Cookie 或开发 worker 的 `KIMI_CODING_API_KEY`。
- 不把 Key 写进 Flutter、`.env`、配置文件、日志、截图、Fixture、测试或 Git。
- 不请求模型、不消耗生成额度、不解析 Extra Usage 钱包、不部署公网服务。
- 不设置或伪装 `User-Agent`，不允许把 Key 重定向或发送到非官方主机。

## 安全设计

- 真实路径只有后端启动前设置 `QUOTA_WATCH_KIMI_REAL=1` 才启用。
- 生产地址固定为官方 HTTPS `https://api.kimi.com/coding/v1/usages`，不提供环境覆盖。
- 禁止自动跟随重定向；响应体设置大小上限；错误只归一为固定中文文案。
- Key 只在单次请求内进入 Authorization Header，不进入模型、响应、缓存或日志。
- 自动化测试使用 `httpx.MockTransport` 和明显的测试占位凭据，始终离线。

## 完成条件

- [x] 官方端点、Header、超时和无自定义 User-Agent 有来源证据。
- [x] 缺 Key 时不发请求并返回安全认证错误。
- [x] 正常响应复用现有解析器，返回 Kimi 实际额度窗口。
- [x] 401/403、404、429、5xx、超时、损坏/超大 JSON、空窗口均有离线测试。
- [x] 开关关闭时 `kimi_real` 返回结构化 503 且不调用 Adapter。
- [x] Flutter 可选择 `kimi_real`；Fixture 模式不会保留该场景。
- [x] Codex 原场景与六种模拟场景回归通过。
- [x] 后端完整 pytest、Flutter analyze/test、Web build 通过。
- [x] Key/秘密扫描和完整 diff 审查通过。
- [x] 用户设置项目专用变量后完成一次脱敏真实读取。

## 自动验证证据

- `compileall` 与 `pip check` 通过；后端 `pytest` **395 passed**。
- Flutter `dart format`、`flutter analyze` 通过，`flutter test` **43 passed**。
- Flutter Web Release 构建成功；发布字体子集重新生成（813 个码点，352164 bytes）。
- HTTP 离线替身验证固定官方 URL、Authorization/Accept、无 User-Agent/X-Msh-Platform、禁重定向、
  1 MiB 响应上限及所有归一化失败路径。
- 开关打开但缺少项目专用 Key 时，路由返回 Kimi 安全错误、零窗口且不发网络请求；响应敏感字段扫描为零。
- 全仓库凭据模式与敏感文件名扫描无命中，`git diff --check` 通过。
- 用户本人将已有 Kimi Code 环境变量安全映射到项目变量并启动后端；脱敏检查返回 HTTP 200、
  `kimi_status=ok`、2 个有效窗口、`fetchedAt` 存在、敏感字段 0。未打印或保存额度值、套餐名、Key
  或原始响应。

## 本卡学习点

- 为什么“解析器已存在”不等于“真实接入已完成”。
- 为什么凭据只能进入后端环境变量，不能放在 Flutter 公共客户端。
- 为什么固定官方主机、禁重定向、限制响应大小可以减少 Key 泄漏风险。
- 如何用离线 HTTP 替身证明请求方法、Header 和失败路径，而不消耗真实额度。

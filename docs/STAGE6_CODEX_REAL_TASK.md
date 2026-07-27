# 阶段 6 / Codex 真实额度本地只读接入任务卡

> 状态：已完成并自动验证，等待用户界面验收
> 日期：2026-07-23
> 用户授权：先接入 Codex；本卡不接 Kimi/GLM。

## 目标

把 Codex 当前账号的额度窗口从官方 `codex app-server` 读取出来，经本地 FastAPI
转换成 Quota Watch 已有的 `ProviderQuota` 契约，并在 Flutter 的“本地 FastAPI”模式中
通过“Codex 真实额度”场景显示。

本卡位于完整交付链的第一条真实数据纵切片：

`用户选择真实场景 → Flutter 请求 → FastAPI → Codex app-server JSON-RPC → 统一契约 → UI`

## 已确认上下文

- 本机 `codex-cli 0.130.0-alpha.5` 支持 `codex app-server`。
- 本机版本生成的稳定 JSON Schema 包含 `account/rateLimits/read`。
- stdio 协议使用 JSONL，顺序为 `initialize` → `initialized` → `account/rateLimits/read`。
- 返回的额度窗口提供 `usedPercent`、`windowDurationMins`、`resetsAt`。
- 当前仓库只有 Codex 手动缓存及离线 Kimi/GLM 解析器，尚无真实 Provider 网络调用。

## 允许范围

- 新增 Codex app-server 只读客户端和 Provider Adapter。
- 新增默认关闭的环境开关 `QUOTA_WATCH_CODEX_REAL=1`。
- 可用 `QUOTA_WATCH_CODEX_COMMAND` 指定本机 `codex.exe` 的绝对路径；不接受 shell 命令串。
- 在现有 `/api/v1/quotas` 增加 `codex_real` 场景。
- Flutter 设置页增加“Codex 真实额度（本机）”场景。
- 为协议解析、超时、进程失败、未登录、开关关闭和 UI 场景选择补测试。
- 完成离线测试后，执行一次脱敏真实读取；只报告归一化额度，不输出原始 JSON。

## 非目标

- 不接入 Kimi、GLM。
- 不读取、复制、解析或记录 `auth.json`、OAuth token、Cookie、API Key。
- 不调用 `chatgpt.com/backend-api/wham/usage` 等内部网页端点。
- 不消费额度重置券，不调用任何写操作或模型生成接口。
- 不后台定时轮询，不部署公网服务，不把凭据放进 Flutter、日志、截图或 Git。
- 不改变 Fixture、既有模拟场景和默认启动行为。

## 安全设计

- 真实场景默认不可用；只有后端启动前显式设置 `QUOTA_WATCH_CODEX_REAL=1` 才启用。
- 子进程使用参数数组并设置 `shell=False`，避免命令注入。
- stderr 丢弃，异常只映射成固定中文文案；不回显原始服务端错误或账号资料。
- 只读取 `rateLimits`/`rateLimitsByLimitId` 中归一化所需字段。
- 请求结束后关闭 app-server 子进程；设置超时并保证清理。
- Flutter 只访问 `127.0.0.1` FastAPI，不接触 Codex 登录状态。

## 完成条件

- [x] 离线假 app-server 验证握手顺序和 JSONL 请求。
- [x] 主/次额度窗口正确映射为百分比及 UTC 重置时间。
- [x] 多 bucket 时优先选择 `limit_id=codex`。
- [x] 缺字段、未登录、超时、找不到命令均返回安全、可操作的错误。
- [x] 未开开关时选择真实场景返回结构化错误，且不会启动子进程。
- [x] Flutter 可选择 `codex_real`，Fixture 模式不会保留该场景。
- [x] 后端全套 pytest、Flutter analyze/test 通过。
- [x] 一次真实读取成功，输出中不含邮箱、token、账号 ID 或原始响应。
- [x] 完整 diff 通过范围、回归和秘密扫描，学习日志记录证据。

## 完成证据（2026-07-23）

- 本机真实调用通过：HTTP 200，返回 Codex 的 1 个有效额度窗口；只记录结构结果，未打印额度值、
  套餐、账户或原始 JSON。
- 响应递归检查未出现 `email`、`token`、`accountId`、`authorization`、`cookie`、`auth` 字段。
- Windows 子进程使用同步 JSONL 队列读取；成功、超时和异常路径都会关闭 app-server，无事件循环警告。
- 后端：`compileall` 通过，`pytest` **376 passed**。
- Flutter：`flutter analyze` 无问题，`flutter test` **42 passed**。
- Kimi/GLM 真实接入保持未实现；真实场景中两家明确显示“本卡尚未接入”。

## 本卡学习点

- JSON-RPC 握手与普通 REST 请求的区别。
- 为什么公开客户端不能保存登录凭据，而应让本地官方进程管理认证。
- Feature flag 如何让真实调用默认关闭并保持测试确定性。
- 如何把 Provider 特有字段转换成稳定的产品契约。

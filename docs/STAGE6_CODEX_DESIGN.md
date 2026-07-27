# 阶段 6：Codex 官方本地 app-server 额度接入设计

> 状态：**已实现并自动验证，等待用户界面验收**
> 日期：2026-07-23
> 授权范围：只接 Codex；Kimi/GLM 不在本卡范围。

## 1. 当前结论

Codex 仍没有供本项目直接调用的公开托管 REST 额度 API，但官方本地 `codex app-server` 协议提供
`account/rateLimits/read`。因此 Quota Watch 可以让**本机官方 Codex 进程管理登录**，通过 JSONL
只读查询额度，而不读取 `auth.json`、不接收 token，也不调用内部网页端点。

官方协议文档：
[Codex app-server README / Auth endpoints](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md#auth-endpoints)。
本机 `codex-cli 0.130.0-alpha.5` 生成的稳定 JSON Schema 也确认了该方法与返回字段。

旧的“CLI `/status`/网页查看 → 手动录入”方案仍保留为离线回退，但已不再是唯一方案。

## 2. 纵向链路

```text
设置页选择“Codex 真实额度（本机）”
        ↓
Flutter BackendQuotaRepository
        ↓ HTTP GET /api/v1/quotas?scenario=codex_real
本地 FastAPI（显式开关）
        ↓ JSONL stdio
codex app-server
        ↓ account/rateLimits/read
字段白名单解析 → ProviderQuota → Flutter 卡片
```

用户不需要把 Codex 桌面端或 CLI 保持打开。查询时后端短暂启动 app-server，完成一次读取后关闭；
本机需要已经完成 Codex 登录。

## 3. 数据映射

只读取官方额度结果中产品需要的字段：

| Codex 字段 | Quota Watch 字段 | 规则 |
|---|---|---|
| `rateLimitsByLimitId.codex` / `rateLimits` | Codex 快照 | 多 bucket 时优先 `limitId=codex` |
| `primary` / `secondary` | `windows[]` | 至少存在一个，否则视为契约变化 |
| `usedPercent` | `used` | 映射到 0～100，`limit=100`、`unit=percent` |
| `windowDurationMins` | `label` | 转成分钟、小时或天窗口 |
| `resetsAt` | `resetAt` | Unix 秒转 UTC 时间 |
| `planType` | `planName` / `planType` | 只返回套餐类型，不返回账户资料 |

任何通知、未使用字段和原始响应都不会进入缓存、日志或 Flutter。

## 4. 开关与安全边界

- `QUOTA_WATCH_CODEX_REAL=1`：启动后端前显式设置；默认未设置。
- `QUOTA_WATCH_CODEX_COMMAND`：可选，只允许一个存在的绝对可执行文件路径，不是自由命令串。
- 子进程使用 `shell=False`、隐藏窗口、丢弃 stderr、单请求超时和强制清理。
- JSON-RPC 错误只归一为固定错误类型，不回显服务端文本。
- 不读取或解析 `auth.json`、`access_token`、`refresh_token`、Cookie 或 API Key。
- 不调用 `chatgpt.com/backend-api/wham/usage`，不调用模型生成或任何写操作。
- Flutter 只连接 `127.0.0.1` FastAPI；不把此后端部署到公网。

## 5. 失败与降级

- 开关未启用：`codex_real` 返回结构化 HTTP 503，且不启动子进程。
- 未安装/未登录/连接失败/超时/契约变化：统一转成安全中文状态；不泄露原始错误。
- Kimi/GLM：在此真实场景明确返回 `unknown` 和“本卡尚未接入”，不伪装成真实值。
- Fixture 和既有六种模拟场景保持原行为，自动化测试不触发真实查询。

## 6. 已实现文件与证据

- `backend/app/providers/codex_app_server.py`：命令解析、JSONL 客户端、Adapter 和字段解析。
- `backend/tests/fake_codex_app_server.py`：完全离线的成功、超时、损坏 JSON、未登录协议替身。
- `backend/tests/test_codex_app_server.py`：握手、解析、错误、命令安全和进程清理。
- `backend/tests/test_codex_real_route.py`：开关关闭与真实场景 HTTP 契约。
- `quota_watch/lib/app/state/quota_state.dart`：`codex_real` 后端场景。
- `quota_watch/lib/presentation/pages/settings_page.dart`：真实场景说明与无 Key 提示。

2026-07-23 验证结果：

- 本机真实读取 HTTP 200，得到 1 个有效 Codex 额度窗口；验证输出未打印实际百分比、套餐或账户资料。
- 响应不存在邮箱、token、账号 ID、Authorization、Cookie 或 auth 字段。
- `compileall` 通过；后端 `pytest` 376 passed。
- `flutter analyze` 无问题；`flutter test` 42 passed。

## 7. 手动录入回退

既有 `CodexManualEntryCache` 与 `CodexManualAdapter` 保留用于离线测试和未来降级设计。若官方
app-server 方法发生契约变化，产品可以回到“人工查看 → 手动录入 → 标注过期”的路径，而不需要
改动统一 `ProviderQuota` 契约。

## 8. 用户验收

后端开启真实开关、Flutter 选择“本地 FastAPI → Codex 真实额度（本机）”后，应看到：

- Codex 卡片为真实查询状态，并可进入详情页查看额度窗口与重置时间。
- Kimi/GLM 显示“本卡尚未接入”。
- 点击刷新可以重新查询；退出 Codex GUI 后仍可查询。
- 页面不得显示 token、Cookie、邮箱、账号 ID 或原始响应。

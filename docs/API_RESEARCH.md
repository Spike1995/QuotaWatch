# 三家 Coding Plan 额度查询 API 调研报告

> 初始调研日期：2026-07-21；最新复核与实现日期：2026-07-23。
> 下方一～七节含早期逆向资料，只能作为历史记录；实施结论以第零节为准。
> **当前实现状态：** Codex 已通过官方本地 `codex app-server` 的
> `account/rateLimits/read` 完成只读接入；它不是公开托管 REST API，也不需要项目读取凭据。
> Kimi 已实现默认关闭的本地只读适配器，并通过自动验证和脱敏真实结构读取。
> GLM 默认关闭适配器与三家综合模式已实现；一次用户授权的脱敏本机检查发现并修复了当前响应契约
> 漂移，现可直接得到 5 小时、每周和工具调用三个窗口，等待用户与 ZCode 做最终无数值反馈的对照。
> 开发用 `kimi_worker` / `glm_worker` 与 ZCode 私有数据不属于产品额度数据接入。

---

## 零、阶段 6～7 Provider 接入更新（2026-07-23）

> 本节**覆盖并修正**下方 2026-07-21 的旧结论。卡 1 最初只做官方资料复核；用户随后明确授权
> “先接入 Codex”，项目才执行本机真实只读实验；之后用户又明确授权“接入 Kimi 实际额度”。
> Kimi 代码、自动测试和首次真实结构读取均已完成；记录只保留 HTTP 状态、窗口数量与敏感字段扫描结果，
> 不保存额度值、套餐名、Key 或原始响应。用户随后授权实现 GLM 默认关闭 Adapter 与综合模式，并在
> 另一次明确风险决定后授权本机脱敏检查。GLM 检查同样只保留字段名、类型、窗口数量与安全状态。

### 0.1 证据来源分级（实施时必须区分）

| 等级 | 含义 | 本项目能否作为唯一依据 |
|---|---|---|
| L1 官方文档 | 厂商公开帮助/产品文档 | 是 |
| L2 官方开源实现 | 厂商发布的开源插件/CLI 源码 | 是（但看 License 与更新时间） |
| L3 内部端点 | 未在文档公开、由官方客户端调用的接口 | 否，视为不稳定研究 |
| L4 社区逆向 | 第三方工具抓包/反推的接口 | 否，仅用于设计容错与降级 |

### 0.2 三家官方支持矩阵（2026-07-23 复核）

| 服务 | 官方自动查询入口 | 仅官方页面/CLI 查看 | 实验性/默认禁用 |
|---|---|---|---|
| **Codex** | ✅ 官方本地 `codex app-server` JSONL 方法 `account/rateLimits/read`（L1 文档 + 本机生成 Schema）；不是公开托管 REST API | ✅ ChatGPT 网页 Usage 面板、Codex CLI `/status`（L1） | ⚠️ app-server 命令仍标为实验性，必须做契约漂移/超时降级；内部 `wham/usage` 仍不可采用 |
| **Kimi Code** | ⚠️ 官方允许会员创建 API Key 用于第三方工具/平台（L1）；额度端点 `/coding/v1/usages` 已由官方开源实现确认（L2，见 §三），**不需要** UA 伪装 | ✅ Kimi 客户端/控制台、Kimi Code CLI（L1/L2） | 已实现，`QUOTA_WATCH_KIMI_REAL=1` 默认关闭；JSON 契约未在公开 API 文档中稳定承诺，已加入超时、大小、重定向和契约漂移保护；脱敏真实读取已通过，待 UI 验收 |
| **GLM Coding Plan** | ⚠️ 官方 `glm-plan-usage` 插件源码确认 `open.bigmodel.cn/api/monitor/usage/quota/limit` 的请求契约（L2），但插件面向官方支持场景，不等于授权任意第三方监控工具 | ✅ 官方用量统计、ZCode“使用统计 → 编程套餐”、官方插件（L1/L2） | Adapter 与 `all_real` 已实现；当前三窗口字段形状经脱敏本机检查与离线回归覆盖，`QUOTA_WATCH_GLM_REAL=1` 仍默认关闭 |

### 0.3 复核引用（官方，2026-07-23 查阅）

- Codex CLI 官方文档：<https://learn.chatgpt.com/docs/codex/cli>（L1）
- Codex 计划/限额说明：<https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan>（L1）
- Codex app-server 官方协议与 `account/rateLimits/read`：
  <https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md#auth-endpoints>（L1/L2）
- Codex “暴露完整用量”功能请求（证明尚无公开 API）：<https://github.com/openai/codex/issues/15281>（L2）
- Kimi Code 官方文档（“官方客户端和第三方平台”表述）：<https://www.kimi.com/code/docs/en/>（L1）
- Kimi Code 会员额度说明（共享周窗口与滚动 5 小时窗口）：
  <https://www.kimi.com/code/docs/en/kimi-code/membership.html>（L1）
- Kimi Code 官方额度请求实现：
  <https://github.com/MoonshotAI/kimi-code/blob/main/packages/oauth/src/managed-usage.ts>（L2）
- Kimi Code 官方请求测试（明确不发送自定义 UA）：
  <https://github.com/MoonshotAI/kimi-code/blob/main/packages/oauth/test/managed-usage.test.ts>（L2）
- GLM Coding Plan FAQ（“仅限指定工具”）：<https://docs.bigmodel.cn/cn/coding-plan/faq>（L1）
- GLM Coding Plan 接入工具/使用须知：<https://docs.bigmodel.cn/cn/coding-plan/tool/others>（L1）
- GLM 用量查询插件说明：<https://docs.bigmodel.cn/cn/coding-plan/extension/usage-query-plugin>（L1）
- GLM 官方插件的请求源码：
  <https://github.com/zai-org/zai-coding-plugins/blob/main/plugins/glm-plan-usage/skills/usage-query-skill/scripts/query-usage.mjs>（L2）
- ZCode 使用统计文档：<https://zcode.z.ai/cn/docs/usage-stats>（L1）
- ZCode 配置文档：<https://zcode.z.ai/cn/docs/configuration>（L1）

### 0.4 对原“速查总表”的修正（务必读）

- **GLM quota endpoint 的技术契约已由官方插件源码（L2）确认，但“能读懂源码”不等于“第三方工具
  已获许可”**。官方 FAQ/订阅规则仍限制使用场景，因此真实开关默认关闭；代码与离线测试可以完成，
  真实调用仍等待官方许可或另行记录的风险决定。
- **Kimi 的 `User-Agent: KimiCLI/1.6` 伪装方案不再作为实现依据**（属于 L4 且有规避检测嫌疑）；
  本项目按 `MoonshotAI/kimi-code` 官方实现固定请求 `/coding/v1/usages`，不发送自定义 UA、不跟随
  重定向，并只在用户显式开启本地后端开关时读取项目专用环境变量。
- **Codex 没有公开托管 REST 额度 API，但已有官方本地 app-server 只读方法**。本项目采用
  `account/rateLimits/read`，让官方进程管理登录；仍禁止把 `wham/usage` 内部端点当稳定接口。

---

## 一、速查总表

| 服务 | 难度 | 鉴权 | 全平台支持 | 主端点 |
|------|------|------|----------|--------|
| **Codex** | ⭐⭐ | 由本机官方 Codex 管理，不交给项目 | 本机 FastAPI + stdio | `codex app-server` / `account/rateLimits/read` |
| **Kimi** | ⭐ | `sk-kimi-xxx` Bearer Key | ✅ 全平台直调 | `api.kimi.com/coding/v1/usages` |
| **GLM** | ⭐⭐⭐ | 官方插件使用 Coding Plan token 原值作为 `Authorization` | 本地后端代码可实现；第三方使用许可待确认 | `open.bigmodel.cn/api/monitor/usage/quota/limit` |

**重要修正（与初版 PLAN.md 不同）**：
- 下方 GLM endpoint 契约已被官方插件源码确认，但权限结论不能由契约反推；本项目保持默认关闭且未真实调用。
- **Kimi 必须用 `sk-kimi-xxx` key**（Kimi Code 平台），不是 `sk-xxx`（Kimi Open Platform）。
  两套 key 不通用。

---

## 二、Codex（OpenAI ChatGPT 套餐）

### 端点

| 用途 | URL | 方法 |
|------|-----|------|
| 主用量查询 | `https://chatgpt.com/backend-api/wham/usage` | GET |
| 累积恢复额度 | `https://chatgpt.com/backend-api/wham/rate-limit-reset-credits` | GET |
| Token 交换 | `https://chatgpt.com/api/auth/session` | GET |
| Token 刷新 | `https://auth.openai.com/oauth/token` | POST |

### 鉴权

```http
Authorization: Bearer <access_token>
chatgpt-account-id: <chatgpt_account_id>
```

凭据存在本地：`~/.codex/auth.json`，含字段：
- `access_token`（JWT，约 9 天有效期）
- `refresh_token`
- `id_token`
- `last_refresh`
- `chatgpt_account_id`（请求时要带的 header 值）

### 响应结构（关键字段）

```jsonc
{
  "plan_type": "plus",              // plus/pro/team/business/free
  "rate_limit": {
    "primary_window": {              // 5 小时窗口
      "limit_window_seconds": 18000,
      "used_percent": 42.5,
      "remaining_percent": 57.5,
      "reset_after_seconds": 12345,
      "resets_at": "2026-07-21T20:00:00Z",
      "is_unlimited": false
    },
    "secondary_window": {            // 7 天窗口
      "limit_window_seconds": 604800,
      "used_percent": 30.1,
      "remaining_percent": 69.9,
      "reset_after_seconds": 360000,
      "resets_at": "2026-07-25T00:00:00Z",
      "is_unlimited": false
    }
  },
  "credits": { ... }                 // 可选：累积恢复额度
}
```

### 注意

- JWT 中 `chatgpt_subscription_active_until` 字段决定订阅是否过期。
- Token 失效后需用 `refresh_token` 调 `/oauth/token` 刷新。
- 移动端/Web 端拿不到 `auth.json`，**必须后端代理**并安全存储 refresh_token。

---

## 三、Kimi（Moonshot AI） Coding Plan

### ⚠️ 两套平台不要混淆

| 平台 | Base URL | Key 格式 | 是否有套餐额度 API |
|------|---------|---------|-----------------|
| Kimi Open Platform（按量） | `api.moonshot.cn/v1` | `sk-xxx` | ❌ 只有余额，无套餐额度 |
| **Kimi Code Platform（套餐）** | **`api.kimi.com/coding/v1`** | **`sk-kimi-xxx`** | ✅ **完整额度 API** |

### 端点（L2 官方源码确认，2026-07-23）

```
GET https://api.kimi.com/coding/v1/usages
```

- 路径固定为 `/usages`（复数）。**旧调研所谓“`/usage` 单数自动 fallback”不成立**：
  官方 `MoonshotAI/kimi-cli`（Python）与 `MoonshotAI/kimi-code`（TS，已迁移）都只请求 `/usages`。
- Base URL 可经 `KIMI_CODE_BASE_URL` 覆盖（尾随斜杠会被剥离），默认即 `https://api.kimi.com/coding/v1`。
  这是官方工具自身的能力；Quota Watch 为避免把 Key 转发到任意地址，生产适配器固定使用官方 URL，
  不提供地址覆盖。

### 鉴权（L2 官方源码确认）

```http
Authorization: Bearer <api_key>
Accept: application/json
```

- ❗ **不需要、也不应设置 `User-Agent: KimiCLI/1.6`**。官方客户端不设任何自定义 UA，
  其测试（`packages/oauth/test/managed-usage.test.ts`）明确断言 `user-agent` 与
  `x-msh-platform` 均**不发送**。本文件旧版“必须伪装成官方 CLI”的结论**错误，已废弃**。
- 仅发送 `Authorization: Bearer <token>` 与 `Accept: application/json`。
- 鉴权失败：401 → “Authorization failed. Please check your API key.”；404 → “Usage endpoint not available.”
- 仅 `managed:kimi-code` provider 可用（key 前缀须为 `managed:` 且后缀为 `kimi-code`）。

### 响应结构（L2 官方源码确认；顶层是**对象**，不是数组）

❗ **重大修正**：旧调研写成 `{"data":[...]}` 数组形态是**错误的**（社区逆向失真）。官方解析器面对的是：

```jsonc
{
  "usage": {                       // 汇总行（如周额度），可选
    "name": "Weekly limit",
    "used": 40,
    "limit": 1000,
    "resetAt": "2025-12-23T05:24:18.443553353Z"   // ISO8601，可达纳秒精度
  },
  "limits": [                      // 各窗口额度，可选
    {
      "detail": { "used": 1, "limit": 100, "name": "5h limit" },
      "window": { "duration": 300, "timeUnit": "MINUTE" }
    }
  ],
  "boosterWallet": { ... }         // 仅 TS 解析器读取的额外付费包；Python 忽略
}
```

字段别名（解析器**故意宽松**，snake_case 与 camelCase 都接受）：

| 概念 | 优先字段 | 回退逻辑（L2 确认） |
|---|---|---|
| 已用 | `used`（int） | 缺失时 `used = limit - remaining`（需 `remaining`+`limit` 同时存在） |
| 上限 | `limit`（int，可接受 `"42"`/`42.0`） | — |
| 剩余 | `remaining`（仅作 `used` 回退） | — |
| 标签 | `name` → `title` →（limits 还查 `scope`） | 按窗口派生 `Nh/Nm/Nd/Ns limit`；汇总默认 `Weekly limit`，limits 默认 `Limit #N` |
| 重置时间 | `reset_at`/`resetAt`/`reset_time`/`resetTime`（ISO 字符串，优先） | 否则用 `reset_in`/`resetIn`/`ttl`/`window`（**整数秒**） |
| 窗口 | `limits[].window.duration`（int）+ `window.timeUnit`（`MINUTE`/`HOUR`/`DAY`...） | duration 也可能在 item 或 detail 上 |

关键解析规则（来自官方源码，避免离线解析器踩坑）：

- 一行同时缺失 `used` 与 `limit` 才丢弃；`used>limit` 时剩余钳为 0；`limit<=0` 时占比为 0。
- `reset_at` 类是 ISO 字符串（可达纳秒精度，解析器截断到微秒/毫秒）；`reset_in`/`ttl`/`window` 是**秒数**，不是时间戳。
- `limits[].window`（对象，窗口元数据）与行内 `window`（整数秒，重置回退）同名但语义不同，按嵌套层级区分。
- `boosterWallet` 金额为“百万分之一美分”定点数：`cents = value / 1_000_000`，仅当 `balance.type=="BOOSTER"` 且 `amount>0` 才解析。
- 已知外部 bug（issue #1569）提到的 `totalQuota` 字段恒为 99，**官方解析器不读取该字段**，不要依赖它。

### 官方样例（来自 `packages/oauth/test/managed-usage.test.ts`）

```jsonc
// 最小汇总
{ "usage": { "used": 40, "limit": 1000, "name": "Weekly limit" } }
// used 缺失 -> used = limit - remaining
{ "usage": { "remaining": 200, "limit": 1000 } }   // used=800
// 窗口派生标签 + detail 嵌套
{ "limits": [
    { "detail": { "used": 1, "limit": 100 }, "window": { "duration": 300, "timeUnit": "MINUTE" } }, // 5h limit
    { "detail": { "used": 2, "limit": 50 },  "window": { "duration": 24,  "timeUnit": "HOUR" } }     // 24h limit
] }
```

### 权威源码位置（L2）

- Python `MoonshotAI/kimi-cli`：`src/kimi_cli/ui/shell/usage.py`（`_usage_url`/`_fetch_usage`/`_parse_usage_payload`/`_to_usage_row`）、`src/kimi_cli/auth/platforms.py`（`_kimi_code_base_url`）、`src/kimi_cli/utils/aiohttp.py`（证实无自定义 UA，超时 120/60/15s）。
- TypeScript `MoonshotAI/kimi-code`：`packages/oauth/src/managed-usage.ts`（`DEFAULT_KIMI_CODE_BASE_URL`/`parseManagedUsagePayload`/`toUsageRow`/`parseBoosterWallet`）、`packages/oauth/test/managed-usage.test.ts`（样例 + 断言不发送 UA）。

### ⚠️ 已废弃的旧版猜测（2026-07-21 社区逆向，已被 L2 源码推翻）

下方是初版基于社区逆向的猜测，**多处与官方源码不符**，仅保留作对照，**不得作为实现依据**：

- 旧猜测顶层为 `{"data":[...]}` 数组 → **错**：官方是 `{usage, limits, boosterWallet}` 对象。
- 旧猜测 `used_amount`/`limit_amount`/`model_name` 为字段 → 官方解析器**不读取**这些名。
- 旧猜测 `resetTime` 可能是 unix 秒 → **错**：`resetTime`/`resetAt` 是 ISO 字符串；秒数用的是 `reset_in`/`ttl`/`window`。
- 旧 curl 示例要求 `User-Agent: KimiCLI/1.6` → **错**：官方不设 UA（见上）。

```jsonc
// 已废弃示例（社区逆向失真，勿用）
{
  "data": [ { "model_name": "all", "used": 320000000, "limit": 1000000000, "resetTime": "..." }, ... ]
}
```

### curl 示例（L2 修正版）

```bash
curl -s 'https://api.kimi.com/coding/v1/usages' \
  -H 'Authorization: Bearer <KIMI_CODE_API_KEY>' \
  -H 'Accept: application/json'
# 不需要 User-Agent
```


### 如果只有 Open Platform key

只能查余额，不能查套餐：

```
GET https://api.moonshot.cn/v1/users/me/balance   # 国内
GET https://api.moonshot.ai/v1/users/me/balance   # 国际
```

```jsonc
{ "code": 0, "data": {
  "available_balance": 1234.56,
  "cash_balance": 1000.00,
  "voucher_balance": 234.56
}}
```

⚠️ `.cn` key 必须打 `.cn`，`.ai` key 必须打 `.ai`，交叉返回 401。

---

## 四、GLM（智谱 / bigmodel.cn / Z.ai）Coding Plan

### 三个监控端点

| 用途 | URL |
|------|-----|
| **套餐额度** | `GET https://open.bigmodel.cn/api/monitor/usage/quota/limit` |
| 模型用量 | `GET https://open.bigmodel.cn/api/monitor/usage/model-usage` |
| MCP/工具用量 | `GET https://open.bigmodel.cn/api/monitor/usage/tool-usage` |

国际镜像：`https://api.z.ai/api/monitor/usage/quota/limit`（路径相同）

### L2 官方源码与脱敏当前结构确认（2026-07-23）

官方插件 `plugins/glm-plan-usage/skills/usage-query-skill/scripts/query-usage.mjs` 证实下列契约：

- **双 host 按 `ANTHROPIC_BASE_URL` 切换**：含 `z.ai` → `api.z.ai`，否则（默认）→ `open.bigmodel.cn`；路径均为 `/api/monitor/usage/quota/limit`。
- **header**：把 `ANTHROPIC_AUTH_TOKEN` 的值原样赋给 `Authorization`，并显式设置
  `Accept-Language: en-US,en` 与 `Content-Type: application/json`；该脚本没有设置自定义 User-Agent。
- **当前官方插件处理**：`TOKENS_LIMIT` 直接保留服务端 `percentage`；`TIME_LIMIT` 保留
  `percentage/currentValue/usage/usageDetails`。插件没有为客户端重新计算百分比。
- **脱敏真实字段形状**：`data.limits` 当前稳定返回三条；两条 `TOKENS_LIMIT` 的 unit 分别为
  3（5h）和 6（周），字段是 `number/percentage/nextResetTime`，不含历史
  `usage/currentValue`；`TIME_LIMIT` 当前 unit 为 5，并带 `percentage/remaining/usageDetails`。
- **当前百分比解释**：官方插件只透传 `percentage`，ZCode 页面“剩余额度”的标题不足以证明原始
  字段方向。用户用 ZCode 做了不提供数值的方向对照，确认 5 小时、每周和工具调用三项的
  `percentage` 都是**已用比例**。当前契约因此直接使用 `used = percentage`，展示层再计算
  `remaining = 100 - used`；不得用账号实际数值写特例。
- **历史契约兼容**：旧样例中的 `usage` = 上限、`currentValue` = 已用；仅在这两个绝对字段存在时
  沿用旧换算。
- **`nextResetTime`**：官方用 `>1e12` 启发式——数值 `>1e12` 视为毫秒，`<=1e12` 视为秒，非数字则 `Date.parse`（ISO）。ZHIPU 通常返回毫秒，z.ai 部分时段返回 ISO。
- **范围保护**：当前“已用比例”必须处于 0～100；超出范围直接报告契约变化，不静默钳制。历史绝对
  契约仍允许 used 超过 limit 并提示超额。
- **历史默认值限制**：只有旧形状存在 `currentValue` 且 unit=3、`usage` 缺失/0 时，才使用旧插件
  的 40,000,000 token 默认上限；当前百分比形状禁止套用该默认值。
- **响应包络**：容忍 `data.code/data.limits`（ZHIPU）或顶层 `code/limits`（旧/z.ai）两种形态。

### ZCode 能否作为 Quota Watch 数据源

ZCode 是官方支持工具，官方“使用统计”页可在“编程套餐”模式读取 Z.ai/BigModel 的 5 小时、每周、
月度 MCP、模型与工具用量，适合由用户人工核对 Quota Watch 的结果。但本轮查阅的 ZCode 官方
Usage Stats 与 Configuration 文档没有提供额度导出、CLI 命令或本地只读 API。

因此本项目不读取 ZCode 私有数据库、缓存、Token、Cookie、日志或网络流量，也不把“进程正在运行”
当成授权。若后续 ZCode 发布机器可读接口，再单独建立 `ZCodeQuotaAdapter` 任务卡。

### ⚠️ 合规提醒（默认禁用真实调用）

官方插件是 L2，但 GLM Coding Plan 的官方 FAQ 明确套餐“仅限官方指定工具”，非指定工具调用不享用套餐额度。
因此本项目的 GLM 真实查询**默认禁用**。`GlmProviderAdapter` 与 `all_real` 已在用户授权的任务卡内
完成代码和离线验证。后续一次用户明确授权的本机脱敏检查仅用于验证字段结构和修复契约漂移，不代表
智谱授权第三方公开监控。Codex 已改走官方本地 app-server（仍默认关闭），与本节的 GLM 端点和凭据
方案无关；Kimi 的授权也不能自动扩展到 GLM。

### 鉴权

```http
Authorization: <CODING_PLAN_API_KEY_OR_AUTH_VALUE>
Accept-Language: en-US,en
Content-Type: application/json
```

⚠️ **必须用 Coding Plan 专用 key**（在 `个人编程套餐 > 套餐概览` 创建），
**不要用按量付费 key**。两者 base URL 也不同：

| 用途 | Base URL |
|------|---------|
| Coding Plan 调用（消耗套餐） | `https://open.bigmodel.cn/api/coding/paas/v4` |
| 按量付费（消耗余额） | `https://open.bigmodel.cn/api/paas/v4` |
| Anthropic 协议 Coding Plan | `https://open.bigmodel.cn/api/anthropic` |

### 当前响应字段形状（虚构数值示例）

```jsonc
{
  "code": 0,
  "msg": "success",
  "success": true,
  "data": {
    "level": "test-plan",
    "limits": [
      {
        "type": "TOKENS_LIMIT",
        "unit": 3,                       // 3 = 5 小时窗口
        "number": 111,
        "percentage": 75,                // 服务端比例；示例值完全虚构
        "nextResetTime": 1700000000000   // Unix 毫秒！
      },
      {
        "type": "TOKENS_LIMIT",
        "unit": 6,                       // 6 = 周窗口
        "number": 222,
        "percentage": 50,
        "nextResetTime": 1700500000000
      },
      {
        "type": "TIME_LIMIT",
        "unit": 5,                       // 当前 MCP/工具窗口
        "number": 333,
        "percentage": 25,
        "remaining": 456,
        "usage": 999,
        "currentValue": 123,
        "nextResetTime": 1700600000000,
        "usageDetails": [ { "type": "test-tool" } ]
      }
    ]
  }
}
```

### 字段含义对照表

| `type` | `unit` | 含义 |
|--------|--------|------|
| `TOKENS_LIMIT` | `3` | **5 小时 token 额度**（主短窗口） |
| `TOKENS_LIMIT` | `6` | **周 token 额度**（新套餐） |
| `TIME_LIMIT` | `5`（当前）/`0`（历史） | **MCP/工具用量**（月级，含 web_search 等） |

- `nextResetTime` 是 **Unix 毫秒**（除以 1000 得秒）
- 当前 TOKENS_LIMIT 不提供可靠绝对 token 上限，因此统一以百分比显示，不伪造 token 数值。
- 当前形状的 `percentage` 直接作为服务端已用比例；5 小时、每周和工具调用三项均不取反。
- 历史 `usage/currentValue` 形状仍按绝对上限/已用兼容；40,000,000 默认值只适用于该历史分支。

### 计费规则（影响额度消耗速度）

- 高峰时段扣 **3×**，非高峰扣 **2×**
- 5 小时窗口重置
- 额度用完返回 HTTP 429 `"insufficient balance"`，**不会**自动扣账户余额

### curl 示例

```bash
curl -s 'https://open.bigmodel.cn/api/monitor/usage/quota/limit' \
  -H 'Authorization: <CODING_PLAN_API_KEY_OR_AUTH_VALUE>' \
  -H 'Accept-Language: en-US,en' \
  -H 'Content-Type: application/json'
```

此示例只描述官方插件的 wire contract，不是让用户现在执行真实查询。

---

## 五、统一的"归一化数据模型"（给前后端用）

不论哪家服务，后端最终吐给前端的数据都归一成这个结构，前端只认它：

```typescript
interface ProviderQuota {
  provider: 'codex' | 'kimi' | 'glm';
  planName: string;            // "ChatGPT Plus" / "Kimi Moderato" / "GLM Pro"
  planType?: string;           // 原始 plan_type，可选
  expiresAt?: string;          // ISO 时间，订阅到期日（Codex JWT 里有，Kimi/GLM 可能没有）
  windows: QuotaWindow[];
  fetchedAt: string;           // 本次查询时间
  status: 'ok' | 'degraded' | 'error';
  errorMessage?: string;
}

interface QuotaWindow {
  label: string;               // "5 小时窗口" / "周窗口"
  used: number;
  limit: number;
  unit: 'tokens' | 'percent' | 'calls';
  resetAt: string;             // ISO 时间
  resetsInSeconds: number;     // 距离重置的秒数（前端做倒计时用）
}
```

---

## 六、风险登记

| 风险 | 影响 | 缓解 |
|------|------|------|
| 官方/开源契约仍可能随版本漂移 | 单家查询失败 | 解析器契约测试、超时和 `status: 'error'`；综合模式隔离单家失败 |
| Codex 登录失效或 app-server 协议变化 | Codex 查询失败 | 由官方进程管理登录；项目不读取或刷新 token，失败时给出安全提示 |
| Kimi 旧调研要求伪装 User-Agent | 误导实现、有规避检测嫌疑 | **已废弃**：L2 源码证实官方不设 UA、且测试断言不发送 UA；只发 `Authorization`+`Accept`（见 §三） |
| GLM 计费 3×/2× | 用户看到的"已用"可能跳变 | UI 注明"按服务端计费规则" |
| GLM endpoint 有技术契约但第三方权限未确认 | 违反套餐使用边界 | 真实开关默认关闭；只做离线测试，ZCode 暂作人工对照 |
| Key 类型用错（Coding vs PAYG） | 鉴权失败 / 扣错账户 | 设置页明确标注 key 类型，加文档说明 |
| Key 泄漏 | 账户被盗 | 当前仅从本地后端进程环境读取；Flutter 不持有，且不写 Git、日志、截图或响应 |

---

## 七、参考实现（可直接学源码）

| 项目 | 语言 | 平台覆盖 | 价值 |
|------|------|---------|------|
| [zai-org/zai-coding-plugins](https://github.com/zai-org/zai-coding-plugins) | JavaScript | Claude Code 插件 | **GLM 官方实现**，用于确认请求与响应契约 |
| [MoonshotAI/kimi-code](https://github.com/MoonshotAI/kimi-code) | TypeScript | Kimi Code | **Kimi 官方实现**，用于确认 usages 契约 |
| [Golden0Voyager/kimi-code-usage](https://github.com/Golden0Voyager/kimi-code-usage) | Python | CLI + MCP + VSCode | Kimi 社区实现，仅作补充参考 |
| [jukanntenn/glm-plan-usage](https://github.com/jukanntenn/glm-plan-usage) | Rust | CLI | GLM 响应结构 serde 定义 |
| [guyinwonder168/opencode-glm-quota](https://github.com/guyinwonder168/opencode-glm-quota) | TypeScript | opencode 插件 | GLM 端点表 + 解析器 |
| [JinHanAI/coding-plan-monitor](https://github.com/JinHanAI/coding-plan-monitor) | — | CLI | 多平台聚合（MiniMax + GLM）参考 |
| [steipete/CodexBar](https://github.com/steipete/CodexBar) | — | 菜单栏 | Codex + 多平台聚合参考 |

---

## 八、2026-07-25：安全配置、Codex 重置次数与 Android 边界

### CC Switch 中可借鉴与不可照搬的部分

参考 [CC Switch 仓库](https://github.com/farion1231/cc-switch) 与其
[配置文件说明](https://github.com/farion1231/cc-switch/blob/main/docs/user-manual/en/5-faq/5.1-config-files.md)：

- 可借鉴：按 Provider 建立配置档案、用单一来源描述当前配置、元数据原子写入、切换后立即生效。
- 不照搬：Quota Watch 不把可同步的 SQLite 当作 Key 仓库，也不导入其他客户端的配置文件。
- 本项目实现：Kimi / GLM Key 只写入 Windows Credential Manager；本地 JSON 只保存标签和 Codex
  手动重置备注。环境变量仍优先，设置页保存的 Key 作为安全回退。

### Codex “可重置次数”契约结论

OpenAI 帮助中心公开说明符合条件的 Codex 用户可能看到 banked rate-limit resets、可用次数与活动
到期信息，但这不等于本机 app-server 已公开同样的机器可读字段：

- [Using Codex with your ChatGPT plan](https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan)
- [Codex referral promotions](https://help.openai.com/en/articles/20001271-codex-referral-promotions)

使用本机官方 `codex-cli 0.130.0-alpha.5` 执行
`codex app-server generate-json-schema --experimental` 后，当前
`GetAccountRateLimitsResponse` 的 `CreditsSnapshot` 只有：

```text
hasCredits
unlimited
balance
```

生成的完整 Schema 中没有 `resetCount`、banked reset 或对应 expiration 字段。因此本阶段不调用
网页内部接口、不读取私有缓存，也不猜测值。统一契约新增独立的可选对象：

```typescript
interface ResetAllowance {
  count: number;
  expiresAt?: string;
  source: 'provider' | 'manual';
}
```

当前 UI 只从 loopback 设置 API 接受 `source='manual'` 的本机非敏感记录，并显示“手动记录”。
以后官方 app-server 若正式增加字段，可以新增 `source='provider'` 解析分支和契约测试。

### Android 网络与凭据边界

Flutter 官方网络文档要求 Android 声明 `INTERNET` 权限：
[Flutter networking](https://docs.flutter.dev/data-and-backend/networking)。

本项目采用“Android 伴随端”而不是“把后端塞进 APK”：

- APK 只包含 Flutter 客户端，不包含 Python 后端或 Provider Key。
- 远程后端必须使用 HTTPS；Android Network Security Config 只允许
  `127.0.0.1` / `localhost` 使用明文 HTTP。
- 本地真机开发使用 `adb reverse tcp:8000 tcp:8000`，仍访问
  `http://127.0.0.1:8000`。
- 不把 FastAPI 配置写接口无鉴权暴露到局域网/公网；若未来要远程多用户访问，必须另做认证、
  TLS、授权和密钥托管设计。

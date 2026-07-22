# 三家 Coding Plan 额度查询 API 调研报告

> 调研日期：2026-07-21
> 用途：本项目的核心数据源参考。所有端点、鉴权、JSON 字段均来自开源工具逆向 + 官方插件确认。
> ⚠️ 除 Kimi Open Platform balance 外，**没有任何一家提供公开文档化的额度查询 API**——
> 全部依赖社区逆向接口，随时可能失效。代码必须做容错降级。
>
> **实现状态（2026-07-22）：** 本文件只是研究记录。Quota Watch 当前仍使用 Mock 数据，没有后端或
> 真实额度适配器。Codex 中配置的 `kimi_worker` / `glm_worker` 调用的是辅助开发模型，不能视为
> 本项目已接入 Kimi/GLM 额度查询。真实接口实验推迟到学习计划阶段 6～7。

---

## 一、速查总表

| 服务 | 难度 | 鉴权 | 全平台支持 | 主端点 |
|------|------|------|----------|--------|
| **Codex** | ⭐⭐ | OAuth Bearer token | 桌面直读，移动/Web 需后端代理 | `chatgpt.com/backend-api/wham/usage` |
| **Kimi** | ⭐ | `sk-kimi-xxx` Bearer Key | ✅ 全平台直调 | `api.kimi.com/coding/v1/usages` |
| **GLM** | ⭐⭐⭐ | Bearer Key（Coding Plan 专用） | ✅ 全平台直调 | `open.bigmodel.cn/api/monitor/usage/quota/limit` |

**重要修正（与初版 PLAN.md 不同）**：
- **GLM 也有公开的 Bearer Key 鉴权**，不需要 Cookie 抓取！只要用 **Coding Plan 专用 key**
  （在 `个人编程套餐 > 套餐概览` 创建），不要用按量付费 key。
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

### 端点

```
GET https://api.kimi.com/coding/v1/usages
```

（备用：`/usage` 单数形式，客户端会自动 fallback）

### 鉴权

```http
Authorization: Bearer sk-kimi-xxxxxxxxxxxxxxxx
User-Agent: KimiCLI/1.6       # ⚠️ 必须伪装成官方 CLI，否则可能被拒
```

### 响应结构（数组形态，当前主版本）

```jsonc
{
  "data": [
    {
      "model_name": "all",
      "name": "Weekly Usage",
      "used": 320000000,
      "limit": 1000000000,
      "resetTime": "2026-07-28T00:00:00Z"
    },
    {
      "model_name": "kimi-for-coding",
      "name": "5h Limit",
      "used": 12000000,
      "limit": 40000000,
      "used_amount": 12000000,
      "limit_amount": 40000000,
      "duration": 5,
      "timeUnit": "HOUR",
      "resetTime": 1700000000,         // 可能是 unix 秒，也可能是 ISO 字符串
      "reset_in": 7200                  // 备选：N 秒后重置
    }
  ]
}
```

### 字段别名（解析器需兼容）

| 概念 | 可能的字段名（按优先级） |
|------|----------------------|
| 已用 | `used` → `used_amount` → `limit - remaining` |
| 上限 | `limit` → `limit_amount` |
| 剩余 | `remaining` |
| 重置时间 | `resetTime` → `reset_at` → `reset_time` → `reset_in`(秒) |
| 标签 | `name` → `title` → `model_name` |
| 窗口 | `duration` + `timeUnit`(`MINUTE`/`HOUR`/`DAY`/`MONTH`) |

### 旧版/对象形态（fallback）

```jsonc
{
  "usage": { "used": 320000000, "limit": 1000000000, "name": "Weekly Usage" },
  "limits": [
    { "detail": { "used": 12000000, "limit": 40000000 },
      "window": { "duration": 5, "timeUnit": "HOUR" } }
  ]
}
```

### curl 示例

```bash
curl -s 'https://api.kimi.com/coding/v1/usages' \
  -H 'Authorization: Bearer sk-kimi-YOUR_KEY' \
  -H 'User-Agent: KimiCLI/1.6'
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

### 鉴权

```http
Authorization: Bearer <CODING_PLAN_API_KEY>
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

### 响应结构

```jsonc
{
  "code": 0,
  "msg": "success",
  "success": true,
  "data": {
    "limits": [
      {
        "type": "TOKENS_LIMIT",
        "unit": 3,                       // 3 = 5 小时窗口
        "usage": 40000000,               // 上限
        "currentValue": 12345678,        // 已用
        "percentage": 31,                // 服务器算好的百分比
        "nextResetTime": 1700000000000   // Unix 毫秒！
      },
      {
        "type": "TOKENS_LIMIT",
        "unit": 6,                       // 6 = 周窗口
        "usage": 280000000,
        "currentValue": 89000000,
        "percentage": 32,
        "nextResetTime": 1700500000000
      },
      {
        "type": "TIME_LIMIT",
        "unit": 0,                       // MCP/工具，月级
        "usage": 100,
        "currentValue": 30,
        "percentage": 30,
        "nextResetTime": null,
        "usageDetails": { ... }
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
| `TIME_LIMIT` | `0` | **MCP/工具用量**（月级，含 web_search 等） |

- `nextResetTime` 是 **Unix 毫秒**（除以 1000 得秒）
- `percentage` 可能 > 100（超额时）
- 默认 5h token 上限（响应缺失时用）：`40,000,000` tokens

### 计费规则（影响额度消耗速度）

- 高峰时段扣 **3×**，非高峰扣 **2×**
- 5 小时窗口重置
- 额度用完返回 HTTP 429 `"insufficient balance"`，**不会**自动扣账户余额

### curl 示例

```bash
curl -s 'https://open.bigmodel.cn/api/monitor/usage/quota/limit' \
  -H 'Authorization: Bearer YOUR_CODING_PLAN_KEY' \
  -H 'Accept-Language: en-US,en' \
  -H 'Content-Type: application/json'
```

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
| 三家都是逆向接口，可能失效 | 单家查询失败 | `status: 'error'`，UI 显示"暂不可查"，不影响其他家 |
| Codex token 9 天过期 | Codex 查询 401 | 后端用 refresh_token 自动刷新，失败引导重新登录 |
| Kimi 必须伪装 User-Agent | 被 403 | 写死 `User-Agent: KimiCLI/1.6` |
| GLM 计费 3×/2× | 用户看到的"已用"可能跳变 | UI 注明"按服务端计费规则" |
| Key 类型用错（Coding vs PAYG） | 鉴权失败 / 扣错账户 | 设置页明确标注 key 类型，加文档说明 |
| Key 泄漏 | 账户被盗 | 后端加密存储；移动端 key 经后端转发，不直接持有 |

---

## 七、参考实现（可直接学源码）

| 项目 | 语言 | 平台覆盖 | 价值 |
|------|------|---------|------|
| [Golden0Voyager/kimi-code-usage](https://github.com/Golden0Voyager/kimi-code-usage) | Python | CLI + MCP + VSCode | Kimi 实现的权威参考 |
| [jukanntenn/glm-plan-usage](https://github.com/jukanntenn/glm-plan-usage) | Rust | CLI | GLM 响应结构 serde 定义 |
| [guyinwonder168/opencode-glm-quota](https://github.com/guyinwonder168/opencode-glm-quota) | TypeScript | opencode 插件 | GLM 端点表 + 解析器 |
| [zai-org/zai-coding-plugins](https://github.com/zai-org/zai-coding-plugins) | — | Claude Code 插件 | **GLM 官方实现**，最权威 |
| [JinHanAI/coding-plan-monitor](https://github.com/JinHanAI/coding-plan-monitor) | — | CLI | 多平台聚合（MiniMax + GLM）参考 |
| [steipete/CodexBar](https://github.com/steipete/CodexBar) | — | 菜单栏 | Codex + 多平台聚合参考 |

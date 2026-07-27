# 阶段 6 / 卡 1：Provider Adapter 接口、缓存与本地架构设计

> 状态：**基础设计已验证；Codex/Kimi 真实纵切片、GLM 默认关闭适配器与综合模式均已实施**。
> 本文件主体记录最初的离线设计；当前实现以 `STAGE6_CODEX_REAL_TASK.md`、
> `STAGE6_KIMI_REAL_TASK.md` 和 `STAGE7_GLM_REAL_AND_ALL_REAL_TASK.md` 为准。GLM 仍未发起真实请求。
> 依据：`docs/POST_AGENT_AB_INTEGRATION_TASKS.md` 第 7 节、`docs/API_RESEARCH.md` 第零节（2026-07-23 复核）。
> 创建：2026-07-23。

## 1. 产品目标回顾（已确认）

```text
首次完成各平台授权或配置
        ↓
Codex / Kimi / GLM 客户端可以关闭
        ↓
打开 Quota Watch 或点击刷新
        ↓
本地 FastAPI 按需查询
        ↓
缓存最后成功结果和 fetchedAt
        ↓
Flutter 显示最新值，失败时显示旧值与“数据可能已过期”
```

“各 Coding 软件关闭前记录一次”只能作为缓存补充，不能作为主数据源（异常退出、多设备共享额度、
额度窗口在软件关闭时仍会重置）。

## 2. 官方支持矩阵（2026-07-23 复核，详见 API_RESEARCH.md 第零节）

| Provider | 自动查询可行性 | 默认状态 | 凭据/合规约束 |
|---|---|---|---|
| **Codex** | ✅ 官方本地 `codex app-server` 提供 `account/rateLimits/read`；不是公开托管 REST API | 已实现，但由 `QUOTA_WATCH_CODEX_REAL=1` 默认关闭 | 登录由官方本机进程管理；项目不读 `auth.json`，不采用内部 `wham/usage` |
| **Kimi Code** | ⚠️ 官方允许会员创建 API Key 用于第三方平台；额度 JSON 契约来自官方开源实现，未公开文档化 | 已实现，由 `QUOTA_WATCH_KIMI_REAL=1` 默认关闭；脱敏真实读取已通过，待 UI 验收 | 项目专用变量 `QUOTA_WATCH_KIMI_API_KEY`；**禁止** UA 伪装、重定向和可覆盖生产地址 |
| **GLM Coding Plan** | ⚠️ 官方插件源码确认 quota endpoint 契约（L2），但 FAQ/订阅规则没有明确授权第三方监控工具 | Adapter 与综合模式已实现并离线验证，由 `QUOTA_WATCH_GLM_REAL=1` 默认关闭；无真实请求 | 项目专用变量 `QUOTA_WATCH_GLM_API_KEY`；不读取 ZCode/worker；真实调用等待许可或另行决策 |

**关键合规结论**：阶段 6 的“首家本地实验”必须先获得用户对**某一家**的再次明确授权，并在实验卡中
写明：为何该家的查询方式不违反其官方“仅限指定工具/用途”规则，或明确接受其属于灰色研究。

## 3. 统一数据契约（沿用现有，不新增专有字段）

复用 `backend/app/models.py` 的 `ProviderQuota` / `QuotaWindow`（已含 `fetched_at`、`status`、
`error_message`）。Adapter 只负责把某家的原始响应**归一**成这个契约，不向前端泄漏专有字段。

新增内部字段（不进 JSON，仅后端/缓存使用）：

```python
class CachedQuota:
    provider: ProviderName
    quota: ProviderQuota          # 最后一次成功结果（status == "ok" 或 "degraded"）
    fetched_at: datetime          # 该成功结果的获取时间（UTC）
    last_error: ProviderQuota | None  # 最近一次失败（status == "error"），用于诊断
    last_error_at: datetime | None
```

**实现进度（2026-07-23）**：`QuotaAggregator` 已落地 `_cache`（最后成功快照）与
`_last_errors`（每家最近一次失败的异常类型名+归一化文案+时间），通过只读 `last_error(provider)` 供
后端诊断；不含原始敏感响应、不进入前端 JSON（6 个测试覆盖）。

## 4. Provider Adapter 接口（设计已实现）

```python
# backend/app/providers/base.py （本卡只定义，可用 Fake 实现；真实实现等授权）
from typing import Protocol

class ProviderAdapter(Protocol):
    """每家 Provider 的只读额度查询适配器。"""

    @property
    def provider(self) -> ProviderName: ...

    def fetch(self) -> ProviderQuota:
        """
        发起一次查询并返回归一化后的 ProviderQuota。
        - 成功：status = "ok"（或 "degraded" 当部分窗口缺失）。
        - 鉴权失败(401/403)：抛 PermissionError；由聚合层转成 status="error" + 引导文案。
        - 限流(429)：抛 RateLimitError；返回降级数据 + 提示。
        - 超时/契约变化：抛 ContractError；单家失败不拖垮其他家。
        - 绝不打印、日志或返回原始敏感响应；只归一化后的结构化错误。
        """
        ...
```

错误归一化映射（统一前端文案）：

| 原始情况 | 抛出异常 | 归一 status | 用户文案 |
|---|---|---|---|
| 正常 | — | `ok` | 正常 |
| 部分窗口缺失 | — | `degraded` | 部分可用 |
| 401/403 | `PermissionError` | `error` | 需要重新登录/检查凭据 |
| 429 | `RateLimitError` | `error`（用旧值 + 过期提示） | 查询过于频繁，稍后重试 |
| 超时 | `TimeoutError` | `error`（用旧值 + 过期提示） | 查询超时 |
| 响应结构变化 | `ContractError` | `error` | 服务商接口可能已变化 |
| 断网 | `ConnectionError` | `error` | 无法连接 |

## 5. 缓存与过期判断（设计）

```text
刷新请求
   ↓
并行 fetch 三家（每家独立 try/except，单家失败不阻塞其他家）
   ↓
每家：成功 -> 写入 CachedQuota.quota + fetched_at
      失败 -> 若有旧值 -> 返回旧值 + status="error" + “数据可能已过期”(基于 fetched_at)
              无旧值 -> 返回 status="error" + errorMessage
   ↓
聚合层返回 [ProviderQuota...]，每条带 fetched_at
   ↓
Flutter：fetched_at 距今 > 阈值(如 6 小时) -> 显示“数据可能已过期”标记
```

过期判断（前端）：`now - fetched_at > staleness_threshold`（可配置，默认 6h）。
缓存仅存于本地后端内存/本地文件，**不进 Git、不进日志原文、不进截图**。

## 6. 测试方案（本卡可立即实现，全部离线）

使用 Fake Adapter + Fixture，不发起真实请求：

1. `FakeProviderAdapter`：可注入预设 `ProviderQuota` 或受控异常（401/429/超时/契约变化）。
2. 聚合层测试：三家并行，单家抛异常时其他家仍返回；401→引导文案；429/超时→旧值+过期提示。
3. 缓存测试：成功写缓存；失败有旧值返回旧值+过期；无旧值返回 error。
4. 过期判断测试：`fetched_at` 旧的返回“可能已过期”。
5. 契约漂移测试：故意改字段，确认抛 `ContractError` 而非崩溃。

**禁止**：真实请求、读取 `auth.json`、要求用户粘贴凭据、在产物里放秘密。

## 7. 本卡完成标准（Definition of Done）

- [x] 三家官方支持矩阵有带日期（2026-07-23）的官方证据（见 API_RESEARCH.md 第零节）。
- [x] 数据契约和缓存设计覆盖成功、401/403、429、超时、契约变化、单家失败（本文件第 3～5 节）。
- [x] App 启动刷新、手动刷新、最后成功快照和过期提示有明确验收标准（第 5 节）。
- [x] 本设计卡未发起真实 Provider 请求，未接触任何凭据。
- [x] 后续真实任务只选择 Codex，并获得用户“先接入 Codex”的明确授权。

## 8. 首家候选确认与字段映射（2026-07-23 L2 源码研究）

### 8.1 初始候选：Kimi Code（已被后续 Codex 官方能力更新取代）

合规性最清晰：Kimi 官方文档（L1）明确“允许在官方客户端**和第三方平台**使用权益”，且额度查询
端点 `/coding/v1/usages` 与 JSON 契约已由官方开源 CLI 源码（L2）确认，**不需要任何 UA 伪装**。
这是发现官方 app-server 额度方法之前的候选结论。用户随后选择“先接入 Codex”，项目又从官方
app-server 文档和本机生成 Schema 确认 `account/rateLimits/read`，所以实际首家改为 Codex。之后用户
另行授权 Kimi；其默认关闭的真实适配器与 Flutter 场景现已完成自动验证和脱敏真实结构读取，等待 UI 验收。

### 8.2 Kimi `/coding/v1/usages` 字段映射（L2 证据，详见 API_RESEARCH.md §三）

请求：`GET https://api.kimi.com/coding/v1/usages`，header 仅 `Authorization: Bearer <key>` + `Accept: application/json`。

响应顶层是**对象** `{usage?, limits[]?, boosterWallet?}`。归一到 `QuotaWindow` 的映射：

| `QuotaWindow` 字段 | 来源（L2 确认） | 回退 |
|---|---|---|
| `label` | `usage.name` / `limits[].detail.name` → `title` → `scope` → 窗口派生 `Nh/Nm/Nd limit` | `Weekly limit`(汇总) / `Limit #N`(limits) |
| `used` | `used`（int） | 缺失时 `limit - remaining`（需二者都在） |
| `limit` | `limit`（int，接受 `"42"`/`42.0`） | — |
| `unit` | 固定 `tokens`（Kimi 套餐为 token 额度） | — |
| `reset_at` | `reset_at`/`resetAt`/`reset_time`/`resetTime`（ISO 字符串，可达纳秒精度，截断到微秒） | 用 `reset_in`/`resetIn`/`ttl`/`window`（**秒数**）推算 |
| `note` | 可选，写入派生说明 | — |

解析规则（离线解析器须遵守）：

- `usage` 行 → 一个 `QuotaWindow`（汇总，默认 label `Weekly limit`）。
- `limits[]` 每项 → 一个 `QuotaWindow`；quota 行读自 `item.detail`（无则读 `item` 本身）。
- 一行同时缺 `used` 与 `limit` 才丢弃。
- `used > limit` 时剩余钳为 0；`limit <= 0` 时占比为 0（不写负数/除零）。
- `resetAt` 类是 ISO 字符串；`reset_in`/`ttl`/`window` 是秒数，不是时间戳，二者按字段名区分。
- `boosterWallet`（TS 扩展，定点数金额）本期**不解析**，留待产品化阶段；Python 解析器也忽略它。
- **不读取** `totalQuota`（issue #1569 的 bug 字段）、`used_amount`/`limit_amount`/`model_name`（旧社区猜测名）。

### 8.3 凭据与安全边界（真实实验卡必须遵守）

- Key 类型：`sk-kimi-xxx`（Kimi Code 套餐 key），**不是** Kimi Open Platform 的 `sk-xxx`。
- 凭据只由本地后端从**用户指定的本地配置位置/环境变量**读取；**不进 Flutter 公共客户端、不进 Git、不进日志/截图/Fixture**。
- 不要求用户在对话中粘贴真实 key；实验卡只使用占位符。
- 不伪装 User-Agent；只发 `Authorization` + `Accept`。

## 9. 任务卡序列

### 卡 2（已完成，离线）：聚合层与缓存骨架
已实现 `backend/app/providers/{base,fake,aggregator}.py` + 14 个离线测试（`test_aggregator.py`），
覆盖单家失败隔离、401/429/超时/契约变化归一化、缓存回退与过期判断。**无真实请求、无凭据。**

### 卡 3（代码、自动验证与脱敏真实读取完成）：Kimi 真实本地最小实验

用户已明确授权，实施记录与最终边界见 `STAGE6_KIMI_REAL_TASK.md`。下方保留最初任务卡文本，作为
“先定义范围、再实现”的过程证据。

```markdown
任务卡：阶段 6 / 卡 3 / Kimi 额度查询本地最小实验
目标：用官方 L2 契约实现 KimiQuotaParser（离线 Fixture 测试通过后），再加一个可关闭的
  KimiProviderAdapter（真实请求，但只在用户本机、用户授权后、读取本地凭据）。
范围：
- backend/app/providers/kimi_parser.py（离线解析器 + Fixture 测试，先做且可独立验收）
- backend/app/providers/kimi_adapter.py（真实请求，默认禁用，需显式开启）
- 凭据读取：仅从用户指定的本地环境变量/配置文件；不进 Git/日志/截图
非目标：
- 不接 Codex / GLM；不改前端契约；不实现 boosterWallet；不部署。
前置：用户明确授权“仅在本机对 Kimi 做真实最小实验”。
验收：
- kimi_parser 离线测试覆盖：usage 行、limits 行、used 缺失走 remaining 回退、resetAt ISO、
  reset_in 秒数、used>limit 钳制、字段缺失丢弃行、totalQuota 被忽略。
- 401 → AuthError；429 → RateLimitError；超时 → ProviderTimeoutError；结构剧变 → ContractError。
- 真实请求路径默认禁用；开启后只读本地凭据，日志不含 key/Bearer/响应原文。
- 单家失败（Kimi）不拖垮其他两家（聚合层已验证）。
凭据规则（告诉用户）：
- 准确环境变量名（如 QUOTA_WATCH_KIMI_API_KEY），由用户本人在本地设置，不进对话。
- 该变量不会被 Git 收集（已在 .gitignore 覆盖 .env*）。
- 后端只在请求时读取，不打印、不写日志、不返回给前端。
```

### 卡 4（代码与离线验证完成）：GLM 默认关闭适配器与综合实际额度

用户已明确授权建立任务卡和实现代码；边界与完成证据见
`STAGE7_GLM_REAL_AND_ALL_REAL_TASK.md`。该卡新增 `glm_real` 和 `all_real`，但没有读取真实 GLM Key
或发送真实 GLM 请求。ZCode 仅作为最终人工对照，不作为私有数据源。

## 10. 三家 Parser 与合规总表（2026-07-23 更新）

| Provider | 离线 Parser | 离线测试 | 真实查询合规性 | 默认状态 |
|---|---|---|---|---|
| **Codex** | `codex_app_server.py`（官方本地 Schema） | 协议/解析/路由测试 15 项 | ✅ 官方本地只读方法；项目不接触凭据 | 已实现，环境开关默认关闭 |
| **Kimi** | `kimi_parser.py` + `kimi_adapter.py`（L2 契约） | 原解析/流水线测试 + 19 个真实 Adapter/路由测试 | ✅ 官方允许第三方平台；**不需要** UA 伪装 | 已实现，环境开关默认关闭；脱敏真实读取已通过 |
| **GLM** | `glm_parser.py` + `glm_adapter.py`（L2 插件契约） | 原解析/流水线测试 + 18 个 Adapter 测试 + 6 个真实/综合路由测试 | ⚠️ 技术契约已确认，第三方监控许可未确认；**默认禁用真实调用** | Adapter 与 `all_real` 已实现并离线验证；无真实请求 |

字段名误导性提醒（解析器已处理）：

- **GLM**：`usage` = 上限，`currentValue` = 已用（与字段名直觉相反）。
- **Kimi**：`used` = 已用，`limit` = 上限；缺失 `used` 时走 `limit - remaining`。
- **GLM `nextResetTime`**：用 `>1e12` 启发式区分毫秒/秒，非数字按 ISO。
- 两家都允许 `percentage` 超 100（不钳制）。

三家的自动化测试均为**纯离线**：无真实网络、无真实凭据、无 UA 伪装。Codex/Kimi 的单独真实
检查曾在用户显式开启后完成脱敏结构验证；GLM 没有做真实检查。`all_real` 只调用各自开关已启用的
Provider，单家失败不会阻断其他结果。2026-07-23 全后端 `pytest` **419 passed**。

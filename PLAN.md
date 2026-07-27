# AI 套餐额度查询器 — 项目方案概览

> 项目目标：做一个手机端 + 桌面端 + Web 端的 App，统一查询 Codex / GLM / Kimi 三家 Coding Plan 的
> 已用额度、剩余额度、重置时间、到期日期。
>
> 2026-07-23 实施更新：Codex 已改用官方本地 `codex app-server`，项目不读取 `auth.json`；Kimi
> 默认关闭 Adapter 已完成脱敏真实结构验证；GLM 默认关闭 Adapter 与 `all_real` 已完成离线验证及
> 用户授权的脱敏本机结构检查；当前三窗口契约漂移已修复，三项 `percentage` 均按已用比例解析。
> 一键 Windows 启动器已通过自动与真实
> 启动健康验证。接口证据与合规结论以 `docs/API_RESEARCH.md` 第零节为准。
>
> 项目同时是**零基础系统性学习 AI coding 与 agent** 的载体：每阶段学一个知识点、产出一个可见成果、
> 用 AI 工具辅助。

> **执行入口：** 系统化的 Vibe Coding 学习清单、工程步骤、阶段验收和 Prompt 模板，统一见
> [`docs/VIBE_CODING_LEARNING_PLAN.md`](docs/VIBE_CODING_LEARNING_PLAN.md)。学习证据记录在
> [`docs/LEARNING_LOG.md`](docs/LEARNING_LOG.md)。本文件只保留项目概览；API 细节以
> [`docs/API_RESEARCH.md`](docs/API_RESEARCH.md) 为准。

> **当前学习决策（2026-07-22）：** 学习软件开发流程与 Vibe Coding 能力优先于尽快接入真实数据。
> 先在 Windows 上用假数据完成“需求 → 实现 → 测试 → 审查 → 复盘”闭环，再引入本地假后端，
> 最后才接真实额度 API 和扩展其他平台。
> 学习以全栈交付流程为骨架：前端、契约、后端/API、测试、Git 和发布证据贯通推进；Dart、Flutter、
> Python 等技术细节按当前切片即时学习，不把路线变成某一语言或框架的专项课程。

---

## 一、核心可行性结论（调研得出）

| 服务 | 查询难度 | 鉴权方式 | 全平台支持 | 数据来源 |
|------|---------|---------|----------|---------|
| **Codex** | ⭐⭐ | 登录由本机官方 Codex 进程管理 | 本机 FastAPI 调用官方进程；公开部署需另做安全设计 | `codex app-server` / `account/rateLimits/read` |
| **Kimi** | ⭐ | `sk-kimi-xxx` Coding Key，仅在本地后端环境变量 | 后端可请求；公开客户端不得内置 Key | `api.kimi.com/coding/v1/usages` |
| **GLM** | ⭐⭐⭐ | 官方插件把 Coding Plan auth 值原样放入 `Authorization` | 代码已实现但第三方监控许可待确认 | `open.bigmodel.cn/api/monitor/usage/quota/limit` |

**生产架构结论**：要支持“手机 + 桌面 + Web”，最终采用「**前端 App + 后端服务**」两层架构。
主要原因是公开前端无法安全保管 Kimi/GLM Key；当前 Codex 路径还依赖用户本机已登录的官方进程，
不能直接照搬到公共多用户后端。

**学习实现顺序**：`Flutter + Mock` → `Flutter + 本地 FastAPI 假接口` → `真实 Codex` →
`真实 Kimi/GLM`。MCP 中已经配置的 Kimi/GLM coding worker 是开发辅助模型，不是 Quota Watch
已经接好的额度数据源；两者必须分开理解。

### 关键端点参考（供阶段 6-7 真实数据接入时重新验证）

**Codex（已实施）**
- 本机入口：官方 `codex app-server` JSONL 协议。
- 只读方法：`account/rateLimits/read`。
- 登录与凭据：由官方 Codex 进程管理；Quota Watch 不读取、解析或刷新 `auth.json`。
- `wham/usage` 等网页内部端点只保留为历史调研，禁止作为当前实现。

**Kimi（按官方 `MoonshotAI/kimi-code` 源码实施）**
- 鉴权：`sk-kimi-xxx` API Key，直接放 `Authorization: Bearer`
- 已调研端点：`GET https://api.kimi.com/coding/v1/usages`
- 本地学习实验可直连；公开 Web/移动端必须通过后端，避免 Key 进入构建产物

**GLM（Coding Plan 监控端点）**
- 端点：`https://open.bigmodel.cn/api/monitor/usage/quota/limit`
- 鉴权契约：官方插件把 `ANTHROPIC_AUTH_TOKEN` 原样放入 `Authorization`；不使用 Cookie 抓取方案
- 官方插件参考：`zai-org/zai-coding-plugins/plugins/glm-plan-usage`
- 当前边界：Adapter 默认关闭、测试纯离线；真实第三方调用许可待确认
- ZCode：可人工显示套餐统计，但当前官方文档未提供额度导出、CLI 或本地只读 API

---

## 二、技术栈（已根据你的基础和目标选定）

```
┌─────────────────────────────────────────────┐
│  前端 App（Flutter, 一套代码三端通用）          │
│  - Windows 学习版 → Web/Android → iOS 可选     │
│  - Dart 语言、HTTP、状态管理(Riverpod)         │
└───────────────┬─────────────────────────────┘
                │ REST API (JSON)
┌───────────────▼─────────────────────────────┐
│  后端服务（Python FastAPI，新手友好）          │
│  - 三家平台适配器（Codex/Kimi/GLM）           │
│  - 本机进程环境变量 + 官方 Codex 登录进程       │
│  - 缓存、限流、错误处理                        │
└───────────────┬─────────────────────────────┘
                │
         ┌──────┴──────┬──────────┐
         ▼             ▼          ▼
   Codex app-server  Kimi 用量端点  GLM 用量端点
   (官方本机进程)   (本机 Key)      (默认关闭)

   可选旁路：产品 MCP Server（最终阶段，让 Agent 读取 Quota Watch 的额度结果）
```

**为什么选这套**：
- **Flutter**：你选了它，一套 Dart 代码覆盖 Web/iOS/Android/桌面，新手最划算
- **Python FastAPI**：语法接近自然语言、调试简单、AI 生态好，比 Node.js 更适合零基础
- **Riverpod**：Flutter 当前推荐的状态管理，比 Provider 现代

### 开发协作分工

| 参与者 | 主要职责 | 权限边界 |
|---|---|---|
| **你** | 产品取舍、亲自运行关键验收、三句话反向讲解、最终接受或拒绝改动 | 不需要脱离 AI 编程，但不能跳过理解与验收 |
| **Codex** | 主控、教学、拆任务、读写代码、运行测试、整合与最终审查 | 对工作区修改负责；不能用“worker 说可以”代替测试 |
| **GLM worker** | 后端、通用编程、边界情况和测试方案的只读审查 | 不直接写文件或执行命令；返回建议或补丁供 Codex 审查 |
| **Kimi worker** | Flutter UI、交互、响应式与视觉可用性的只读审查 | 不直接写文件或执行命令；不把视觉建议当成已实现功能 |

同一任务只在确有收益时委托一个相关 worker。Codex 保持主线程中的需求、决定和验收上下文，
避免多个模型同时修改同一处代码。

---

## 三、分阶段学习路线图（概览）

> 下列内容是产品阶段概览。实际执行已细化为 0～10 阶段，并增加任务卡、亲手练习、质量门与
> Definition of Done；以 [`docs/VIBE_CODING_LEARNING_PLAN.md`](docs/VIBE_CODING_LEARNING_PLAN.md) 为准。

| 阶段 | 学习核心 | 工程产出 |
|---|---|---|
| 0 | 工具链、终端、Git、错误诊断 | 补齐脚手架并让现有 Flutter 草案真正运行 |
| 1 | Dart、Widget、异步与数据流 | 验证静态 UI，补模型和导航测试 |
| 2 | 小步修改、Diff、测试与回退 | Repository 抽象与可持续开发基线 |
| 3 | JSON、状态与统一契约 | 用本地夹具让假数据覆盖正常、加载、空和失败状态 |
| 4 | Python、HTTP 与 FastAPI | 本地假后端返回稳定 JSON，不接任何真实额度 API |
| 5 | Riverpod、异步状态、前后端联调 | Flutter 稳定消费假后端，完成无秘密端到端闭环 |
| 6 | OAuth、Token 生命周期与安全 | 优先接入最重要的 Codex 真实额度 |
| 7 | 契约漂移、容错与降级 | 再接 Kimi、GLM，并完成三家聚合 |
| 8 | 可观测性、UX 与测试矩阵 | 可日常使用的 Release Candidate |
| 9 | 开源、构建、部署、版本和回滚 | Windows 开源 Beta；Web/Android 随后，iOS 可选 |
| 10 | 产品 MCP 与 Agent 工具设计 | 可选：独立 MCP 进程只读查询额度 |

---

## 四、第一个里程碑（最关键）

**详细计划阶段 5 结束时，你应该有**：Windows 上可运行的 Flutter App 通过本地 FastAPI
假接口展示三家模拟额度，具备加载、空、错误、刷新和基础测试。这个里程碑不需要任何 Key，
重点证明你已经走完一次可审查、可测试、可解释的前后端开发闭环。

真实额度与公开部署属于第二条路线。在模拟端到端里程碑通过之前，不用接真实 API 换取表面进度。

---

## 五、AI 工具学习贯穿全程（核心目标之一）

不是单独开"AI 工具课"，而是**每个阶段都在 Codex 中练**：
- **Prompt 习惯**：先描述目标→给上下文→明确产出格式，再让 AI 写代码
- **Codex 主闭环**：调查/计划 → 小步编辑 → 测试 → diff 审查 → 三句话讲解
- **模型分工**：后端问题按需请 GLM 只读复核，UI 问题按需请 Kimi 只读复核，Codex 负责落地与验证
- **Skill 复用**：稳定且重复的流程再沉淀为 skill；不要为了“用了 Agent”而增加复杂度
- **调试能力**：AI 可以先查，但你必须阅读完整错误、确认原因并亲自运行至少一个关键验证

---

## 六、风险与诚实告知

1. **GLM 权限与契约风险**：官方插件确认了 wire contract，但未明确授权任意第三方监控工具；因此真实
   开关仍默认关闭。一次用户授权的本机脱敏结构检查不扩展成公开/商业许可；GLM 失败时只降级该卡。
2. **Codex 登录或协议失效**：由官方 app-server 管理登录；失败时引导用户检查本机 Codex，不由项目
   读取 token 或自行刷新。
3. **iOS 打包门槛**：需要 Mac，建议放最后或用云服务。
4. **三家服务条款**：第三方接口和自动化访问可能受服务条款限制。优先自用学习；任何公开或商业化发布前，
   都要重新核对当时的条款、隐私要求和接口许可。

---

## 七、实施进度

| 阶段 | 状态 | 备注 |
|------|------|------|
| 0. 工具链与运行闭环 | 已验证 + 能讲解 | Flutter 3.44.2 已安装；Web 工程、自动化验证、Edge 人工验收、截图及启动/功能边界讲解均已完成 |
| 1. Dart + 静态 UI | 已验证，待全栈迁移 | 已区分 95%～不足 100%“紧张”和 100%“耗尽”；用户确认 8 个测试通过 |
| 2. Vibe Coding 工程基线 | 代码已验证，概念按需复盘 | Repository 接口和注入测试已经建立；后续继续用小步 diff 和测试巩固 |
| 3. 假数据契约与状态 | 已验证 | 正常、加载、空、未配置、部分失败、全部失败场景均有离线测试 |
| 4. FastAPI 假后端 | 已验证 | `/health` 与六种额度场景已实现；8 个 pytest 通过，不含凭据和外网请求 |
| 5. 假数据端到端 | 已验证 | Riverpod + HTTP Repository + 设置页完成；29 个 Flutter 测试、Web 构建及真实浏览器 E2E 通过 |
| 6. Codex 真实额度 | 代码与自动验证完成，待 UI 验收 | 官方 app-server 只读纵切片；脱敏真实结构读取完成 |
| 7. Kimi/GLM + 三家聚合 | 代码与自动验证完成，待 UI 验收 | Kimi/GLM 脱敏本机结构检查；默认关闭 Adapter 与 `all_real` 失败隔离 |
| 8. 产品化 | 一键启动与 GLM 漂移修复切片已验证，待用户数值对照 | Windows 启动器、三窗口双契约解析、端口保护；后端 431、Flutter 45、Web/Playwright 通过 |
| 9. 开源发布 | 待开始 | Windows 优先；Web/Android 随后，iOS 可选 |
| 10. 产品 MCP Server | 可选 | 与开发阶段使用的 Kimi/GLM worker 无关 |

---

## 八、参考资料

- [OpenAI Codex 套餐说明](https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan)
- [Codex app-server 官方文档](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md)
- [Kimi Code 官方源码](https://github.com/MoonshotAI/kimi-code)
- [多平台 Coding Plan 监控（MiniMax + GLM）](https://github.com/JinHanAI/coding-plan-monitor)
- [GLM Coding Plan 用量查询插件](https://docs.bigmodel.cn/cn/coding-plan/extension/usage-query-plugin)
- [GLM Coding Plan FAQ（含工具限制）](https://docs.bigmodel.cn/cn/coding-plan/faq)
- [ZCode 使用统计](https://zcode.z.ai/cn/docs/usage-stats)

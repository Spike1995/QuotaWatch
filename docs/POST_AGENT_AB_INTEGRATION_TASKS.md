# Quota Watch：Agent A / B 完成后的集成、验证与下一阶段任务

> 工作区：`D:\APPDEsign`  
> 用途：把本文件整体交给后续集成 Agent。  
> 执行时机：仅在 Agent A、Agent B 都停止写入并提交完整完成报告后执行。  
> 本文件不授权接入任何真实 Codex、Kimi 或 GLM Provider。

## 给后续 Agent 的直接执行提示词

你是 Quota Watch 的主集成 Agent。先完整阅读以下文件，再执行任何命令：

1. 根目录 `AGENTS.md`
2. `docs/AGENT_A_FONT_E2E_INSTRUCTIONS.md`
3. `docs/AGENT_B_FRONTEND_OPTIMIZATION_INSTRUCTIONS.md`
4. `docs/AGENT_A_COMPLETION_REPORT.md`
5. `docs/AGENT_B_COMPLETION_REPORT.md`
6. `docs/AGENT_COMPLETION_REPORT_TEMPLATE.md`
7. `docs/HANDOFF_PRE_API_COMPLETION.md`
8. `docs/VIBE_CODING_LEARNING_PLAN.md`
9. `docs/LEARNING_LOG.md`

先检查当前 worktree、分支、HEAD、`git status --short`、运行中的 Flutter/Dart/Python/Edge
进程和端口占用。不得假设历史报告仍等于当前状态。

不得执行 `git reset`、`git stash`、`git checkout --`，不得覆盖、删除或丢弃 dirty changes；
未经用户明确要求，不得暂存、提交、合并、变基或推送。不要把进入任务前已有的修改认领为自己的
工作。

## 0. 开始门：条件不满足时停止集成

只有以下条件全部满足，才能开始最终集成验证：

- `docs/AGENT_A_COMPLETION_REPORT.md` 和 `docs/AGENT_B_COMPLETION_REPORT.md` 均存在。
- 两份报告的 `status` 都是 `complete`，且 `safe_to_integrate: true`。
- 报告中的验证表填写真实命令、退出码和结果，不得残留 `待填`、`unknown`、`应该通过`等占位。
- Agent B 的最终 `flutter test`、`flutter analyze` 和 `git diff --check` 有实际证据。
- Agent A 明确记录字体子集对应的源码 HEAD、字体文件大小、FontManifest、两次 E2E 和人工截图检查。
- Agent A、Agent B 已停止写文件；不要在测试过程中接受新的页面、字体、测试或 E2E 修改。
- 7357、8000 没有被其他任务占用。发现占用时先确定归属，不得直接终止不明进程。

截至本文件创建时的已知风险仅作为提醒，执行时必须重新核对：

- 仓库曾只有 `D:\APPDEsign` 一个 worktree，A/B 并未真正隔离。
- Agent B 曾生成完成报告，但 `flutter test` 一栏仍为 `待填`。
- Agent A 完成报告曾缺失。

如果上述问题仍存在，停止最终验证并准确报告缺失证据；不要用一次新的测试替另一位 Agent 修改其
报告，也不要把不完整报告改成 `complete`。

## 1. 审查 A/B 实际修改与所有权

1. 对照两份指令和报告，列出 Agent A、Agent B 各自实际修改的文件。
2. 运行并审查：

   ```powershell
   git status --short
   git diff --stat
   git diff --name-status
   git diff --check
   ```

3. 对未跟踪文件单独核对归属，因为普通 `git diff` 不会显示其内容。
4. Agent B 的 presentation、响应式测试和可访问性修改应先成为最终页面事实。
5. Agent A 的字体子集必须基于 Agent B 最终页面、测试和 Fixture 中的字符重新生成。
6. 如果 A/B 已经在同一 dirty worktree 中完成，不要虚构分支合并或执行 cherry-pick；按文件和代码块
   审查当前结果即可。
7. 发现双方越界、重叠或无法判断归属时，保留现状并报告；不得擅自选择一侧覆盖另一侧。

## 2. 固定集成顺序

必须按以下顺序完成：

1. 冻结 Agent B 的最终 presentation 与 Widget 测试代码。
2. 记录 Agent B 新增或修改的全部可见中文和语义中文。
3. 使用 Agent A 最终报告中记录的准确命令，在最终源码上重新运行
   `scripts/build_font_subset.ps1`。
4. 核对输出固定为：

   ```text
   quota_watch/assets/fonts/NotoSansSC-QuotaWatchSubset.ttf
   ```

5. 确认完整约 17 MB 的上游字体仍只位于临时目录，没有进入仓库。
6. 重新运行全部 Flutter、后端、Web build 和 E2E 验证。
7. 实际查看最终截图，最后才更新学习日志和阶段状态。

如果 Agent A 报告说明其字体子集不是基于 Agent B 的最终文字生成，即使 Agent A 自己的 E2E 曾
通过，也必须重新生成子集、重新 build，并重新跑两次 E2E。

## 3. 最终自动验证

先使用 Agent A 报告中的字体生成命令。不得猜测脚本参数；若报告未写清楚，先阅读脚本的参数定义。

随后执行：

```powershell
cd D:\APPDEsign\quota_watch
E:\Move\flutter\bin\dart.bat format lib\presentation test
E:\Move\flutter\bin\flutter.bat pub get
E:\Move\flutter\bin\flutter.bat analyze
E:\Move\flutter\bin\flutter.bat test
E:\Move\flutter\bin\flutter.bat build web --dart-define=QUOTA_DATA_MODE=backend --dart-define=QUOTA_SCENARIO=partial --dart-define=QUOTA_BACKEND_URL=http://127.0.0.1:8000

cd D:\APPDEsign
backend\.venv\Scripts\python.exe -m pytest -c backend\pytest.ini backend\tests
python scripts\run_e2e.py
python scripts\run_e2e.py
git diff --check
```

要求：

- 记录每条命令的实际退出码和通过数量。
- 第一次失败后先保存脱敏错误并定位原因，不要机械重复运行掩盖偶发问题。
- E2E 两次都必须针对同一个最终 Web build。
- E2E 结束后确认 7357、8000 没有遗留 `LISTENING` 进程。
- 确认 `backend/.venv/` 仍被 Git 忽略。
- 疑似凭据扫描只能输出文件名，不得打印匹配行或可能的秘密内容。

## 4. 最终人工功能检查

自动测试通过后，至少检查以下可观察行为：

### 响应式与交互

- 390px：首页单列；详情页指标和摘要标记不溢出；设置页完整可操作。
- 768px：首页两列，第三张卡片换行到左侧。
- 1440px：首页三列，正文不超过约 1120px。
- 1920px：正文不再随窗口无限拉宽。
- 下拉刷新仍可用。
- 有额度窗口的卡片可以进入详情；错误、未配置、无窗口卡片不可进入不存在的详情。
- Fixture 模式下后端 URL 被禁用，并显示原因。
- Tab 焦点顺序合理，Enter/Space 可操作 Material 按钮。
- 卡片语义包含服务商、套餐和状态；不可点击卡片不能谎报为按钮。

### 字体与 E2E

- 查看 `docs/evidence/2026-07-22-stage5-backend-partial.png`，不能只看 aria-label。
- 截图中必须实际可读：`本地 FastAPI · 部分失败`、`查询失败`、
  `模拟故障：GLM 服务暂时不可用`。
- 中文不得显示为方框。
- `/assets/FontManifest.json` 中存在 `NotoSansSCSubset`，并引用
  `NotoSansSC-QuotaWatchSubset.ttf`。
- E2E 确实收到 `/api/v1/quotas?scenario=partial` 的响应，不得只以 HTML 到达判断 Flutter 已启动。

## 5. 范围、安全和回归审查

最终 diff 必须满足：

- 阶段 3～5 仍只使用 Mock、Fixture 和本地 FastAPI 假接口。
- 没有真实 Codex、Kimi、GLM Provider 请求或适配器。
- 没有 API Key、Token、Cookie、`.env`、`auth.json` 内容或真实 Provider 响应。
- Flutter 公共客户端没有任何 Provider 凭据。
- 完整源字体未进入仓库；OFL、上游来源和子集再生成方法有记录。
- Agent B 没有改变数据契约、状态规则和路由语义。
- Agent A 没有覆盖 Agent B 的页面或响应式实现。
- 单家错误、空数据、部分失败、全部失败、损坏 JSON、断网和超时仍有测试证据。

## 6. 文档和统一交付报告

全部验证完成后：

1. 只根据真实证据更新 `docs/LEARNING_LOG.md`。
2. 必要时同步 `docs/VIBE_CODING_LEARNING_PLAN.md`、根 `README.md` 和 `PLAN.md`；不得重写历史记录。
3. 新增：

   ```text
   docs/AGENT_AB_INTEGRATION_REPORT.md
   ```

4. 报告结构沿用 `docs/AGENT_COMPLETION_REPORT_TEMPLATE.md`，并额外记录：
   - A/B 报告是否完整、是否存在占位或矛盾。
   - 最终源码 HEAD 和 dirty worktree 状态。
   - 字体子集是否在 Agent B 最终文字之后重新生成。
   - Flutter、FastAPI、Web build、两次 E2E 的实际结果。
   - 最终截图实际看到的关键中文。
   - 端口、凭据、完整字体和真实 Provider API 检查结果。
5. 只有所有 Definition of Done 都有证据时，才能写“阶段 3～5 的真实 API 接入前版本已完成”。

## 7. A/B 完成后的下一张任务卡：阶段 6 / 卡 1

### 任务名称

真实额度接入前的官方支持、安全与本地架构复核。

### 已确认的产品方向

用户选择“个人电脑上的本地自动查询工具”，目标体验为：

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

“各 Coding 软件关闭前记录一次”只能作为缓存补充，不能作为主数据源，原因包括异常退出、多设备
共享额度和额度窗口在软件关闭时仍会重置。

### 本卡允许范围

- 重新核对三家当前官方用量查看入口、支持工具、使用条款和可编程接口状态。
- 建立三家支持矩阵：`官方自动查询 / 仅官方页面或 CLI 查看 / 实验性且默认禁用`。
- 设计本地 FastAPI Provider Adapter 接口、缓存结构、`fetchedAt`、过期判断和单家失败隔离。
- 使用 Fake Adapter、Fixture 和脱敏示例定义契约及测试；不得发起真实 Provider 请求。
- 更新 `docs/API_RESEARCH.md`，明确区分官方文档、官方开源实现、内部端点和社区逆向。
- 写出下一张“首家 Provider 本地实验”任务卡和验收标准。

### 本卡禁止范围

- 不读取、复制或解析用户现有 `auth.json`、Token、Cookie、API Key。
- 不要求用户在对话中粘贴任何凭据。
- 不在 Flutter、Git、日志、截图或 Fixture 中放置秘密。
- 不使用伪装官方客户端的 User-Agent 绕过限制。
- 不把“请求成功”当作“官方允许公开产品接入”。
- 不实现多用户云端凭据托管。
- 未获得用户对某一家真实本地实验的再次明确授权前，不发起真实请求。

### 必须重新验证的外部事实

执行阶段 6 时只使用当时的官方资料和官方开源实现，不能直接相信旧调研。至少重新核对：

- Codex：官方 Usage 面板、CLI `/usage`，以及个人账户是否存在公开稳定的额度 API。
- Kimi Code：控制台、CLI `/usage`、支持工具范围；旧文档中的 `KimiCLI/1.6` User-Agent
  伪装方案不得作为实现依据。
- GLM Coding Plan：官方用量统计、官方 `glm-plan-usage` 插件及“仅限指定工具”规则。

参考入口仅用于重新发现资料，实施时仍要检查更新时间：

- OpenAI：`https://help.openai.com/en/articles/20001106`
- Kimi：`https://www.kimi.com/zh-cn/help/kimi-code/benefits`
- GLM：`https://docs.bigmodel.cn/cn/coding-plan/extension/usage-query-plugin`
- GLM 使用须知：`https://docs.bigmodel.cn/cn/coding-plan/usage-notes`

### 凭据规则

未来某张真实实验任务卡确实需要凭据时，必须告诉用户：

- 凭据应由用户本人填写到哪个本地配置位置。
- 使用的准确环境变量名。
- 如何确认该文件或变量不会被 Git、日志和截图收集。

只能使用占位符，永远不得要求用户把实际值发到对话中。凭据只能由本地后端或系统安全存储读取，
不得进入 Flutter 公共客户端。

### 阶段 6 / 卡 1 完成标准

- 三家官方支持矩阵有带日期的官方证据。
- 数据契约和缓存设计覆盖成功、401/403、429、超时、契约变化和单家失败。
- App 启动刷新、手动刷新、最后成功快照和过期提示有明确验收标准。
- 未发起真实 Provider 请求，未接触任何凭据。
- 下一张任务卡只选择一家 Provider 做最小本地实验，并等待用户明确授权。

## 8. 最终回复要求

最终回复只报告：

- A/B 集成状态。
- 修改与保留的文件范围。
- 自动验证的真实通过/失败数量。
- 人工截图和响应式检查结果。
- 冲突、秘密、端口和字体检查结论。
- `docs/AGENT_AB_INTEGRATION_REPORT.md` 的绝对路径。
- 是否达到阶段 6 入口；明确说明真实 Provider API 是否仍为零。

不要写“应该可以”。

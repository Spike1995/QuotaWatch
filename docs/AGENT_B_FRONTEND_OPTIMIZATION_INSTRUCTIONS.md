# Agent B 指令：响应式前端与可访问性优化

> 目标工作区：`D:\APPDEsign`  
> 任务性质：修改 Flutter presentation 层和对应 Widget 测试。  
> 并行条件：必须与 Agent A 使用独立 worktree；不得同时写同一个工作目录。

## 直接执行提示词

你是 Quota Watch 的 Agent B。请先完整阅读仓库根目录 `AGENTS.md`，再检查当前 presentation
代码和测试。不要 reset、覆盖或丢弃已有修改，不要暂存、提交或推送，除非用户另行明确要求。

本任务假设你处于独立 worktree。如果你和 Agent A 共用 `D:\APPDEsign` 的同一 working tree，
请立即停止写入并要求用户提供隔离 worktree。原因是 Agent A 正在生成字体和 Web 构建，可能读取到
你尚未完成的页面代码。

## 目标

在不改变数据契约、状态管理和产品功能的前提下，让首页、详情页和设置页在 390px、768px、
1440px 三种宽度上更易读、不会无限拉宽，并改善状态语义和键盘可用性。

保持实现简单。不要重做品牌视觉，不要引入新的 UI 框架或依赖。

## 当前代码事实

- 首页：`quota_watch/lib/presentation/pages/home_page.dart`
  - 使用 `ListView` 顺序显示 `SummaryHeader` 和三张 `QuotaCard`。
  - 当前桌面端没有最大内容宽度，1440px 卡片会横向铺满。
- 详情页：`quota_watch/lib/presentation/pages/detail_page.dart`
  - 当前 `ListView` 同样铺满可用宽度。
  - `_WindowBlock` 使用三个 `_Metric` 的 `Row`，窄屏和长文字需要防止溢出。
- 设置页：`quota_watch/lib/presentation/pages/settings_page.dart`
  - 表单在桌面端铺满宽度。
  - 已有 Fixture/FastAPI、场景和 URL 校验，不得改变这些业务规则。
- 卡片：`quota_watch/lib/presentation/widgets/quota_card.dart`
  - 已有文字状态标签，不能退化成只用颜色表达状态。
- 顶部摘要：`quota_watch/lib/presentation/widgets/summary_header.dart`
  - 已显示三家标记和当前模式/场景。
- 自动测试集中在 `quota_watch/test/widget_test.dart`，也允许新增独立的响应式测试文件。

## 允许修改的文件

- `quota_watch/lib/presentation/pages/home_page.dart`
- `quota_watch/lib/presentation/pages/detail_page.dart`
- `quota_watch/lib/presentation/pages/settings_page.dart`
- `quota_watch/lib/presentation/widgets/quota_card.dart`
- `quota_watch/lib/presentation/widgets/quota_progress_bar.dart`
- `quota_watch/lib/presentation/widgets/summary_header.dart`
- 必要时在 `quota_watch/lib/presentation/widgets/` 新增一个简单响应式布局组件
- `quota_watch/test/widget_test.dart`
- 推荐新增 `quota_watch/test/responsive_layout_test.dart`
- 可新增 `docs/FRONTEND_OPTIMIZATION_REPORT.md` 记录验收结果
- 新增并维护 `docs/AGENT_B_COMPLETION_REPORT.md`

## 禁止修改的范围

- `quota_watch/pubspec.yaml` 和 `pubspec.lock`
- `quota_watch/lib/app/theme/app_theme.dart`
- `quota_watch/assets/fonts/**`
- `scripts/build_font_subset.ps1`
- `scripts/e2e_web_check.py`、`scripts/run_e2e.py`
- `docs/evidence/**`
- `quota_watch/lib/data/**`、`quota_watch/lib/app/state/**` 和路由契约
- `backend/**`
- 任何真实 API、凭据或第三方服务代码

## 必须实现的内容

### 1. 页面最大宽度

为三页添加居中的内容约束，但不要修改全局 Theme：

- 首页最大内容宽度：约 `1120px`。
- 详情页最大内容宽度：约 `900～960px`。
- 设置页最大内容宽度：约 `680～720px`。
- 小于最大宽度时仍使用当前页面内边距。
- 1440px 继续放大时只增加两侧留白，正文不再无限变宽。

可以新增一个 presentation 层的轻量 `ResponsiveContent`/`CenteredContent` 组件复用这些约束，
但不要为了抽象而引入复杂布局框架。

### 2. 首页响应式卡片布局

根据可用内容宽度实现：

- 小于约 `700px`：单列。
- `700px～1099px`：两列；第三张卡片换到下一行。
- 大于等于约 `1100px`：三列。
- 卡片水平、垂直间距保持一致，建议 `12～16px`。
- `SummaryHeader` 始终占满受约束的内容宽度，不进入卡片网格。
- 下拉刷新仍然可用。
- 点击有额度窗口的卡片仍进入详情页；错误、未配置或无窗口卡片仍不可进入不存在的详情。

建议使用 `LayoutBuilder + Wrap + SizedBox(width: ...)`，或同等简单且可测试的实现。避免给三张卡片
硬编码不同宽度。

### 3. 窄屏防溢出

- 详情页三个 `_Metric` 在 390px 和较长数值下不得产生 RenderFlex overflow；可以使用
  `Expanded`、`Flexible` 或 `Wrap`。
- `SummaryHeader` 的三家标记在窄屏不得溢出；可以改为 `Wrap`，宽屏仍保持一行。
- 卡片标题、套餐名、状态标签同时出现时不得互相挤出屏幕。必要时对套餐名使用合理的
  `maxLines`/`overflow`，但不能隐藏状态文字。
- 设置页 URL 输入和按钮在 390px 下保持完整可操作。

### 4. 状态和可访问性

保留现有状态文字：`充足`、`告警`、`紧张`、`耗尽`、`查询失败`、`部分可用`、`加载中`、
`未配置`、`无数据`。不得改成只用颜色或图标。

为额度卡片和状态标签补充必要的语义：

- 卡片语义至少包含服务商名称、套餐名和当前状态。
- 可点击卡片对辅助技术表现为可操作项；不可点击卡片不能谎报为按钮。
- 设置按钮继续保留 tooltip。
- 不要重复读出同一段文字；需要时使用 `excludeSemantics` 组织一个清晰标签。
- 保持 Material 控件的键盘焦点和 Enter/Space 操作，不要用裸 `GestureDetector` 替换 `InkWell`。

### 5. 设置页易用性

- 桌面端表单居中限宽。
- Fixture 模式下后端 URL 保持禁用，并让用户能看出它为什么不可编辑。
- 不改变现有 URL 校验、场景过滤、应用后刷新和返回行为。
- 保存按钮、下拉框和 URL 字段保持清晰的焦点顺序。

## 测试要求

新增或扩展 Widget 测试，至少覆盖：

1. `390x844`：首页单列、无布局异常。
2. `768x900`：首页两列。
3. `1440x1000`：首页三列且整体内容宽度不超过约定最大值。
4. `1920x1080`：正文宽度不再随窗口无限增长。
5. 390px 详情页三个指标无 overflow。
6. 390px 摘要三家标记无 overflow。
7. 卡片语义区分可点击和不可点击状态。
8. 现有“点击 Codex 进入详情”“设置页导航”“空/错误/部分失败”等测试继续通过。

测试应断言可观察行为和几何关系，不要依赖脆弱的整页 golden 截图。每个测试结束后恢复
`tester.binding.setSurfaceSize(null)`，避免污染其他用例。

## 验证命令

```powershell
cd D:\APPDEsign\quota_watch
E:\Move\flutter\bin\dart.bat format lib\presentation test
E:\Move\flutter\bin\flutter.bat analyze
E:\Move\flutter\bin\flutter.bat test
git diff --check
```

如果你的独立 worktree 不在 `D:\APPDEsign`，将上述路径替换为当前 worktree 的绝对路径。

不要覆盖 Agent A 的 Web build 或 E2E 截图。本分支只需完成 Widget 层验证；合并后的最终 Web build
和 Edge E2E 由集成者执行。

## 新中文文字规则

尽量复用已有文案。如果确实增加可见中文文字，在最终报告中逐条列出。Agent A 在合并后必须重新
生成字体子集，否则新文字可能显示为方框。

## 完成标准

- 390px 单列、768px 两列、1440px 三列行为有自动测试证明。
- 1440px/1920px 页面正文有最大宽度，不再横向铺满。
- 首页、详情和设置页在窄屏无 overflow。
- 状态仍由文字加颜色表达，卡片语义可辨识。
- 原有业务行为和所有现有测试保持通过。
- 没有修改字体、主题、E2E、后端、数据契约或真实 API 范围。

最终报告必须包含：修改文件、各断点行为、测试结果、新增中文文字以及需要集成者复验的项目。

## 合并顺序

Agent B 完成后不要自行合并。推荐集成顺序：

1. 集成 Agent B 的 presentation 和测试修改。
2. 在合并结果上让 Agent A 重新生成字体子集。
3. 由主 Agent 重新跑 Flutter 全部测试、Web build、两次 E2E 和截图检查。

## 统一完成报告

完成或停止工作前，必须阅读 `docs/AGENT_COMPLETION_REPORT_TEMPLATE.md`，并严格按模板新增：

```text
docs/AGENT_B_COMPLETION_REPORT.md
```

Agent B 的报告必须额外明确：

- 390px、768px、1440px、1920px 各自最终布局行为。
- 新增或修改的所有用户可见中文文字，逐条原样列出；没有则写 `none`。
- 是否修改了 Agent A 禁止区域；正常结果必须为 `否`。
- 哪些测试只证明 Widget 布局，哪些仍需合并后由 Agent A 的 Web/E2E 证明。
- 建议集成者检查的具体页面、状态和键盘操作。

最终回复只报告：状态、修改内容、实际验证结果、报告路径、冲突判断和集成者下一步。
不要写“应该可以”。

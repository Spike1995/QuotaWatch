# Quota Watch Agent 统一完成报告模板

> 所有并行 Agent 必须使用本模板。目的不是写开发日记，而是让集成者快速判断：做了什么、证据
> 是否充分、是否越界、与其他 Agent 是否冲突，以及下一步应执行什么。

## 使用规则

1. 开始修改前记录 worktree、分支、HEAD 和初始 `git status --short`。
2. 只报告自己实际修改或生成的文件，不把进入 worktree 前已有的 dirty changes 认领为自己的工作。
3. 状态只能填写 `complete`、`partial` 或 `blocked`：
   - `complete`：本任务所有完成标准都有证据。
   - `partial`：完成了一部分，但仍有明确待办。
   - `blocked`：存在无法在本任务权限内解决的阻塞。
4. 测试必须写实际运行的命令和真实结果；不得写“应该通过”。
5. 不复制超长日志。失败时保留经过脱敏的核心错误、失败测试名和退出码。
6. 不在报告中粘贴任何 API Key、Token、Cookie、`.env`、`auth.json` 内容或真实服务响应。
7. 报告文件只由对应 Agent 修改；不要修改另一位 Agent 的报告。

## 固定快速摘要

请保持字段名不变，未知值写 `unknown`，没有内容写 `none`。

```yaml
report_version: 1
agent_id: A_or_B
task_name: short_task_name
status: complete_or_partial_or_blocked
worktree_path: absolute_path
branch: branch_name_or_detached
base_commit: commit_before_work
head_commit: current_head_commit
started_with_dirty_tree: true_or_false
real_provider_api_touched: false
credentials_or_secrets_touched: false
files_outside_allowed_scope: none_or_list
shared_files_touched: none_or_list
new_visible_chinese_text: none_or_list
font_subset_regeneration_required_after_merge: true_or_false
safe_to_integrate: true_or_false
```

## 1. 一句话结果

用一到三句话说明已经得到的用户可见结果。不要先描述过程。

## 2. 自己完成的改动

| 文件 | 操作（新增/修改/删除/生成） | 修改原因 | 可观察行为变化 |
|---|---|---|---|
| `path/to/file` | 修改 | 原因 | 用户或测试能观察到的变化 |

如果删除了任何文件，说明是否可恢复以及为什么属于任务范围。

## 3. 未修改但依赖的内容

列出任务依赖、但没有由本 Agent 修改的文件或前置条件。例如：另一个 Agent 的页面文字、现有
Fixture、临时源字体、后端虚拟环境。

## 4. 验证证据

| 命令或人工检查 | 退出码/结果 | 关键证据 | 是否最终验证 |
|---|---:|---|---|
| `exact command` | `0` | `29 tests passed` | 是/否 |

说明：

- “最终验证”表示该命令是在本 Agent 所有修改完成后运行。
- 如果只运行了子集测试，必须标记为“否”，并写出仍需运行的完整回归。
- 人工截图检查要写出截图路径和实际看到的关键文字。

## 5. 范围与安全自检

- 是否只修改允许范围：`是/否`。
- 如果否，逐个说明越界文件、原因及是否应保留。
- 是否加入新的依赖：`是/否`；如有，列出名称和理由。
- 是否发生外网请求：`是/否`；如有，只记录公开上游地址和用途，不记录凭据。
- 是否接入真实 Provider API：必须为 `否`。
- 是否读取或写入凭据：必须为 `否`。
- 是否运行了删除、覆盖、提交、推送操作：逐项说明。

## 6. 与其他 Agent 的冲突审查

| 检查项 | 结果 | 说明 |
|---|---|---|
| 是否修改另一 Agent 的禁止区域 | 无/有 | 文件列表 |
| 是否修改双方可能共享的文件 | 无/有 | 文件和建议保留哪一侧 |
| 是否新增可见中文文字 | 无/有 | 完整列出新文字 |
| 合并后是否必须重建字体 | 否/是 | 原因 |
| 合并后是否必须重跑 Web/E2E | 否/是 | 原因 |

不要只写“无冲突”。需要基于实际文件列表解释为什么无冲突；如果存在冲突，说明按文件还是按代码块
解决，并指出建议的合并顺序。

## 7. 尚未完成、失败或不确定的内容

每项使用以下格式：

- 项目：
- 原因：
- 是否阻塞集成：
- 建议负责人：Agent A / Agent B / 主 Agent / 用户：
- 建议下一步：

如果没有，明确写 `none`。

## 8. 给集成者的继续工作指令

必须按实际情况填写：

1. 推荐合并顺序。
2. 合并前需要保留或丢弃的候选改动；没有则写 `none`，不得自行丢弃用户改动。
3. 合并后第一个要运行的命令。
4. 完整回归命令顺序。
5. 需要人工检查的页面、状态和截图。
6. 当前仍禁止开始的下一阶段工作。

## 9. 最终工作树摘要

粘贴以下命令的简短输出；不得包含文件内容：

```powershell
git status --short
git diff --stat
git diff --name-status
```

对于未跟踪文件，手动补充本 Agent 创建的文件列表，因为普通 `git diff` 不会显示其内容。

## 10. 最终交付消息

Agent 在结束任务时，应在对话最终回复中同时提供：

- `status`。
- 一句话结果。
- 完成报告文件的绝对路径。
- 通过/失败的验证数量。
- 冲突结论。
- 集成者下一步。

最终回复必须与报告内容一致。


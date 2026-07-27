# Agent A 指令：中文字体与 E2E 最终收尾

> 目标工作区：`D:\APPDEsign`  
> 任务性质：写代码、生成字体子集、构建并验证。  
> 阶段边界：只完成真实 Provider API 接入前的阶段 3～5；不得接入真实 Codex、Kimi 或 GLM 服务。

## 直接执行提示词

你是 Quota Watch 的 Agent A。请先完整阅读仓库根目录 `AGENTS.md` 和
`docs/HANDOFF_PRE_API_COMPLETION.md`，然后检查当前 dirty worktree。不要 reset、覆盖或丢弃
已有修改，不要暂存、提交或推送，除非用户另行明确要求。

如果 Agent B 正在并行修改前端，本任务必须在独立 worktree 中进行。你不得修改 Agent B
负责的 `quota_watch/lib/presentation/pages/`、普通页面组件或响应式布局代码。

## 当前问题

Fixture、本地 FastAPI、Riverpod/HTTP 和主要自动测试已经完成。真实 Edge E2E 能收到
`partial` 场景响应，但 Flutter Web release 截图中的中文显示为缺字方框。语义树中的中文正确，
所以这不是 JSON/UTF-8 数据乱码，而是发布包没有内置中文字形。

已经确认：

- `quota_watch/assets/fonts/OFL-NotoSansSC.txt` 已存在。
- Noto Sans SC 上游为：
  `https://github.com/google/fonts/tree/main/ofl/notosanssc`。
- 完整源字体曾下载到：
  `C:\Users\wangz\AppData\Local\Temp\quota-watch-noto-source\NotoSansSC-wght.ttf`。
  该临时文件可能已经不存在，使用前必须检查；缺失时只从上述官方上游重新下载到临时目录。
- 完整源字体约 17 MB，不得复制或提交到仓库。
- Windows 系统字体 fallback 已实测对当前 Flutter Web Canvas 发布构建无效，相关源码已撤回，
  不要再次采用该方案。
- Flutter 自带字体裁剪工具位于：
  `E:\Move\flutter\bin\cache\artifacts\engine\windows-x64\font-subset.exe`。
- 该工具的真实调用契约是：

  ```text
  font-subset <output.ttf> <input.ttf>
  ```

  Unicode 码点通过 **stdin** 输入，用空格分隔并以换行结束。不要把字符文本或码点作为第三个
  命令行参数。

## 允许修改的文件

- `quota_watch/assets/fonts/**`
- `quota_watch/pubspec.yaml`
- `quota_watch/lib/app/theme/app_theme.dart`
- 新增 `scripts/build_font_subset.ps1`
- `scripts/e2e_web_check.py`
- 必要时小幅修改 `scripts/run_e2e.py`
- `docs/HANDOFF_PRE_API_COMPLETION.md`
- `docs/LEARNING_LOG.md`
- 新增并维护 `docs/AGENT_A_COMPLETION_REPORT.md`
- 最终验证截图 `docs/evidence/2026-07-22-stage5-backend-partial.png`
- 必要时根 `README.md` 的字体生成说明

## 禁止修改的范围

- `quota_watch/lib/presentation/pages/**`
- 除字体接入所必需内容外的 `quota_watch/lib/presentation/widgets/**`
- `quota_watch/lib/data/**`、`quota_watch/lib/app/state/**`
- `backend/app/**` 和真实 Provider 适配器
- Agent B 的前端优化指令或产出
- 任何凭据、Token、Cookie、`.env`、`auth.json` 或真实服务响应

## 实施要求

### 1. 生成可复现的字体子集

新增 `scripts/build_font_subset.ps1`，至少提供：

- 必填或明确的官方源字体路径参数。
- 可配置 Flutter 根目录参数，默认可以使用当前环境的 `E:\Move\flutter`。
- 自动定位 `font-subset.exe` 并在缺失时给出明确错误。
- 从下列 UTF-8 文件收集实际字符并去重：
  - `quota_watch/lib/**/*.dart`
  - `quota_watch/assets/fixtures/*.json`
  - `quota_watch/test/**/*.dart`
  - `backend/app/*.py`
- 将 Unicode 码点转换为十进制或十六进制字符串，通过 stdin 传给 `font-subset.exe`。
- 输出固定为：
  `quota_watch/assets/fonts/NotoSansSC-QuotaWatchSubset.ttf`。
- 生成失败、输出不存在或输出为空时，以非零状态退出。
- 脚本不得修改或删除完整源字体，也不得把完整源字体放入仓库。

当前界面文字主要位于 BMP，仍应避免只处理 ASCII。注释要说明“为什么使用随包子集”，不需要写
长篇字体教程。

### 2. 在 Flutter 中注册并使用字体

在 `quota_watch/pubspec.yaml` 的 `flutter:` 下注册字体 family，统一命名为：

```text
NotoSansSCSubset
```

字体 asset 使用：

```text
assets/fonts/NotoSansSC-QuotaWatchSubset.ttf
```

在 `AppTheme._build` 返回的 `ThemeData` 中设置该 `fontFamily`。不要继续依赖系统字体 fallback，
不要重新引入运行时 Google Fonts 网络请求。

在 `quota_watch/assets/fonts/README.md` 记录：

- 官方上游 URL。
- 字体使用 SIL Open Font License 1.1。
- 仓库只保存项目 UI 字符子集。
- 完整源字体不入库。
- 重新生成子集的命令和需要重新生成的时机。

### 3. 加固 E2E 的字体证据

保留 `scripts/e2e_web_check.py` 当前已经实现的行为：

- 等待真实的 `/api/v1/quotas?scenario=partial` 响应。
- 等待 Flutter semantics placeholder。
- 点击启用语义节点后再验证 Codex、Kimi、GLM 和 `查询失败`。
- 检查 HTTP 状态、partial JSON、控制台错误和页面错误。

再增加发布包字体清单检查：

- 请求 `/assets/FontManifest.json`。
- 断言存在 `NotoSansSCSubset` family。
- 断言它引用 `NotoSansSC-QuotaWatchSubset.ttf`。

FontManifest 和 aria-label 只能证明“字体被打包、文字数据正确”，不能证明 Canvas 真的画出了中文字形。
因此 E2E 通过后，必须使用图像查看工具实际检查最终截图。

### 4. 重新构建

使用当前 Flutter 3.44.2 支持的命令，不要添加已经不存在的 `--web-renderer` 参数：

```powershell
cd D:\APPDEsign\quota_watch
E:\Move\flutter\bin\flutter.bat build web --dart-define=QUOTA_DATA_MODE=backend --dart-define=QUOTA_SCENARIO=partial --dart-define=QUOTA_BACKEND_URL=http://127.0.0.1:8000
```

## 验证顺序

```powershell
cd D:\APPDEsign\quota_watch
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

另外完成以下只读检查：

- 查看 `docs/evidence/2026-07-22-stage5-backend-partial.png`，确认所有中文可读且没有方框。
- 截图中应能读到 `本地 FastAPI · 部分失败`、`查询失败` 和
  `模拟故障：GLM 服务暂时不可用`。
- 确认端口 7357、8000 没有遗留 `LISTENING` 进程。
- 确认 `backend/.venv/` 仍被 Git 忽略。
- 只输出文件名地扫描疑似凭据，不得打印可能的秘密内容。
- 审查完整 diff，确认没有真实 Provider 请求、凭据或完整 17 MB 字体。

## 与 Agent B 的合并规则

如果 Agent B 同时修改了可见中文文字，Agent A 分支中的字体子集只能算临时通过。合并时必须：

1. 先合并 Agent B 的前端修改。
2. 在合并后的源码上重新运行 `scripts/build_font_subset.ps1`。
3. 重新运行 Web build、两次 E2E 并人工查看截图。

原因：字体子集只包含生成时扫描到的字符，Agent B 新增的中文可能不在旧子集中。

## 完成标准

- Flutter 原有 29 个及新增测试全部通过，`flutter analyze` 无问题。
- FastAPI 8 个 pytest 通过。
- Web release build 成功。
- E2E 连续两次通过，并验证 FontManifest。
- 最终截图中文正常，无缺字方框。
- 完整源字体未进入仓库，OFL 和字体来源说明完整。
- 无测试服务遗留，无凭据，无真实 Provider API 代码。

## 统一完成报告

完成或停止工作前，必须阅读 `docs/AGENT_COMPLETION_REPORT_TEMPLATE.md`，并严格按模板新增：

```text
docs/AGENT_A_COMPLETION_REPORT.md
```

Agent A 的报告必须额外明确：

- 字体子集由哪个源码 HEAD 生成。
- 子集字体文件大小和上游源字体位置。
- `FontManifest.json` 中实际 family/asset。
- 最终截图是否由人工实际检查，看到哪些关键中文。
- Agent B 合并后是否需要重新生成子集；除非已经基于合并后的代码生成，否则必须写 `是`。
- E2E 是否连续两次在最终 build 上通过。

最终回复只报告：状态、修改内容、实际验证结果、报告路径、截图路径、冲突判断和集成者下一步。
不要写“应该可以”。

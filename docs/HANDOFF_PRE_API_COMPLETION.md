# Quota Watch：真实 API 接入前收尾交接

> 可把本文件整体交给下一位 Agent。工作区：`D:\APPDEsign`。

## 给接手 Agent 的任务提示词

请继续完成 Quota Watch 的“真实 Provider API 接入前”收尾。先完整阅读仓库根目录
`AGENTS.md`，再检查当前 dirty worktree；不得 reset、覆盖或丢弃已有修改。Codex 是唯一工作区
写入者；如果调用 GLM/Kimi，只允许做只读复核。实现优先，遇到真实问题再简短说明。

你的目标不是接入 Codex、Kimi 或 GLM 的真实额度服务，而是把阶段 3～5 的离线 Fixture、
本地 FastAPI 假后端、Flutter HTTP/Riverpod 联调、测试、浏览器 E2E 和文档收尾到可重复验证。
不要读取、请求、打印、保存或提交任何 API Key、Token、Cookie、`auth.json` 内容或真实服务响应。

## 已经完成的功能

- Flutter 支持 Fixture 与本地 FastAPI 两种数据源，设置页可切换模式、场景和后端地址。
- 支持 `normal`、`empty`、`partial`、`unconfigured`、`all_error`、`server_error` 场景。
- 已覆盖加载、正常、空、未配置、部分失败、全部失败、HTTP 503、损坏 JSON、断网和超时。
- 本地 FastAPI 提供：
  - `GET /health`
  - `GET /api/v1/quotas?scenario=...`
- Flutter HTTP 解析已使用 `utf8.decode(response.bodyBytes)`，修复 FastAPI 未声明 charset 时的中文乱码。
- 当前自动测试证据：
  - Flutter：29 个测试通过。
  - FastAPI：8 个 pytest 通过。
  - `flutter analyze`：`No issues found!`。
  - 后端模式 Web release 构建曾成功。
- 根目录 `README.md`、`PLAN.md`、学习计划和学习日志已经更新到“阶段 5 已验证、阶段 6 待明确授权”。

## 本轮刚修复但需要最终回归的内容

### 1. 后端测试从仓库根目录运行失败

已在 `backend/pytest.ini` 增加：

```ini
pythonpath = .
```

以下两种入口都已实测为 `8 passed`：

```powershell
backend\.venv\Scripts\python.exe -m pytest -c backend\pytest.ini backend\tests
```

```powershell
cd backend
.\.venv\Scripts\python.exe -m pytest
```

### 2. E2E 偶发把 HTML 到达误判为 Flutter 已启动

已修改 `scripts/e2e_web_check.py`：

- 用解析后的 URL path/query 匹配 `scenario=partial`，不再使用脆弱的字符串后缀判断。
- 用 `page.expect_response(...)` 等待真实额度接口响应。
- 等待 `flt-semantics-placeholder` 和 Codex 语义节点后再截图和断言。

修改后 `python scripts\run_e2e.py` 已连续两次通过，并且脚本能在结束时关闭 7357/8000
测试服务。接手后仍需在字体修复和新 Web 构建上重新运行。

## ~~当前唯一未完成的阻塞项：Web 发布版中文字体缺字~~（已解决，2026-07-23）

最新 E2E 截图（中文已正常）：

`docs/evidence/2026-07-22-stage5-backend-partial.png`

**阻塞已解除。** Agent A 已完成随包 OFL 中文字体子集方案：
`scripts/build_font_subset.ps1` 扫描源码唯一码点并调用 Flutter 自带 `font-subset.exe`，
生成 `quota_watch/assets/fonts/NotoSansSC-QuotaWatchSubset.ttf`（306 528 字节，731 码点），
在 `pubspec.yaml` 注册 `NotoSansSCSubset` 并在 `app_theme.dart` 设置 `fontFamily`。
最终截图经人工查看：Codex/Kimi/GLM 三家卡片中文全部可读，无缺字方框；
GLM 卡显示「查询失败」「模拟故障：GLM 服务暂时不可用」。
E2E 已增加 `FontManifest.json` 断言并连续两次通过。

注意（历史背景，方案已换，勿再尝试）：之前在 `ThemeData` 中添加 Windows 系统字体 fallback，
发布版实测无效，源码已撤回；不要重复该方案。

## 字体收尾的推荐方案（已落地）

使用随包分发的 OFL 开源字体子集，保证离线、Edge 和不同机器都能显示当前 UI 汉字。
**以下步骤 Agent A 已全部完成，仅留作复现参考：**

已完成的准备：

- 官方字体来源：
  `https://github.com/google/fonts/tree/main/ofl/notosanssc`
- OFL 许可证已下载到：
  `quota_watch/assets/fonts/OFL-NotoSansSC.txt`
- 17,772,300 字节的官方变量源字体已下载到临时路径（不应把完整源字体提交到项目）：
  `C:\Users\wangz\AppData\Local\Temp\quota-watch-noto-source\NotoSansSC-wght.ttf`
- Flutter 自带的裁剪工具位于：
  `E:\Move\flutter\bin\cache\artifacts\engine\windows-x64\font-subset.exe`

复现步骤（已完成）：

1. 用 `font-subset.exe` 从官方源字体生成当前 UI 所需字符的 TTF 子集，目标路径：
   `quota_watch/assets/fonts/NotoSansSC-QuotaWatchSubset.ttf`。
2. 字符集合扫描这些 UTF-8 文本源中的实际可见字符：
   - `quota_watch/lib/**/*.dart`
   - `quota_watch/assets/fixtures/*.json`
   - `backend/app/*.py`
   - `quota_watch/test/**/*.dart`
3. 可复现的 PowerShell 生成脚本：`scripts/build_font_subset.ps1`
   - 接收官方源字体路径和 Flutter 根目录参数；
   - 收集唯一 Unicode codepoint；
   - 调用 `font-subset.exe <output.ttf> <input.ttf>`，通过 stdin 输入 codepoint；
   - 不把完整源字体复制进仓库。
4. `pubspec.yaml` 的 `flutter:` 下声明字体 asset 和 family：`NotoSansSCSubset`。
5. `app_theme.dart` 的 `ThemeData` 设置该 family。
6. `assets/fonts/README.md` 记录上游、OFL 许可证、子集用途和重新生成方法。
7. E2E 请求 `assets/FontManifest.json`，断言 `NotoSansSCSubset` 和对应 asset 已进入发布包；
   语义文本断言不能证明画布中文字形正常，因此最终仍要实际查看截图（已完成）。

## 必须执行的最终验证

先重新构建后端模式的 partial 场景：

```powershell
cd D:\APPDEsign\quota_watch
E:\Move\flutter\bin\flutter.bat build web --dart-define=QUOTA_DATA_MODE=backend --dart-define=QUOTA_SCENARIO=partial --dart-define=QUOTA_BACKEND_URL=http://127.0.0.1:8000
```

然后执行：

```powershell
cd D:\APPDEsign\quota_watch
E:\Move\flutter\bin\flutter.bat analyze
E:\Move\flutter\bin\flutter.bat test

cd D:\APPDEsign
backend\.venv\Scripts\python.exe -m pytest -c backend\pytest.ini backend\tests
python scripts\run_e2e.py
python scripts\run_e2e.py
git diff --check
```

最终还要完成这些只读检查：

- 实际打开并检查 `docs/evidence/2026-07-22-stage5-backend-partial.png`，确认中文可读，GLM 显示
  `查询失败`，错误说明是 `模拟故障：GLM 服务暂时不可用`。
- 确认 7357 和 8000 没有遗留 `LISTENING` 进程。
- 只输出文件名地扫描新增代码是否含疑似凭据；不要在终端打印可能的秘密内容。
- 确认 `backend/.venv/` 仍被 Git 忽略。
- 审查完整 diff；不要提交或暂存，除非用户另行明确要求。

## 文档收尾

字体与 E2E 全部通过后，在 `docs/LEARNING_LOG.md` 的本次阶段 3～5 记录中补充两条证据：

- E2E 启动竞态已改为等待真实 API 响应和 Flutter 语义节点。
- Web 发布包已经内置 OFL 中文字体子集，最终截图无缺字。

不要把历史会话记录中的旧状态当成当前状态，也不要为了“看起来整齐”重写历史记录。

## 完成标准与交付口径

只有以下事实同时成立，才能向用户说“真实 API 接入前阶段已完成”：

- FastAPI 8/8、Flutter 29/29、静态分析、Web build 全部通过。
- Edge E2E 连续两次通过，截图中文正常且 partial 场景显示正确。
- 无凭据、无外网 Provider 调用、无测试服务遗留。
- 真实 Codex/Kimi/GLM 适配器代码仍为零；阶段 6 必须等待用户明确授权。

最终回复应简短、结果优先，链接根 `README.md` 和最终 E2E 截图，并明确“没有接入真实 API”。

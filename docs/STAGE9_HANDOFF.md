# Stage 9 交接文档：Windows 桌面小组件 + 假数据移除

> 本文档供接手 agent 使用。目标：让后续工作无需重新探索即可继续。
> 最后更新：Stage 9 的真正桌面层、无面板多区域磁贴、合成黑带修复、托盘恢复、launcher
> 竞态修复与常驻运行轻量化均已完成自动验证。
> 下一步工作：S9-5 开机自启 / S9-6 msix 打包。

---

## 一、本次完成的工作（已验证，不要重做）

### A. Windows 桌面平台壳（S9-1）
- `flutter create --platforms=windows .` 生成 `quota_watch/windows/`（runner.exe + CMake + 图标资源）
- `.metadata` 登记 windows 平台
- 前提：已装 Visual Studio 2026 Community + C++ 桌面工作负载；已开启 Windows 开发者模式（插件符号链接需要）
- 验证：`flutter build windows` 成功，`flutter run -d windows` 起来

### B. 无边框置顶小窗（S9-2）
- 加依赖：`window_manager: ^0.5.2`（pubspec.yaml）
- **conditional import 架构**（关键，保 Web 构建）：
  - `lib/app/desktop/desktop_controller.dart` — 接口 + `DisplayMode` 枚举 + 条件导入
  - `lib/app/desktop/desktop_controller_io.dart` — 原生真实现
  - `lib/app/desktop/desktop_controller_web.dart` — Web 空实现
  - `lib/app/desktop/window_drag_area.dart` + `_io.dart` + `_web.dart` — 同样的拖拽区三件套
- `main.dart` 改 `async main()` + `WidgetsFlutterBinding.ensureInitialized()` + `await DesktopController.instance.init()`
- 当前窗口配置：360×680、`titleBarStyle: TitleBarStyle.hidden`；启动后按所选显示模式定位
- 无边框后用 `DragToMoveArea` 给标题文字补回拖动能力（**注意：只包标题文字，不包整个 AppBar，否则吞掉 body 的下拉刷新手势** —— 见 C 节的坑）

### C. 系统托盘 + 菜单（S9-3）
- 加依赖：`tray_manager: ^0.5.3`
- 托盘图标：`assets/logos/quota_watch_icon.ico`（紫色百分比环，Pillow 生成，多分辨率 16/24/32/48/64/128/256）
  - **关键坑**：Windows 托盘底层用 `LoadImage(IMAGE_ICON, LR_LOADFROMFILE)`，**只认 `.ico` 不认 `.png`**。png 会让图标加载静默失败（空白）
  - 应用窗口图标也已替换：`windows/runner/resources/app_icon.ico`
- 托盘菜单：显示 / 显示模式切换（checkbox）/ 数据设置 / 退出
- `setPreventClose(true)` 必须在 `init` 里（窗口就绪后）就设，不能放到 `onWindowClose` 内部（时序错误会导致点✕直接关窗而非回调）
- 托盘图标在初始显示模式前注册；Windows 右键菜单始终使用初始化时保存的应用 HWND，
  避免窗口样式变化后 popup owner 漂移

### D. 桌面悬浮插件模式（目标"出现在桌面上的插件"，方案1）
- **`DisplayMode` 枚举**：`alwaysOnTop`（置顶小窗）/ `desktopWidget`（桌面悬浮插件）
- `setDisplayMode(mode)` 切换，托盘菜单 checkbox 反映当前模式；选择当前已勾选模式也会
  `show → apply`，不能提前返回；只有“置顶小窗”切换会主动 focus
- 桌面悬浮模式窗口属性（`_applyDisplayMode`）：
  - **不要使用 `setAlwaysOnBottom(true)`**：用户运行时证明它会把顶层窗口压到壁纸之后
  - 正常状态保持无 owner 的普通顶层窗口，`alwaysOnTop=false`、`skipTaskbar=true`
  - 插在 Explorer 最高 `WorkerW/Progman` 桌面合成层正上方；普通应用能覆盖
  - 首帧后放到当前光标所在显示器工作区右上角
  - 启动、加载、设置和置顶模式使用不透明窗口底色，不调用运行期 `setOpacity`
  - 三张磁贴区域建立后，原生 Accent 底色与 Flutter 页面画布才同步透明；磁贴自身暗色/亮色
    空白处约 46%/53% alpha。不要把透明时序前移到 Flutter 首帧之前
  - 首页监听 `DesktopController.displayModeListenable`：`desktopWidget` 隐藏整个 AppBar，
    只显示磁贴；`alwaysOnTop` 恢复标题、设置、最小化和关闭。桌面模式的这些操作从托盘进入
  - 桌面首页用 `GlobalKey` 测量三张卡片的真实矩形，经 MethodChannel 调用 Win32
    `SetWindowRgn`，把不透明窗口裁成三个圆角区域的并集；卡片间隙与底部空白不属于窗口，
    可把输入继续交给下层窗口
  - 桌面模式调用 `windowManager.setAsFrameless()`，原生侧同时保存并移除 caption、
    thick frame、系统菜单和扩展窗口边缘；实际外窗与 Flutter 客户区均为 360×680，
    不再露出 4px 左右边缘和 5px 底部黑框
  - `SetWindowRgn` 不会自动停止 `window_manager` 的 Accent 原生底色矩形合成。首页完成
    卡片测量、准备应用三个区域时才把原生底色设为透明；进入设置、加载/空/错误状态或置顶模式
    时，先恢复不透明 `#121318` 再清除区域。不要把透明底色前移到启动阶段
  - 退出桌面模式时恢复原始 `STYLE/EXSTYLE`，并把标题栏模式恢复为
    `TitleBarStyle.hidden`，置顶小窗的系统窗口行为不变
  - 设置页、加载/空/错误状态与 `alwaysOnTop` 模式会清空裁形并恢复完整矩形；返回桌面首页、
    滚动或数据刷新后重新测量区域
  - **生产路径明确关闭** Flutter 主窗口的 Shell `SetParent` 和 `WS_EX_TOOLWINDOW`
- **`Win+D` 的独立处理**：
  - Show Desktop 会把桌面窗口整体抬到普通窗口之上，单纯阻止 `SC_MINIMIZE` 无效
  - 原生侧用两个独立的 0×0 隐藏窗口检测桌面 Z-order；这两个窗口不承载 Flutter surface
  - 桌面被抬起时，主窗口临时进入 topmost 带的最底部；普通应用恢复后立即退出 topmost
  - 兼容 `SHELLDLL_DefView` 位于 `Progman`（Windows 11 24H2+）或 `WorkerW` 的两种层级
- **为什么不再把 Flutter 主窗口挂到 `Progman` 或设为 `WS_EX_TOOLWINDOW`**：
  - Shell 子窗口会改变托盘插件的 `GA_ROOT`
  - 实机把顶层 Flutter 窗口切为 `WS_EX_TOOLWINDOW` 后，HWND/矩形仍存在，但实际截图只有透明区域
  - Alt+Tab 隐藏留给后续不破坏 Flutter renderer 的方案
- **原生 channel 实现**：
  - `windows/runner/flutter_window.cpp` 注册 `MethodChannel('quota_watch/window')`
  - 生产使用固定 HWND 的 `showTrayMenu` 和多显示器感知的 `positionDesktopWidget`
  - `setDesktopWidget(true)` 启用桌面状态跟踪；`setToolWindow(true)` 仅保留为可逆诊断入口，
    生产路径只调用 `setToolWindow(false)`
  - ⚠️ flutter_window.cpp 的注释**必须用英文**，中文注释触发 MSVC C4819 编码警告
- 启动模式 dart-define：`--dart-define=QUOTA_DISPLAY_MODE=desktop_widget`（默认 `always_on_top`）。**dart-define 是编译期常量，改值要重新 `flutter build`**
- **最新运行期与像素证据**：
  - 只有 1 个实例；普通顶层窗口（parent=0）；`visible=True`、未最小化
  - 正常状态 `Owner=0`、`Topmost=False`、`WS_EX_TOOLWINDOW=False`
  - 矩形 `[2204,16,2544,536]`，距当前工作区顶部/右侧各约 16px
  - 最大化普通应用覆盖同一屏幕区域的真实像素对比通过
  - 用户实机确认 `Win+D` 后小组件仍存在；返回普通应用后探针确认 `Topmost=False`

### E. 修复的两个回归（D 完成后发现的）
1. **下拉刷新失效**：`WindowDragArea` 原本包了整个 AppBar，内部 `DragToMoveArea` 用 `HitTestBehavior.translucent` 吞掉所有 pan 手势 → body 的 RefreshIndicator 收不到下拉。修复：只把标题文字 `Text('Quota Watch')` 包进拖拽区。验证：新增 widget test `标题栏可拖动窗口时，列表仍可下拉刷新`（fling 后 `repo.loads > 1`），**测试通过**
2. **收起后无法恢复**：收起改为 `hide()`；托盘“显示”和模式选择都先 `show()`，
   再重放当前窗口属性并聚焦。即使“桌面悬浮插件”已经勾选，再点一次也会恢复同一个窗口。

### F. 移除全部展示用假数据
**前端：**
- 删 `lib/data/fixtures/`（FixtureQuotaRepository）、`lib/data/mock/mock_data.dart`（MockQuotaRepository）、`assets/fixtures/`（5 个假场景 JSON）
- 删 `DataSourceMode` enum、`DemoScenario` 的 6 个假场景；改名 `DemoScenario`→`QuotaScenario`（只剩 4 个真实场景：codexReal/kimiReal/glmReal/allReal，默认 allReal）
- `lib/app/state/quota_state.dart` 重写：固定走真实后端，`quotaRepositoryProvider` 只返回 `BackendQuotaRepository`
- `lib/presentation/pages/settings_page.dart` 重写：删数据来源下拉，只剩真实场景选择 + 后端地址
- `pubspec.yaml` 删 `assets/fixtures/`
- 新增 `test/helpers/sample_quota_repository.dart`（测试专用样本数据，非生产代码，替代被删的 MockQuotaRepository）

**后端：**
- 删 `app/scenarios.py`（全部假场景生成器）、`app/providers/{fake,kimi_fixture,glm_fixture,codex_adapter,codex_manual}.py`
- 删 `/api/v1/quotas` 的假场景分支 + `server_error` 分支；默认 scenario 从 `normal` 改 `all_real`
- 删 experimental 聚合路由（`/api/v1/experimental/aggregate`）及其开关 `QUOTA_WATCH_EXPERIMENTAL_AGGREGATE`
- `models.py` 的 `HealthResponse.service` 从 `quota-watch-fake-backend` 改 `quota-watch-local-backend`
- **保留**：三个真实适配器（codex_app_server/kimi_adapter/glm_adapter）、解析器回归样本（`backend/fixtures/*.json` 脱敏样例）、infra（aggregator/base/parser）
- **测试 helper 移到 `backend/tests/`**（非生产代码）：`fake_provider.py`（FakeProviderAdapter）、`fixture_adapters.py`（KimiFixtureAdapter/GlmFixtureAdapter，驱动真实 parser）。`tests/__init__.py` 让其成包，import 改 `from tests.fake_provider import` / `from tests.fixture_adapters import`
- 删除的测试文件：`test_api.py`、`test_codex_manual.py`、`test_codex_aggregate.py`、`test_experimental_aggregate_route.py`、`test_experimental_aggregate_staleness.py`

**顺带修的真实 bug（假数据移除过程暴露）：**
- `scripts/start_quota_watch.ps1` 加 UTF-8 BOM（之前无 BOM，PowerShell 5 按GBK读中文注释→命令解析错乱）。smoke test 的 `scenario=normal` 改 `all_real`
- `backend/tests/test_one_click_launcher.py` 的 `_run_launcher` 加 `encoding="utf-8", errors="replace"`（PowerShell 中文输出在 UTF-8 模式下解码崩溃）

### G. 仓库内 EXE 一键启动
- 普通根目录 EXE 启动时，`scripts/start_quota_watch.ps1` 只作为一次性引导：它仍是唯一负责
  Key 映射、端口保护和健康检查的边界，并用无控制台的 `pythonw.exe` 启动后端。
- 引导脚本启动 Windows release 前端后，通过只含 PID/状态、不含额度或凭据的临时文件完成
  运行时交接并退出；GUI launcher 等待前端，退出时回收本次拥有的后端进程树。
- `-ValidateOnly`、Smoke、Edge 与 `-KeepBackend` 等开发模式仍走原 PowerShell 工作流。
- 新增 `scripts/launcher/QuotaWatchLauncher.cs` 与 `scripts/build_windows_launcher.ps1`
- 根目录生成 `启动 Quota Watch.exe`；它只是启动壳，不读取 Key
- 当前 EXE 依赖完整仓库、`backend/.venv`、PowerShell 和 release 构建目录，**不是可独立分发安装包**
- 启动器专项 9 项通过，含编译 EXE、临时后端、假桌面前端和退出清理的端到端测试
- 后续根据用户反馈改为 Windows GUI subsystem；PowerShell 使用 `CreateNoWindow`，双击不再显示终端
- 启动失败会弹出安全错误框，脱敏日志写入 `%TEMP%\quota-watch-launcher`
- launcher 使用单实例互斥；第二次双击会向已有 Flutter 窗口投递托盘左击消息并唤醒它。
  若旧 launcher 仍持有互斥量但窗口已经退出，新实例会有限等待并在互斥量释放后接管；
  测试构建使用独立互斥名称，不受正在运行的正式应用影响
- 轻量化稳态实测：常驻关联进程由 7 个降为 4 个，不再常驻 PowerShell/conhost；工作集约
  370.4 MB → 247.9 MB（约 -33%），私有内存约 264.8 MB → 189.5 MB（约 -28%）。
- 强制结束前端的边界复测也能清理 launcher、两级 Python 后端和 8000 端口；任务卡见
  `docs/STAGE9_LIGHTWEIGHT_RUNTIME_TASK.md`。

### H. 托盘与悬浮窗运行时修复
- 托盘图标在初始显示模式前注册，Shell 回调 HWND 保持为 Quota Watch。
- Windows 右键菜单由 `WindowNative.showTrayMenu` 使用保存的应用 HWND 和
  `TPM_RETURNCMD` 创建。
- `WindowNative.positionDesktopWidget` 在 Flutter 首帧后最终定位，避免延迟 `center()` 覆盖
- 收起使用 `hide()`；托盘“显示”和两个模式菜单都能重新显示当前窗口
- 悬浮模式使用可见普通顶层窗口；正常状态非 topmost，普通应用可覆盖
- `Win+D` 状态由隐藏 sentinel 检测，主窗口临时跟随 topmost helper；恢复应用后重新停回桌面层
- Flutter 主窗口不启用 Shell 子窗口、toolwindow 或透明 opacity
- 任务卡：`docs/STAGE9_DESKTOP_RUNTIME_FIX_TASK.md`

### I. 360×680 紧凑玻璃磁贴（S9-4）
- 小组件改为 360×680 右侧竖向信息条，默认三家、每家两个窗口时完整进入首屏；内容变多或
  系统大字体时仍可滚动。
- 窄窗三张磁贴纵向排列；700px 以上两列、1100px 以上三列，宽屏形成横向长条。
- 磁贴使用 Flutter 半透明表面、细描边与轻量模糊。桌面组件在三张原生区域建立后才同步移除
  Accent 底色和 Flutter 页面底色；置顶小窗仍使用不透明环境渐变，因此不改变已验收的
  `Win+D`、窗口层级与启动安全路径。
- `5 小时窗口`、`5h limit`、`Weekly limit`、`周窗口` 等原始标签只在 UI 层统一为
  `5 小时额度`、`7 天额度` 等“时间/用途 + 额度”文案。
- 每个窗口只显示统一名称、`已用 X%`、进度条和重置时间；已删除“已用 / 剩余 / 上限”三列。
- 进度动画尊重系统“减少动态效果”；整卡语义包含套餐状态和各窗口摘要。
- 桌面模式去掉卡片外阴影和厚重百分比徽标；状态使用彩色圆点 + 文字，百分比使用纯文本，
  保留细描边、进度条和重置时间。每张卡片标题区域仍是无标题栏窗口的拖动入口。
- 实机 `GetWindowRgn` 为复杂区域，纵向中心线只包含三段卡片区域；两处 10px 间隙和底部
  90px 空白均被原生窗口区域排除。普通应用覆盖和 `Win+D` 路径没有改变。
- 黑边修复后实机 `STYLE=0x94000000`、`EXSTYLE=0x0`，没有 caption、thick frame 或
  window edge；360×680 外窗与客户区完全一致，客户区偏移为 `0,0`。
- 用户仍反馈可见黑边后，虚构数据物理屏幕截图确认还有第二根因：区域外 Accent 底色固定为
  `#121318`。延迟透明修复后，同一位置已变为桌面下层实际颜色，卡片与桌面直接相接。
- 恢复根目录真实启动器后，再次只捕获不含文字/额度的右侧边缘；实际运行实例同样没有
  `#121318`，证明最终 Release 已包含该修复。用户主观复验仍是任务卡最后一项。
- 卡片透明度二次修复后，暗/亮 Golden 的卡片外 alpha 为 0、卡片空白处约为 46%/53%。
  虚构 Release 中相邻桌面为 `#4B1C1C` 时，卡片内为 `#B49C9B`，桌面壁纸纹理可连续透过；
  真实启动实例的无文字边缘复查结果一致。
- 任务卡：`docs/STAGE9_COMPACT_GLASS_TILE_TASK.md`
- 无面板裁形任务卡：`docs/STAGE9_SEAMLESS_DESKTOP_TILES_TASK.md`
- 黑边修复任务卡：`docs/STAGE9_BLACK_EDGE_FIX_TASK.md`
- 卡片真实透明任务卡：`docs/STAGE9_CARD_TRANSPARENCY_TASK.md`

---

## 二、当前验证状态（绿）

| 检查 | 命令 | 结果 |
|---|---|---|
| 前端静态分析 | `cd quota_watch && flutter analyze` | ✅ No issues found |
| 前端测试 | `cd quota_watch && flutter test` | ✅ 50 全过（含窄窗、路由裁形、刷新与暗/亮 Golden） |
| Web 构建（隔离验证） | `cd quota_watch && flutter build web` | ✅ Built |
| Windows 构建 | `cd quota_watch && flutter build windows [--dart-define=...]` | ✅ Built |
| 后端测试 | `cd backend && .venv\Scripts\python.exe -m pytest -c pytest.ini tests` | ✅ 414 全过 |
| 启动器校验 | `启动 Quota Watch.exe -ValidateOnly` + 专项 pytest | ✅ validation；9 passed |
| 无终端启动 | PE subsystem + 隐藏 PowerShell + 根目录 EXE smoke | ✅ subsystem=2；exit 0 |
| 悬浮窗口 | Win32 parent/style/rect + 双启动 | ✅ 顶层、正常非置顶、右上角、单实例 |
| 显示桌面 | 用户 `Win+D` + 返回后 Win32 探针 | ✅ 桌面仍显示；返回后 `Topmost=False` |
| 桌面插件像素证据 | Computer Use 截图 + 可访问控件树 | ✅ 实际页面可见，不是透明 HWND |
| 托盘绑定与恢复 | Shell icon HWND + hide/left-click restore | ✅ 绑定应用；隐藏后恢复 |
| 托盘右键菜单 | 原生回调后检查 `#32768` 菜单 | ✅ 8 项；5 个可见命令 |
| 真实收起/重复双击恢复 | Computer Use 点击 + 再启动根 EXE | ✅ 同一窗口重新成为前台顶层窗 |
| 当前模式恢复 | hide + 托盘选择已勾选 desktopWidget | ✅ 同一窗口 ID 重新出现 |
| launcher 退出竞态 | 互斥量占用 2 秒后释放 | ✅ 等待后接管；应用/launcher 各 1 |
| 紧凑玻璃磁贴 | 360×680 几何测试 + 虚构数据暗/亮 Golden | ✅ 三张首屏、统一文案、无裁切 |
| 无面板原生裁形 | 实机 `GetWindowRgn` + 区域/路由回归 | ✅ 3 个不连续圆角区域；间隙和底部不命中应用 |
| 原生黑边 | Win32 `STYLE/EXSTYLE` + 外窗/客户区探针 | ✅ 无系统边缘；360×680 = 360×680，偏移 0 |
| 合成黑带 | 虚构 Release + 200% DPI 物理屏幕边缘像素 | ✅ `#121318` 已替换为桌面下层实际像素 |
| 数据卡片真实透明 | 透明 Golden + 虚构/真实 Release 无文字边缘 | ✅ 桌面纹理参与磁贴 alpha 混合 |
| 常驻运行轻量化 | 实际启动资源采样 + 重复双击 + 强制前端退出 | ✅ 7→4 进程；工作集约 -33%；无孤儿后端 |

---

## 三、未完成的工作（接手 agent 的待办）

### S9-5：开机自启（pending）
- **不用 `launch_at_startup` 包**（凭据边界：exe 不碰 key，自启应注册启动脚本而非裸 exe）
- 方案：写 `scripts/install_autostart.ps1`，把调用 `启动 Quota Watch.exe` 的快捷方式或命令写入
  `shell:startup`，支持卸载
- `start_quota_watch.ps1 -Desktop` 已完成，不要重复实现

### S9-6：msix 打包（pending）
- 加 dev 依赖 `msix: ^3.16.0`，配 `pubspec.yaml` 的 `msix_config:`
- `flutter pub run msix:create` 产出 `.msix`
- ⚠️ **自启不打包进 msix**：安装版自启仍依赖 dev 仓库的启动脚本（backend+venv+key 映射在仓库侧）。把 Python backend 一并打包成完全自包含是 AGENTS.md 说的"需独立安全设计"的后续里程碑

### 文档
- `docs/STAGE9_DESKTOP_RUNTIME_FIX_TASK.md` 与本交接已更新到最终桌面层方案
- `docs/STAGE9_COMPACT_GLASS_TILE_TASK.md` 记录紧凑玻璃磁贴的范围、设计与验证证据
- `docs/STAGE9_SEAMLESS_DESKTOP_TILES_TASK.md` 记录无面板多区域裁形与实机证据
- `docs/STAGE9_BLACK_EDGE_FIX_TASK.md` 记录非客户区黑边的根因、两阶段修复与实机证据
- `docs/LEARNING_LOG.md` 已补充 `Win+D` 和 S9-4 视觉改版证据

### 潜在改进（非阻塞）
- 研究不触发 Flutter surface 透明的 Alt+Tab 隐藏方法
- 若产品仍要求“嵌入桌面壁纸层且普通应用覆盖”，应单独设计宿主/渲染架构，不要直接恢复 `SetParent`
- 托盘图标在 Win11 默认折叠进 `^` 抽屉（未签名 exe 的系统策略）；签名后（S9-6 msix）通常更友好

---

## 四、关键约束（硬规则，来自 AGENTS.md）

1. **凭据安全**：`KIMI_CODING_API_KEY`/`GLM_API_KEY` 只能由 `start_quota_watch.ps1` 注入 backend 子进程。**绝不进 Flutter exe、tests、日志、fixtures、截图、Git**。桌面 exe 不碰 key
2. **保留离线确定性测试**：测试用 stub（`tests/fake_provider.py`、`tests/fixture_adapters.py`、`test/helpers/sample_quota_repository.dart`）而非连真实后端。这些 stub 不产生用户可见数据
3. **改动前先读现有代码**：conditional import 架构、原生 channel、_applyDisplayMode 都有微妙时序，改动前务必读 `desktop_controller_io.dart` 全文
4. **flutter_window.cpp 注释用英文**（MSVC C4819）
5. **PowerShell 脚本保持 UTF-8 BOM**（中文注释在 PS5 无 BOM 会解析错乱）
6. **改 dart-define 值必须重新 `flutter build`**（编译期常量）

---

## 五、运行/验证命令速查

```powershell
# 前端
cd quota_watch
E:\Move\flutter\bin\flutter.bat analyze
E:\Move\flutter\bin\flutter.bat test
E:\Move\flutter\bin\flutter.bat build windows --dart-define=QUOTA_DISPLAY_MODE=desktop_widget

# 后端
cd backend
.venv\Scripts\python.exe -m pytest -c pytest.ini tests

# 构建并校验 EXE 启动器（不真正启动）
powershell -ExecutionPolicy Bypass -File scripts\build_windows_launcher.ps1
& "D:\APPDEsign\启动 Quota Watch.exe" -ValidateOnly

# 启动前后端（双击或命令）
& "D:\APPDEsign\启动 Quota Watch.exe"
# Edge 开发入口
& "D:\APPDEsign\启动 Quota Watch.cmd"
# 或直接跑前端 exe（前提后端已在 8000 端口）
quota_watch\build\windows\x64\runner\Release\quota_watch.exe
```

**Flutter/Dart 路径**：`E:\Move\flutter`（3.44.2 / Dart 3.12.2）
**Python**：`backend\.venv\Scripts\python.exe`（3.12）

---

## 六、已知坑清单（避免重蹈）

| 坑 | 现象 | 解法 |
|---|---|---|
| 托盘用 png | 图标空白 | 必须用 .ico（Pillow 从 png 转） |
| setPreventClose 放 onWindowClose 内 | 点✕直接关窗 | 必须在 init 窗口就绪后立即设 |
| WindowDragArea 包整个 AppBar | 下拉刷新失效 | 只包标题文字 |
| 窗口使用 minimize/restore | 收起后无法重新打开 | 使用 hide/show 并重放当前模式 |
| popup 动态选择 owner | 图标存在但点击无响应 | 原生 popup 固定使用应用 HWND |
| 恢复后仍挂在 Progman | visible=True 但用户看不见 | 生产路径保持普通顶层窗口 |
| Flutter 主窗口使用 HWND_BOTTOM | 进程可见但落到壁纸后 | 主窗口插到最高 Explorer 桌面层正上方 |
| WS_EX_TOOLWINDOW | HWND 存在但 Flutter 画面透明 | 生产路径明确关闭 toolwindow |
| 只拦截 SC_MINIMIZE | `Win+D` 后仍被桌面覆盖 | sentinel 检测桌面抬升，临时进入 topmost 带最底部 |
| 当前模式提前 return | 点已勾选“桌面悬浮插件”无反应 | 模式选择始终 show/apply；置顶模式再 focus |
| 旧 launcher 正在退出 | 新双击静默无窗口 | 等待互斥量释放并接管，超时明确提示 |
| flutter_window.cpp 中文注释 | MSVC C4819 警告 | 注释用英文 |
| PowerShell 脚本无 BOM | 中文注释致命令解析错乱 | 保存为 UTF-8 BOM |
| smoke test scenario=normal | 422（normal 已删） | 改 all_real |
| 用 `timeout` 跑 GUI exe | 进程残留锁文件 | 用 `taskkill /F /IM quota_watch.exe` 清理，或 `cmd //c start` 独立启动 |

---

## 七、架构要点图

```
Flutter exe (quota_watch.exe, C++ runner 壳 + Flutter 引擎)
  ├─ lib/main.dart (async, ensureInitialized, DesktopController.init)
  ├─ lib/app/desktop/
  │   ├─ desktop_controller.dart     [接口 + DisplayMode enum + 条件导入]
  │   ├─ desktop_controller_io.dart  [Windows 真实现: window_manager + tray_manager]
  │   ├─ desktop_controller_web.dart [Web no-op]
  │   ├─ window_drag_area*.dart      [拖拽区三件套]
  │   └─ window_native_io.dart       [原生 channel: tray popup + positioning]
  ├─ windows/runner/flutter_window.cpp [注册 quota_watch/window channel]
  └─ lib/app/state/quota_state.dart  [QuotaScenario enum, 只走真实后端]

本地后端 (Python FastAPI, 127.0.0.1:8000)
  ├─ app/main.py     [/health, /api/v1/quotas?scenario=all_real]
  ├─ app/providers/  [codex_app_server, kimi_adapter, glm_adapter 真实适配器]
  └─ 凭据由 start_quota_watch.ps1 注入子进程

启动脚本
  ├─ scripts/start_quota_watch.ps1 [一次性引导: 注入后端 key、健康检查、起前端, UTF-8 BOM]
  └─ 启动 Quota Watch.exe [单实例 + 前端监督 + 自有后端进程树回收]
```

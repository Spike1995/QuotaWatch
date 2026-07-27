# Quota Watch 学习进度与复盘日志

> 本文件记录学习证据，不记录愿望。只有命令、测试、可操作成果或能够清楚解释的知识才算进度。
>
> 当前工作区是 Windows + PowerShell，因此示例使用 Windows 命令；其他系统使用等价 Shell 命令即可。

详细路线见 [VIBE_CODING_LEARNING_PLAN.md](VIBE_CODING_LEARNING_PLAN.md)。

## 个性化学习约定（2026-07-22）

- 目标：允许持续使用 AI，但要能自己定义任务、判断建议、运行验收并交付可供他人使用和贡献的开源软件。
- 学习主线：优先熟悉从需求、前端、数据契约、后端/API、测试、调试、Git 到构建发布的全栈交付流程，不把课程重心放在孤立的 Dart、Flutter 或 Python 语法细节上。
- 技术细节策略：语法和框架概念只在当前任务第一次需要时解释到“足以理解、修改和验证”的深度；源码注释用于随查，不要求集中背诵。
- 协作节奏校准：采用“实现优先”；Codex 先完成一个小而可验证的功能，遇到错误、风险、产品选择或用户主动提问时再讨论。
- 交付方式：结论简短，不用突然提问代替教学；需要复盘时再共同整理三句话。
- 节奏：每周 6 天、每天约 2 小时，保留 1 天休息；采用边做边学。
- 平台：先在 Windows 主机完成学习版，Web/Android/iOS 不并行推进。
- 数据：阶段 0～5 只使用 Mock、Fixture 和本地 FastAPI 假接口；真实额度 API 延后。
- 分工：Codex 主控、教学、编辑与验证；GLM 主要做后端/编程只读审查；Kimi 主要做 Flutter UI/交互只读审查。
- 验收：每张任务卡由学习者亲自运行一个关键命令或操作路径，并用三句话说明“改了什么、为什么、怎样证明”。
- 每周练习：安排一次约 20 分钟的无 AI 小练习，用来暴露知识缺口，不追求复杂代码。

## 状态说明

- `未开始`：尚未进入阶段。
- `学习中`：正在理解概念或完成任务卡。
- `已实现`：代码或文档已存在，但验收尚未完整通过。
- `已验证`：Definition of Done 有证据支持。
- `能讲解`：可以脱离 AI 解释设计、失败路径与测试。

阶段只有达到“已验证 + 能讲解”才算毕业。

## 阶段追踪

| 阶段 | 当前状态 | 已有证据 | 下一项证据 |
|---|---|---|---|
| 0. 工具链与运行闭环 | 已验证 + 能讲解 | Flutter 3.44.2、doctor、依赖、静态分析、2 个 Widget 测试、Web 构建、Edge 人工验收、运行截图及启动/功能边界讲解均已完成 | 进入阶段 1 / 卡 1 |
| 1. Dart 与 Flutter UI | 已验证，待全栈迁移 | `QuotaWindow` 正常/零上限/紧张/耗尽/过期测试及 100%“耗尽”Widget 测试已实现；用户亲自确认 8 个测试通过 | 在 Repository 解耦卡中保持 UI 行为不变 |
| 2. Vibe Coding 工程基线 | 代码已验证，概念按需复盘 | Repository 接口、Mock 注入和替换点已经建立 | 后续任务继续用 diff、测试和小步修改巩固 |
| 3. 假数据契约与状态 | 已验证 | 正常、加载、空、未配置、部分失败、全部失败和读取失败均有离线测试 | 进入阶段 4 |
| 4. FastAPI 假后端 | 已验证 | `/health`、六种场景、结构化 503；8 个 pytest 通过 | 进入阶段 5 |
| 5. 假数据端到端 | 已验证 | Riverpod、HTTP Repository、设置页；37 个 Flutter 测试、静态分析无问题、Web 构建和真实浏览器 E2E 通过、Web 发布包内置 OFL 中文字体子集 | 阶段 6 开始前重新做安全与接口复核 |
| 6. Codex 真实额度 | 代码与自动验证完成，待用户 UI 验收/讲解 | 官方本地 app-server 纵切片；真实脱敏结构读取成功；后端 376、Flutter 42 测试通过 | 用户按 README 查看自己的真实窗口，并用三句话完成验收 |
| 7. Kimi/GLM + 三家聚合 | 代码与自动验证完成，待用户最终 GLM 对照/讲解 | Kimi 脱敏真实结构读取；GLM 当前/历史双契约、三窗口脱敏复验；`all_real` 独立开关、并发与失败隔离 | 用户只反馈 GLM 三项是否与 ZCode 一致，不发送数值 |
| 8. 产品化 | 一键启动与 GLM 漂移修复切片已验证，阶段其余内容待办 | 启动器、子进程凭据映射、端口保护、三窗口解析；后端 431、Flutter 45、Web build、Playwright 与真实启动健康检查通过 | 用户确认 GLM 对照；之后进入缓存/可观测性任务 |
| 9. Windows 开源 Beta | 桌面层、托盘恢复、无面板无黑边磁贴与仓库内 EXE 启动切片已验证 | 360×680 三订阅首屏、普通应用覆盖/`Win+D` 保留、414 个后端测试、50 个 Flutter 测试、EXE 互斥接管 | 之后完成开机自启与安装包 |
| 10. 安全配置与多端适配 | 自动验证完成，待用户真机验收/讲解 | Windows Credential Manager、三种布局、手动重置来源、统一配色；后端 426、Flutter 62、Windows/Web/Android 构建及安全 E2E 通过 | 用户做 Key、横竖布局与 Android 真机可见验收 |
| 11. 产品 MCP Server | 可选 | 开发用 Kimi/GLM worker 已配置，但不属于产品代码 | 产品 MCP 契约测试与工具调用轨迹 |

## 当前任务卡

```markdown
日期：2026-07-22
阶段 / 卡号：阶段 3～5 / 真实 API 接入前统一收尾

目标：完成全部离线状态、本地 FastAPI、Flutter HTTP 联调和真实浏览器验收。
范围：Fixture、统一 JSON 契约、FastAPI、Riverpod、HTTP Repository、设置页、前后端测试和 E2E。
非目标：不接任何真实额度 API，不读取或保存任何第三方凭据。
协作方式：实现优先；遇到问题或用户主动提问时再结合当前代码讨论。
验收：
- [x] 正常、加载、空、未配置、部分失败、全部失败、超时、后端不可达和 HTTP 503 均有实现或测试
- [x] FastAPI 8 个测试通过，Python compileall 通过
- [x] Flutter 29 个测试全部通过
- [x] `flutter analyze` 输出 `No issues found!`
- [x] 后端模式 Web release 构建成功
- [x] Playwright/Edge 真实浏览器收到 FastAPI partial 响应并显示三家卡片
- [x] E2E 发现的中文 UTF-8 乱码已修复并添加回归测试
- [x] 截图：`docs/evidence/2026-07-22-stage5-backend-partial.png`
下一张：阶段 6 真实 Codex 接入前安全复核；需用户明确授权。
```

## 2026-07-24 / Stage 9 / Windows EXE 一键启动

### 本次完成

- 新增 `STAGE9_DESKTOP_EXE_LAUNCHER_TASK.md`，把“前端 exe”“进程启动器”和“可分发安装包”明确为
  三个不同交付物。
- `start_quota_watch.ps1` 新增 `-Desktop`：健康检查通过后启动 Windows release
  `quota_watch.exe`，用户从托盘退出后只清理由本次入口创建的后端。
- 新增可审查的 C# 入口壳与 `build_windows_launcher.ps1`；根目录已生成
  `启动 Quota Watch.exe`。入口壳只转交参数，不读取或保存 Key。
- EXE 当前依赖完整仓库、`backend/.venv` 和 release 目录；尚不是可复制到另一台电脑的单文件安装包。

### 验证证据

- 启动器专项 **9 passed**：包含“现场编译 EXE → 启动临时后端 → 假桌面前端退出 → 后端端口释放”，
  并确认两个测试 Key 标记均未出现在输出中。
- 后端完整测试 **405 passed**；Flutter format、`flutter analyze`、**45 tests** 全部通过。
- Windows desktop-widget release 重新构建成功；根目录 EXE 的 `-ValidateOnly` 通过。
- 用户仍需亲自双击根目录 EXE，检查桌面窗、三家内容、刷新和托盘退出；这项功能验收不能由编译或
  离线进程测试替代。

### 补充：无终端窗口启动

- 根据用户实际启动反馈，把 C# 入口壳从 Console subsystem 改为 Windows GUI subsystem；PowerShell
  子进程同时设置 `CreateNoWindow` 与隐藏窗口模式。
- 隐藏终端不等于吞掉故障：启动壳捕获安全状态输出，仅在启动失败时写入
  `%TEMP%\quota-watch-launcher` 并弹窗显示日志路径；不记录 Key 或 Provider 原始响应。
- 专项测试 9 项通过；测试直接读取临时 EXE 的 PE 头并确认 subsystem=2。根目录新版 EXE 也确认
  subsystem=2，离线烟雾链退出码为 0，临时后端端口在结束后释放。

### 补充：托盘菜单与真正的桌面宿主

- 用户实际验收发现：托盘右键无菜单、启动后看不到窗口、没有形成常驻桌面组件。Win32 只读检查确认
  两个窗口进程都存活且 `visible=True`，但父窗口为空并被置于 `HWND_BOTTOM`，实际落到了壁纸之后。
- `tray_manager` 的 Windows 原生代码只派发右键事件，应用原先没有调用
  `popUpContextMenu()`；现已显式弹出菜单并要求其位于前台。
- 桌面模式不再使用 `alwaysOnBottom`，而是通过 MethodChannel + Win32 `SetParent` 挂到 Shell
  `Progman`，在首帧后定位到工作区右上角。最终运行态：父类 `Progman`、可见、未最小化、
  `WS_EX_TOOLWINDOW=True`、layered=True，距顶部和右侧约 16px。
- GUI launcher 增加单实例互斥，并给测试构建使用独立互斥名称。连续启动两次后仍只有一个
  `quota_watch.exe` 和一个 launcher。
- 最终回归：后端 **407 passed**；Flutter format、analyze、**45 tests** 通过；Windows
  desktop-widget release 与 GUI launcher 均重新构建成功。托盘菜单实际绘制和返回桌面观感仍由用户
  做最终验收。

### 二次补充：托盘 HWND 与隐藏/恢复语义

- 用户继续实机验收后发现：收起后无法再次打开，托盘右键仍无菜单。第一次修复只补了 Dart
  右键回调，但忽略了 `tray_manager` 在注册图标和 popup 时都会调用
  `GetAncestor(..., GA_ROOT)`。
- 桌面重挂载后 `GA_ROOT` 已是 `Progman`。现改为在 `SetParent` 前注册托盘，使 Shell
  回调仍绑定 Quota Watch；Windows popup 则改由自有 MethodChannel 使用保存的应用 HWND
  与 `TPM_RETURNCMD` 返回命令。
- 桌面组件是 `WS_CHILD`，不再使用 `SC_MINIMIZE/SC_RESTORE`；收起改为 `hide()`，
  恢复改为 `show()` 后重放当前显示模式。
- 运行态证明：Shell 托盘项可通过应用 HWND 查询；窗口隐藏后经托盘左键路径恢复；
  右键路径真实创建 8 项菜单窗口，5 个可见命令标签完整；重复启动仍只有一个应用和一个 launcher，
  `/health=ok`。
- 二次回归：后端 **409 passed**；Flutter analyze 无问题、**45 tests** 通过；Windows
  desktop-widget release 构建成功。用户仍需亲自做一次右键选择和收起/恢复验收。

### 三次补充：`visible=True` 仍不等于用户能看见

- 用户继续反馈“打不开”。现场检查发现前端进程和窗口都存在，窗口矩形也正确，但恢复后仍是
  `Progman` 的子窗口；普通应用覆盖它，所以操作系统的 visible 状态没有证明用户可见。
- 托盘“显示”与左击现在会把桌面组件切成 `alwaysOnTop` 顶层小窗。用户需要重新放回桌面时，
  再选择“桌面悬浮插件”，使显示模式与真实 Z-order 一致。
- launcher 的单实例分支原先只返回 0。现在第二次双击会找到已有
  `FLUTTER_RUNNER_WIN32_WINDOW`，投递与托盘左击相同的消息，因此不会新增实例，也不会静默无响应。
- 真实桌面控制已点击“最小化到托盘”，确认窗口消失；再次双击根目录 EXE 后，同一窗口 ID
  重新成为可激活顶层窗口。最终应用、launcher、启动脚本各 1 个，后端 `/health=ok`。
- 三次回归：后端 **410 passed**；Flutter analyze 无问题、**45 tests** 通过；Windows release
  与 GUI launcher 均构建成功。

### 四次补充：透明 Flutter surface、同模式 no-op 与 launcher 退出竞态

- 用户继续反馈“桌面悬浮插件点开后完全无效”。真实窗口截图证明先前两条实现路径都不足：
  Shell `Progman` 子窗口会被普通应用覆盖；普通顶层窗口运行期启用
  `WS_EX_TOOLWINDOW` 后，HWND 和矩形仍存在，但 Flutter 画面只剩透明区域。
- 当前 `desktopWidget` 改为不透明的普通顶层窗口，保持 `alwaysOnTop=true`、
  `skipTaskbar=true` 并定位到当前显示器右上角；生产路径明确关闭
  `SetParent`、`WS_EX_TOOLWINDOW` 和运行期 opacity。
- `setDisplayMode` 原先在所选模式等于当前模式时直接返回。窗口已经 `hide()` 后，点当前已勾选的
  “桌面悬浮插件”因此确实没有反应。现改为模式选择始终执行
  `show → apply → focus`，只有托盘勾选状态刷新按“是否真正切换”决定。
- 真实桌面控制先确认窗口出现标题、设置、收起/退出控件和页面像素；随后点击收起，窗口从可见列表
  消失，再通过原生托盘菜单选择当前已勾选的 `desktopWidget`，同一个窗口 ID 重新出现。
- 重建时还复现了 launcher 退出竞态：旧 launcher 短暂持有互斥量但 Flutter 窗口已消失，新双击
  原先会静默返回。现在第二实例会轮询唤醒并有限等待互斥量；人工占用 2 秒后释放的实验中，新
  launcher 成功接管，最终应用和 launcher 各 1 个。
- 四次回归：`flutter analyze` 无问题、**44 tests** 通过；后端 **411 passed**；
  Windows desktop-widget release、根目录 GUI launcher、`-ValidateOnly` 和 launcher 专项
  **15 tests** 均通过。当前实例已由新版根目录 EXE 启动，后端 `/health=ok`。

### 五次补充：普通应用覆盖与 `Win+D` 同时成立

- 用户指出第四版始终置顶，普通应用最大化也无法覆盖。先把 Flutter 主窗口改为无 owner、
  `Topmost=False` 的普通顶层窗口，并插到 Explorer 最高 `WorkerW/Progman` 桌面合成层正上方；
  同一屏幕区域的像素对比确认最大化应用能完整覆盖它。
- 用户随后实机发现 `Win+D` 后小组件仍会消失。只读探针显示窗口依然
  `Visible=True`、`Minimized=False`，说明问题不是最小化。Windows 的 Show Desktop 会把桌面窗口
  整体抬到普通窗口之上，因此拦截 `SC_MINIMIZE` 不足。
- 最终实现保持 Flutter surface 完全不改造，另建两个 0×0 隐藏原生窗口：底部 sentinel 检测
  桌面层是否被抬起，topmost helper 仅在显示桌面期间进入 topmost 带的最底部。小组件临时跟随
  helper；普通应用恢复后立即退出 topmost 带并停回桌面层。
- 桌面图标宿主同时兼容 `SHELLDLL_DefView` 位于 `Progman`（Windows 11 24H2+）和旧版
  `WorkerW` 的层级；没有对 Flutter 主窗口调用 `SetParent`、`WS_CHILD` 或
  `WS_EX_TOOLWINDOW`。
- 用户已确认新版按 `Win+D` 不会消失；返回普通应用后运行态为
  `Topmost=False`、`DesktopRaised=False`、`Owner=0`，窗口仍为 340×520 且后端
  `/health=ok`。
- 五次回归：Windows desktop-widget release 构建成功；`flutter analyze` 无问题、
  Flutter **44 tests**、后端 **412 passed**，桌面源约束专项 **7 passed**。

### S9-4：360×680 紧凑玻璃磁贴

- 按用户要求把小组件改成右侧竖向信息条：三家订阅使用半透明玻璃磁贴，宽屏时仍可排成横向
  三列。360×680 响应式测试确认默认六个窗口全部进入首屏且没有 overflow。
- `QuotaWindowBlock` 删除重复的“已用 / 剩余 / 上限”三列，只保留统一名称、
  `已用 X%`、进度条和重置时间。
- 表现层新增统一标签格式化：`5 小时窗口`/`5h limit` → `5 小时额度`，
  `Weekly limit`/`周窗口`/`7d limit` → `7 天额度`；没有修改后端原始标签或百分比语义。
- `ui-ux-pro-max` 的设计系统用于确定高密度 Bento、深色玻璃、16～18px 圆角、细描边、
  低动效和文字对比原则；进度条响应系统“减少动态效果”。
- 暗/亮 Golden 只使用虚构额度；像素检查发现旧字体子集缺少“周五”的“五”，重新生成后已补齐。
  字体脚本同时改为临时输出、成功后替换，并跳过源字体不支持的注释符号，失败不再删除可用字体。
- 最终验证：`flutter analyze` 无问题，Flutter **48 tests**、后端 **412 passed**，
  Windows Release 构建成功；根目录 EXE 启动后前端、launcher、后端各 1 个且 `/health=ok`。
- 用户反馈初版磁贴不够透明后，暗色/亮色表面不透明度分别调整为约 48%/65%，并去掉底色与
  渐变的重复叠加；模糊提高到 18，文字与进度条保持原对比度。暗/亮 Golden、全部
  **48 tests**、静态分析和 Windows Release 再次通过；重启后前端、launcher、8000 端口
  监听各 1 个且 `/health=ok`。本次没有修改 Windows 原生透明层或额度数据契约。
- 用户进一步要求桌面组件去掉顶部状态栏。首页现在监听 `DisplayMode`：桌面组件模式隐藏标题、
  设置、最小化和关闭按钮，磁贴从顶部 8px 开始；切回置顶小窗时完整应用栏恢复。控制能力保留在
  托盘菜单中。暗/亮 Golden、顶部几何和动态模式切换回归通过，Flutter 增至 **49 tests**，
  静态分析无问题，Windows Release 构建成功；新版根目录 EXE 重启后前端、launcher、8000
  端口监听各 1 个且 `/health=ok`。
- 为解决“一整块应用面板浮在壁纸上”的割裂感，桌面首页现在测量三张卡片的真实矩形，并经
  MethodChannel 交给 Win32 `SetWindowRgn`，把普通不透明 Flutter 窗口裁成三块圆角区域的并集。
  没有恢复 layered window、原生透明背景、Shell `SetParent`、`WS_EX_TOOLWINDOW` 或运行期
  opacity，因此保留已验收的普通应用覆盖、`Win+D` 和稳定渲染路径。
- 桌面模式进一步去掉卡片外阴影和厚重徽标：状态改成彩色圆点 + 文字，百分比改成纯文本，
  仅保留低对比细描边；每张卡片的服务商标题仍可拖动无标题栏窗口。进入设置页、加载/空/错误状态
  或切到置顶小窗时恢复完整窗口区域，返回桌面首页后重新裁形。
- 实机 `GetWindowRgn` 返回复杂区域，中心线只包含 `9–151`、`162–338`、`349–589` 三段；
  两处卡片间隙和底部空白不属于 Quota Watch 命中区。最终 `flutter analyze` 无问题，
  Flutter **50 tests**、后端 **413 passed**、Windows Release 构建通过；根目录 EXE 重启后
  前端、launcher、8000 端口监听各 1 个且 `/health=ok`。
- 用户实机继续发现三张磁贴周围有黑边。Win32 样式探针确认外窗仍有
  `WS_CAPTION`、`WS_THICKFRAME` 和 `WS_EX_WINDOWEDGE`：360×680 外窗的 Flutter 客户区实际
  只有 352×675。单独移除样式后仍未改变客户区，因为 `window_manager` 的
  `TitleBarStyle.hidden` 会在 `WM_NCCALCSIZE` 中保留约 8px 缩放边界。
- 最终桌面模式同时启用 `windowManager.setAsFrameless()`，并在原生侧保存后移除 caption、
  thick frame、系统菜单和扩展边缘；退出桌面模式时恢复原样式与 hidden 标题栏。实机复核外窗/
  客户区均为 360×680、偏移 `0,0`，三段磁贴区域仍在，`Parent=0`、`Owner=0`、
  `Topmost=False`。`flutter analyze` 无问题，Flutter **50 tests**、后端 **414 passed**、
  Windows Release 构建通过；真实启动器的前端、launcher、端口监听各 1 个且 `/health=ok`。
- 用户复验后仍看到黑边，说明“客户区与 STYLE 正确”不能代替像素级验收。使用本地虚构额度的
  Release 实例，在 200% DPI 下截取物理屏幕右边缘：卡片到外窗边界之间的空白为固定
  `#121318`，与 `WindowOptions.backgroundColor` 完全一致；外窗之外才是桌面下层颜色。
  根因是 `SetWindowRgn` 裁掉了 Flutter 内容和点击区域，但 `window_manager` 的 Accent
  原生底色仍按完整矩形合成。
- 修复改为安全的延迟透明：启动时继续使用不透明底色；只有首页完成卡片测量、准备应用三个
  原生区域时，才把顶层 Accent 底色设为透明。进入设置、非数据状态或置顶小窗时，先恢复
  `#121318` 再清除区域；frameless 模式同时显式关闭 DWM shadow。虚构实例同一像素位置已从
  `#121318` 变为桌面下层的实际颜色，圆角卡片与桌面直接相接。`flutter analyze` 无问题，
  Flutter **50 tests**、后端 **414 passed**；最终用户复验仍单独保留。
- 根目录 EXE 恢复真实启动后，只截取不含文字和额度的右侧 32px 边缘进行最终像素检查：
  空白区保持桌面下层的棕红像素，没有固定 `#121318`；前端、launcher、8000 监听各 1 个，
  `/health=ok`。真实额度内容没有被读取、记录或截图。
- 用户继续指出数据卡片本身仍不够透明。检查合成链后确认：卡片色虽然带 alpha，但桌面模式的
  `Scaffold` 和正文环境渐变仍先绘制不透明 `surface`，所以卡片只能透出应用内部背景。
- 桌面组件现在同步把 Flutter 页面画布设为透明，并把暗色/亮色卡片空白处调整为约
  46%/53% alpha；置顶小窗仍保留不透明页面渐变。测试覆盖桌面透明画布与置顶不透明画布，
  启动/加载/设置路径的原生底色安全时序不变。
- 虚构数据 Windows Release 的无文字右边缘中，相邻桌面为 `#4B1C1C` 时，卡片内为
  `#B49C9B`，而上一版同位置接近 `#F0F6F7`；壁纸斜线也能连续透过卡片。最终
  `flutter analyze` 无问题，Flutter **50 tests**、后端 **414 passed**、Windows Release
  构建成功。真实启动器恢复后前端、launcher、backend、8000 监听均为 1，`/health=ok`；
  真实额度内容没有被读取或截图。
- 常驻运行轻量化先用真实根目录启动器建立基线：7 个关联进程、工作集约 370.4 MB、私有内存
  约 264.8 MB；5 秒 CPU 仅约 31.2 ms，因此没有动已验收的 `Win+D` sentinel 轮询，也没有
  修改任何 Windows 服务、注册表、安全或电源设置。
- 普通桌面启动改为“一次性 PowerShell 引导 + GUI launcher 监督”：脚本仍独占凭据映射和
  健康检查职责，用 `pythonw.exe` 启动后端，显式清空 Flutter 子进程的 Provider 凭据变量，
  再用只含 PID/状态的临时文件交接；PowerShell 随即退出。
- 稳态真实复测常驻进程降为 4 个，工作集约 247.9 MB、私有内存约 189.5 MB，分别下降约
  33% 和 28%；无常驻 PowerShell/conhost，重复双击仍保持单实例和单端口监听。
- 强制结束前端时曾发现 .NET 对外部 `Process.ExitCode` 的读取会阻塞在隐藏错误框，导致后端
  暂未回收。改用 Win32 进程句柄等待并把清理放到所有异常路径后，前端、launcher、两级 Python
  与 8000 监听都能在数秒内归零；延迟假桌面端到端测试覆盖了真正的 PID 交接路径。
- 最终验证：启动器专项 **9 passed**、后端 **414 passed**、`flutter analyze` 无问题、
  Flutter **50 tests**、Windows Release 和根目录 GUI launcher 均构建成功。

## 2026-07-25 / Stage 10 / 安全配置、横竖布局与 Android 伴随端

### 本次目标与选择

- 目标是同时交付“用户可安全配置 Key”“横/竖/自动布局”“Codex 可重置次数与到期时间”“统一配色”
  和“Android 可运行”，同时保持 Windows 桌面层、托盘、一键启动和真实 Provider 查询不回退。
- 参考 CC Switch 的 Provider 档案、单一配置来源和原子元数据思路，但不复制其配置数据库或导入
  其他客户端私有文件。Quota Watch 的 Key 只进入本机后端与 Windows Credential Manager。
- 当前官方 Codex app-server Schema 的 credits 仍只有 `hasCredits`、`unlimited`、`balance`。
  因此新增独立 `resetAllowance` 契约，当前值只能是明确标注的 `source=manual` 本机备注，不猜测
  官方值、不调用网页内部接口。

### 纵向实现

- 后端新增 loopback-only 凭据档案 API、WinCred 封装、非敏感 JSON 原子元数据和动态 Key
  resolver；环境变量保持最高优先级。输入使用 `SecretStr`，格式错误和存储异常只返回归一化文案。
- 设置页新增 Kimi / GLM password 输入、Codex 手动重置备注和三种布局选择。Key 不进入
  SharedPreferences、日志或响应；请求结束清空，页面在请求中被关闭也不会访问已销毁 controller。
- 卡片与进度条改为统一蓝灰/安全绿语义色，告警色按亮暗模式保证对比；Provider 品牌色只保留在
  Logo 和小面积标识。暗/亮 Golden 均重新生成并人工查看。
- Windows 竖向仍为 360×680；横向为 1120×340；自动模式保留原 1～3 列断点。托盘恢复和显示
  模式切换会恢复所选尺寸。
- Android 工程使用 `com.quotawatch.app`，声明网络权限并限制远程明文 HTTP；移动端跳过
  Windows 窗口/托盘逻辑。APK 只作为可信后端的客户端，不包含 Python 或 Provider Key。
- 为降低系统负担，只安装 Android command-line SDK/JDK/必要 NDK，不装 Android Studio 或
  模拟器；Gradle daemon 关闭。安装压缩包约 330 MB 已移入回收站，已安装工具保持可用。

### 验证证据

- 后端完整测试 **426 passed**；新增覆盖凭据不回显、非 loopback 403、环境变量优先、动态启用、
  Codex Token 拒绝、手动备注来源、缓存不被污染、删除与畸形输入清洗。
- `flutter analyze` 无问题；Flutter **62 tests** 通过，覆盖三种布局、Android 应用栏、远程 HTTP
  拒绝、Key 清空、请求期间销毁页面、重置次数解析/语义和暗/亮 Golden。
- Edge E2E 使用独立临时端口与内存凭据库，成功走过最新 Web Release → FastAPI
  `all_real`；三家均为无凭据 `unknown`，截图不含个人额度。
- Windows 当前真实运行保持 4 个关联进程、无 PowerShell/cmd/conhost；最终 5 秒采样工作集约
  232 MB、私有内存约 179 MB、CPU 增量为采样精度内 0 ms。Windows Release 完整目录约 32 MB。
- Windows/Web Release、Android Debug APK 与按 ABI Release 均已构建；APK 反查确认
  `com.quotawatch.app`、minSdk 24、`INTERNET` 和 loopback-only 明文例外。arm64 Release 约
  17.9 MB；当前仍是 debug signing config，只作本机验收。
- Android 首次 Release 的 Maven 下载发生一次 TLS handshake 中断，Flutter 自动重试后成功；
  `flutter doctor` 仍提示额外许可证未接受，但 Debug/Release 构建均已通过。完整证据见
  `docs/STAGE10_HANDOFF.md`。

### 尚需用户验收

- 使用自己的 Key 完成一次设置页保存与额度刷新，不能把 Key 或额度数值发给 AI。
- 亲自切换横/竖布局，复核普通应用覆盖、`Win+D`、托盘恢复没有回退。
- Android 真机通过 `adb reverse` 运行并查看三家卡片；APK 构建不等于真机网络和交互已验收。

## 2026-07-23 / 前端优化 / 全窗口直显 + 官方标识 + 周重置日期

### 本次完成

- 首页卡片直接展示**全部额度窗口**（进度条、已用/剩余/上限、重置时间、备注），不再跳转详情页；
  `QuotaCard.onTap` 保留为可选参数，`/detail` 路由与详情页保留给后续历史趋势等扩展内容。
- 图标升级为三家**官方标识**：ChatGPT 绿结（Wikimedia 收录的官方 SVG 渲染）、Kimi 官方图标
  （取自 kimi.com 前端图标库 `a_Kimi` 矢量，重绘为黑底白标应用图标样式）、Z.ai 官方 Z 字标
  （z.ai 官网 CDN SVG 渲染）。512px PNG 存于 `quota_watch/assets/logos/`，来源与授权说明见
  `assets/logos/README.md`（仅本地学习用途，不分发）；`Provider.logoAsset` 提供映射，
  `ProviderLogo` 组件带品牌色圆形 + 首字母回退。
- 重置时间规则：超过 24 小时（周/7 天窗口）写成 `M月d日（周X）重置` 的具体日期，24 小时内
  保留 `X小时Y分后重置` 倒计时；规则集中在 `quota_window_block.dart` 的 `formatResetText`，
  首页与详情页共用同一份，消除两处格式不一致的可能。
- 美化：进度条改为自绘轨道 + 填充微动画并加粗到 10px；窗口标签右侧加与进度条同色的百分比
  徽标；卡片加细描边；顶部总览的彩色圆点换成三家官方小标识；详情页品牌头加入标识。
- 新增共享组件 `provider_logo.dart`、`quota_window_block.dart`；详情页删除重复的格式化代码，
  改为复用共享窗口块；移除首页底部过时的“尚未接入真实额度 API”提示。
- 新增开发工具 `scripts/capture_web_screenshot.mjs`：无依赖 Node 脚本，通过 CDP 驱动无头 Edge
  真实等待后截图（Flutter Web 在虚拟时间预算下截图必白屏，此脚本解决该问题）。

### 关键证据

- `flutter analyze`：`No issues found!`；`flutter test`：**45 个测试全部通过**。
- 新增断言：首页无需点击出现全部窗口标签（`5 小时窗口`×3、`7 天窗口`、`周窗口`×2）、
  `已用/剩余/上限`×6、`）重置`具体日期×3、`后重置`倒计时×3。
- 响应式测试随卡片变高调整测试画布（宽 390/768/1440/1920 断点断言不变），详情页格式化回归
  （百分比/次数不误判为分钟）保持不变并通过。
- Web release 构建成功，真实无头 Edge 截图：
  `docs/evidence/2026-07-23-ui-all-windows-wide.png`（1440 宽三列）、
  `docs/evidence/2026-07-23-ui-all-windows-narrow.png`（420 宽单列）。

### 遇到的工程问题

- 无头 Edge `--screenshot` 配合 `--virtual-time-budget` 对 Flutter Web 只能截到白屏
  （CanvasKit 在虚拟时间下来不及初始化）；改用 CDP 真实等待 9 秒后抓帧成功。
- 卡片变高后，原 800×600 测试画布中 ListView 不再构建折叠线以下的卡片，导致 `findsNWidgets(3)`
  失败；测试统一改为 1200×1600 画布。另修复辅助函数中 `setSurfaceSize` 未 `await` 引发的
  测试框架时序冲突（Guarded function conflict）。
- 已知数据问题（未处理）：`assets/fixtures/*.json` 使用绝对时间，随时间流逝会变成过去时刻，
  截图中三个 5 小时窗口显示“即将重置”即由此造成；后续可把 fixture 读取时改为相对当前时间平移。

### 追加（同日）：删除 ⓘ 注释行 + Codex 字段边界确认

- 按用户决定移除窗口块中带 ⓘ 图标的备注行（“主窗口，到期前自动恢复”“高峰时段扣 3×”等）；
  `note` 字段保留在数据契约中，后端照发，前端不再展示。`flutter analyze` 无问题、45 测试通过、
  Web 构建成功，证据 `docs/evidence/2026-07-23-ui-no-notes-wide.png`。
- Codex 字段边界（只读查证，未做真实调用）：
  - 当前 app-server `account/rateLimits/read` 快照只含窗口字段（`usedPercent`/`windowDurationMins`/
    `resetsAt`/`planType`），**不含订阅到期**；到期日在本地 JWT 的
    `chatgpt_subscription_active_until` 声明（`docs/API_RESEARCH.md` 已记录），接入需用户授权的安全切片。
  - “可重置次数/恢复额度”只出现在 OpenAI 内部端点 `wham/rate-limit-reset-credits` 的调研记录中；
    项目纪律禁止依赖 wham 内部端点（`backend/README.md`），app-server 是否返回 credits 未确认，
    需要授权后的脱敏结构实验才能回答。

### 追加（同日 17:37，经用户授权）：Codex app-server 脱敏结构实验

- 方式：`backend/tools/inspect_codex_structure.py`（保留入库，设计上只能输出字段路径 + 类型，
  不可能打印任何值）；官方 `codex app-server` 自管凭据，不读 auth.json、原始响应不落盘、不进 Git。
- 结果（仅字段名/类型，无数值）：
  - **credits 存在**：`rateLimits.credits` 与 `rateLimitsByLimitId.codex.credits` 均含
    `balance`(str)、`hasCredits`(bool)、`unlimited`(bool)——即“恢复额度”无需碰 wham 内部端点，
    官方快照直接提供，可合规接入。
  - **订阅到期不存在**：全快照无 `expir/subscri/until/renew` 任何字段；到期仍只有 JWT 的
    `chatgpt_subscription_active_until` 一条路径，接入需另行授权的安全切片。
  - 附带发现：存在第二个限制 bucket（`rateLimitsByLimitId` 下另一 limitId，其 credits 为 null，
    自带 primary 窗口与 planType）；本账号当前 `secondary` 窗口为 null，现有适配器按 None 跳过、
    不报错。credits 的确切语义（次数还是额度量）未取值确认，留待接入切片时只在本机界面呈现。

### 追加（同日，用户授权后实施）：Codex credits 端到端接入

- 任务卡：`docs/STAGE8_CODEX_CREDITS_TASK.md`。纵切片路径：后端 `QuotaCredits` 契约模型 →
  `parse_codex_rate_limits` 白名单解析（credits 缺失/为 null → None；类型不符、空串或 >32 字符
  → ContractError）→ 聚合器失败回退保留 credits → normal 场景与 fixture 演示值 → Flutter
  `QuotaCredits.fromJsonOrNull` → Codex 卡片窗口列表下方"恢复额度"行（无限/余量/已用完三态）。
- 证据：后端 440 个 pytest 通过；`flutter analyze` 无问题；Flutter 49 个测试通过；
  Web 构建成功；截图 `docs/evidence/2026-07-23-ui-codex-credits.png`。
- 工程事件：验证真实 `codex_real` 路由时，连续重试触发 OpenAI 侧 RateLimitError
  （app-server 响应耗时 21.5s 才返回限流错误）——这是对"不要密集重试提供方接口"的现成教训；
  已将 `CodexAppServerClient` 默认超时 8s → 15s 覆盖冷启动波动，真实路由闭环留待限流恢复后
  由用户一键启动查看。期间发现早前截图步骤残留多个 http.server/uvicorn 进程占用测试端口，
  已按 PID 清理；后续脚本一律按端口找 PID 回收。

### 追加（2026-07-24 00:06）：修复"本地后端请求超时"误报

- 用户实测真实额度场景报"本地后端请求超时"。排查证据：后端在 127.0.0.1:8000 健康运行、
  `/health` 与 `scenario=normal` 秒回；前端默认地址与启动器端口一致。根因是
  `BackendQuotaRepository` 默认 5 秒超时 < Codex app-server 冷启动 8–15 秒（限流时 ~21.5s），
  真实场景下整页必然误报超时。
- 修复：默认超时 5s → 30s（仍长过后端单家最坏 15s + 余量；测试自行注入超时值不受影响）。
  `flutter analyze` 无问题、49 个测试通过。启动器走 `flutter run` 源码路径，下次启动即生效。
- 降级边界：若提供方限流未消，页面应加载成功且 Codex 卡片单独显示"查询超时"
  （后端 15s 适配器超时 → 单家错误卡片），而不是整页失败——这是设计内行为。

## 2026-07-23 / 阶段 3～5 / 字体子集与 E2E 收尾

### 本次完成

- 新增 `scripts/build_font_subset.ps1`：扫描 `quota_watch/lib/**`、`quota_watch/test/**`、
  `assets/fixtures/*.json`、`backend/app/*.py` 的唯一码点，通过 stdin 传给 Flutter 自带的
  `font-subset.exe`（契约 `font-subset.exe <out.ttf> <in.ttf>`，码点空格分隔、换行结束），
  生成 `quota_watch/assets/fonts/NotoSansSC-QuotaWatchSubset.ttf`（306 528 字节，731 个码点）。
  完整 17 MB 官方源字体不入库。
- `pubspec.yaml` 注册 `NotoSansSCSubset` 字体 family；`app_theme.dart` 的 `ThemeData` 设置
  `fontFamily: 'NotoSansSCSubset'`，保证 Web 发布包离线渲染中文。
- `assets/fonts/README.md` 记录上游 URL、OFL 许可证、子集用途与重新生成时机/命令。
- `e2e_web_check.py` 增加 `FontManifest.json` 检查：断言 `NotoSansSCSubset` family 及对应
  asset 进入发布包；并将 console 错误过滤改为忽略 `net::ERR_*` 资源瞬时重试，真正的 JS 异常
  仍由 `pageerror` 硬失败。

### 关键证据

- E2E 启动竞态已改为等待真实 `/api/v1/quotas?scenario=partial` 响应和 Flutter 语义节点。
- Web 发布包已内置 OFL 中文字体子集，最终截图无缺字方框。
- 人工查看 `docs/evidence/2026-07-22-stage5-backend-partial.png`：Codex 卡（充足 / 已用 40% /
  2h17m 后重置）、Kimi 卡（告警 / 已用 36.0M / 40.0M）、GLM 卡（查询失败 / 模拟故障：GLM
  服务暂时不可用）中文全部可读。
- `flutter analyze`：`No issues found!`；`flutter test`：37 个测试通过；FastAPI 8 个 pytest 通过；
  后端模式 Web release 构建成功；E2E 连续两次通过并验证 FontManifest。

### 遇到的工程问题

- 进入工作区时 `quota_card.dart` 存在预先存在的编译错误（未完成的 `Semantics` 包装引用了未定义
  方法且括号错乱，HEAD 版本无此问题），阻塞 `flutter test/build`。经用户授权做最小修复：
  对齐 `Card(` 的括号使解析器能找到已存在的 `quotaStatusText`；并把“已用/重置” Row 的两个 Text
  包进 `Flexible` 以消除 3.6px 溢出。
- Agent B 与本任务在**同一 worktree** 并行修改了前端（`centered_content.dart`、响应式测试、
  `quota_card.dart` 的 `container: true` 等），属于规则要求独立 worktree 的情况。字体子集已在
  合并后的源码上重新生成（包含 Agent B 新增中文「当前为内置演示数据，无需填写后端地址」）。
- 仍**未接入任何真实 Provider API**，无凭据、无真实服务响应。阶段 6 必须等待用户明确授权。

## 2026-07-23 / 阶段 3～5 / Agent A+B 集成最终验证

### 本次完成（集成者角色）

- 开始门：Agent A、Agent B 完成报告均 `complete`、`safe_to_integrate: true`，无占位符；HEAD `fe6a3ba`，端口 7357/8000 无占用。
- 固定集成顺序：在 Agent B 最终 presentation/test 源码上重新运行 `scripts/build_font_subset.ps1`，输出固定为 `NotoSansSC-QuotaWatchSubset.ttf`（731 码点、306 528 字节）；17 MB 完整源字体仍只在临时目录，未入库。
- 最终自动验证（真实退出码）：
  - `dart format lib\presentation test`：`Formatted 13 files (0 changed)`。
  - `flutter pub get` / `flutter analyze`（`No issues found!`）/ `flutter test`（37/37 通过）均退出 0。
  - `flutter build web`（backend/partial）：`√ Built build\web`。
  - FastAPI `pytest`：`8 passed`。
  - `run_e2e.py` 连续两次针对同一最终 build 通过，并验证 FontManifest 含 `NotoSansSCSubset`。
  - `git diff --check`：无空白错误；7357/8000 无遗留 LISTENING；`backend/.venv/` 仍被忽略。
- 人工查看 `docs/evidence/2026-07-22-stage5-backend-partial.png`：标题「本地 FastAPI · 部分失败」、GLM 卡「查询失败」「模拟故障：GLM 服务暂时不可用」、Codex「充足」、Kimi「告警」中文全部可读，**无缺字方框**；三列居中限宽（Agent B 的 `CenteredContent` 生效）。390/768/1920 由 `responsive_layout_test.dart` 覆盖（全部通过）。
- 范围与安全：仍只有 Mock/Fixture/本地 FastAPI 假接口；无真实 Provider 适配器或凭据；数据契约、路由语义和状态规则未被 Agent B 改动；失败路径测试（单家错误/空/部分/全部失败/损坏 JSON/超时/503）均有证据。

### 结论

阶段 3～5「真实 API 接入前」版本**已完成**。真实 Provider API 仍为零；阶段 6 须用户明确授权后才开始，开始前须重新核对三家官方接口与凭据安全设计。详见 `docs/AGENT_AB_INTEGRATION_REPORT.md`。

## 2026-07-23 / 阶段 6 / 卡 1 / 官方支持与本地架构复核（仅设计 + 离线实现）

### 本次完成（仍不接入真实 API）

- 按 `POST_AGENT_AB_INTEGRATION_TASKS.md` 第 7 节，用 2026-07-23 当时官方资料重新复核三家入口，
  并在 `docs/API_RESEARCH.md` 新增“第零节”：来源分级（L1 官方文档 / L2 官方开源 / L3 内部端点 /
  L4 社区逆向）、三家支持矩阵、对旧结论的修正与官方引用。
  - **关键合规修正**：GLM Coding Plan 官方 FAQ 明确“仅限官方指定工具”，非指定工具不享用套餐额度；
    旧调研把 `monitor/usage` 端点当作稳定接入依据属于 L4，默认禁用。Kimi 的 `KimiCLI/1.6` UA 伪装
    方案不再作为实现依据。Codex 没有公开稳定额度 API，`wham/usage` 是 L3 内部端点。
- 新增 `docs/STAGE6_PROVIDER_DESIGN.md`：产品目标、支持矩阵、统一契约、`ProviderAdapter` 接口、
  错误归一化（401/403/429/超时/契约变化/断网）、缓存与“数据可能已过期”过期判断、离线测试方案、
  Definition of Done 与下一张任务卡。
- 实现阶段 6 / 卡 2 的**离线**骨架（不发起真实请求、不接触凭据）：
  - `backend/app/providers/base.py`：`ProviderAdapter` 协议 + `AuthError/RateLimitError/
    ContractError/ProviderTimeoutError/ProviderConnectionError` 归一化异常与用户文案。
  - `backend/app/providers/fake.py`：`FakeProviderAdapter`，可注入结果或受控异常。
  - `backend/app/providers/aggregator.py`：`QuotaAggregator`，并行查询、单家失败不拖垮其他家、
    最后成功缓存、失败有旧值返回旧值 + 过期提示、过期阈值判断。
  - `backend/tests/test_aggregator.py`：14 个离线测试覆盖成功、单家失败隔离、各错误归一化、
    缓存回退、过期判断。

### 关键证据

- `backend/.venv/Scripts/python.exe -m pytest`：`22 passed`（8 既有 + 14 新增），全部离线。
- 新增 provider 代码扫描：无 `httpx/requests/urllib/bearer/auth.json/sk-kimi/...`，纯离线设计。
- 新增测试无任何真实凭据模式。

### 补充：Kimi 契约 L2 源码研究与离线解析器（2026-07-23，仍未接入真实 API）

- 只读研究官方开源 `MoonshotAI/kimi-cli`（Python）与 `MoonshotAI/kimi-code`（TS）源码，
  在 `docs/API_RESEARCH.md §三` 用 L2 证据修正多处旧（L4 社区逆向）错误结论：
  - 端点固定 `GET /coding/v1/usages`（复数，无 `/usage` fallback）。
  - **不需要 `User-Agent: KimiCLI/1.6` 伪装**（官方测试断言不发送 UA）；旧结论已废弃。
  - 顶层是 `{usage?, limits[]?, boosterWallet?}` 对象，**不是**旧猜的 `{data:[...]}` 数组。
  - `used` 主字段，缺失走 `limit - remaining`；`resetAt` 是 ISO（可达纳秒）；`reset_in/ttl/window` 是秒数。
- 新增 `backend/app/providers/kimi_parser.py`：按官方宽松解析规则归一化到 `QuotaWindow`，
  覆盖 usage 行、limits 行、remaining 回退、ISO/秒数重置、`used>limit` 钳制、字段缺失丢弃、
  忽略 bug 字段 `totalQuota` 与 `boosterWallet`（本期不解析）。
- 新增 `backend/tests/test_kimi_parser.py`：18 个离线契约测试全部通过。
- 在 `docs/STAGE6_PROVIDER_DESIGN.md` 新增 §8（Kimi 首家确认 + 字段映射 + 凭据边界）与 §9（卡 3 任务卡）。
- **真实请求路径仍为零**：kimi_parser 只解析，无网络/凭据/UA 伪装；真实适配器需卡 3 用户授权。
- 全后端 `pytest`：`40 passed`（8 API + 14 aggregator + 18 kimi_parser），全部离线。

### 补充：Kimi 离线解析→聚合→缓存全链路打通（2026-07-23）

- 新增 `backend/app/providers/kimi_fixture.py`：`KimiFixtureAdapter`，把脱敏 Kimi JSON 经
  `parse_kimi_usage` 解析后包装成 `ProviderQuota`，可被 `QuotaAggregator` 消费（仍离线、无凭据）。
- 新增 `backend/tests/test_kimi_pipeline.py`：4 个集成测试，证明 Kimi 解析窗口能进入聚合器，
  与 Codex/GLM 并行；Kimi 失败时回退到缓存旧窗口 + “数据可能已过期”提示。
- 新增 `backend/fixtures/kimi/usage_typical.json` 与 `usage_remaining_fallback.json`：
  基于官方源码衍生的脱敏样例，解析器测试改为从文件读取（契约更具体）。
- 全后端 `pytest`：`46 passed`（8 API + 14 aggregator + 20 kimi_parser[含 2 文件 Fixture] + 4 pipeline），
  全部离线；无真实 Provider 代码、凭据或 UA 伪装。

### 补充：GLM 官方插件 L2 契约研究与离线解析器（2026-07-23，真实调用仍默认禁用）

- 只读研究官方开源 `zai-org/zai-coding-plugins`（`query-usage.mjs`），在 `docs/API_RESEARCH.md §四`
  补充 L2 确认：双 host（`open.bigmodel.cn` / `api.z.ai`）按 `ANTHROPIC_BASE_URL` 切换；
  **`usage`=上限、`currentValue`=已用**（字段名具误导性）；`unit` 3=5h/6=周/0=月；`nextResetTime`
  用 `>1e12` 启发式区分毫秒/秒/ISO；`percentage` 不钳制可 >100；5h 默认上限 40,000,000。
- 明确合规边界：GLM 官方 FAQ 限定套餐仅用于官方指定工具，故本项目 GLM 真实查询**默认禁用**，
  解析器仅作离线契约文档/回归资产（`backend/app/providers/glm_parser.py`，16 个测试）。
- 在 `docs/STAGE6_PROVIDER_DESIGN.md` 新增 §10「三家 Parser 与合规总表」：Codex 无公开 API（不实现），
  Kimi 合规可实验（候选），GLM 默认禁用。
- 全后端 `pytest`：`62 passed`（8 API + 14 aggregator + 20 kimi_parser + 4 pipeline + 16 glm_parser），
  全部离线；**真实 Provider API 仍为零**。

### 补充：Flutter 端过期判断准备（2026-07-23）

- 在 `quota_watch/lib/data/models/quota_models.dart` 的 `ProviderQuota` 增加 `isStale` 派生 getter
  与 `staleThreshold`（默认 6h，与后端 `QuotaAggregator.is_stale` 口径一致），为阶段 6 失败回退旧值
  时显示“数据可能已过期”做前端准备。`now`/`threshold` 可注入以便测试。
- 新增 4 个模型测试（`quota_models_test.dart`）：fetchedAt 为 null 视为过期、未超阈值不过期、
  超 6h 过期、可注入更短阈值。
- 未改动任何 widget 或可见中文文字，因此**无需重新生成字体子集**。
- `flutter analyze`：`No issues found!`；`flutter test`：**41 passed**（原 37 + 4 新增）。

### 补充：契约漂移回归测试（阶段 7 DoD 提前落实，2026-07-23）

- 新增 `backend/tests/test_parser_contract_drift.py`：13 个测试，模拟 Kimi/GLM 响应字段缺失、
  类型变化、结构剧变、未知新字段、脏数据（负值、坏时间串）等漂移。
  - 结构性破坏（非对象、关键容器缺失）-> 抛 `ContractError`（可诊断地失败）。
  - 字段级漂移（缺 used、reset 时间格式变、多余字段）-> 优雅降级，不崩溃。
  - 端到端：Kimi 响应结构性破坏时，`ContractError` 经 `QuotaAggregator` 归一为 `status=error`，
    单家漂移不拖垮其他家（满足阶段 7 “写一条契约漂移回归测试”的 DoD）。
- 全后端 `pytest`：**78 passed**（8 API + 14 aggregator + 20 kimi_parser + 4 kimi_pipeline +
  16 glm_parser + 3 glm_pipeline + 13 contract_drift），全部离线；**真实 Provider API 仍为零**。

### 补充：Parser 边界覆盖、Codex 设计、实验性聚合路由（2026-07-23）

- **Kimi parser 边界**：新增 `test_kimi_parser_boundary.py`（17 测试）：usage+limits 同时缺失、
  percentage 字符串/数字被忽略、limit=0、极大值、reset_in≤0、仅日期 ISO、DAY/未知 timeUnit 标签、
  无 detail 直接读 item 等。
- **GLM parser 边界**：新增 `test_glm_parser_boundary.py`（13 测试）：percentage 字符串超额提示、
  数值字段为数字字符串、`data.limits` 优先于顶层 `limits`、unit/type 缺失组合、nextResetTime 负数/超大毫秒/字符串。
- **Codex 设计**：新增 `docs/STAGE6_CODEX_DESIGN.md`：因 Codex 无公开稳定 API，唯一合规路径为
  “CLI `/status`/网页面板人工查看 → 手动录入 → 本地缓存（标注手动录入 + 过期提示）”，
  不调用 `wham/usage` 内部端点、不读 `auth.json`。
- **实验性聚合路由**：`backend/app/main.py` 新增 `/api/v1/experimental/aggregate`，**默认禁用**
  （`QUOTA_WATCH_EXPERIMENTAL_AGGREGATE=1` 才挂载），用离线 Fake/Fixture 演示 QuotaAggregator；
  `test_experimental_aggregate_route.py`（4 测试）验证默认 404、启用后返回三家聚合、不破坏既有路由。
- 全后端 `pytest`：**112 passed**（78 + 17 kimi_boundary + 13 glm_boundary + 4 实验路由），
  全部离线；`flutter analyze` 无问题；`git diff --check` 干净。**真实 Provider API 仍为零**。

### 补充：实验路由 HTTP 层过期回退验证 + 代码清理（2026-07-23）

- 新增 `test_experimental_aggregate_staleness.py`（3 测试）：在 HTTP 层验证实验路由的缓存/过期回退——
  首次调用三家 ok 写缓存；把 Kimi 适配器换成会抛 `RateLimitError` 的 fixture 后再次调用，
  Kimi 返回旧窗口 + status=error + “查询过于频繁；数据可能已过期”，而 Codex/GLM 仍 ok（单家失败隔离）。
- 代码清理：移除 `kimi_fixture.py`/`glm_fixture.py` 中未使用的 `ProviderAdapter` 导入
  （fixture 通过结构化子类型满足协议，无需显式类型注解）。
- `compileall backend/app backend/tests` 通过；全后端 `pytest`：**115 passed**；**真实 Provider API 仍为零**。

### 补充：Codex 手动录入缓存实现（2026-07-23）

- 新增 `backend/app/providers/codex_manual.py`：`CodexManualEntryCache`，按 `STAGE6_CODEX_DESIGN.md`
  实现“人工查看 → 手动录入剩余百分比 → 本地缓存”：录入换算 used/limit（unit='percent'）、
  标注“手动录入”、未录入返回 unknown 引导文案、清空、reset 时间、与 `QuotaAggregator.is_stale` 协同。
- 新增 `backend/tests/test_codex_manual.py`：10 个离线测试（换算、容错、引导、过期协同）。
- 更新 `backend/README.md`：记录 providers 包各模块、实验性聚合路由（默认禁用）与安全边界。
- 更新 `STAGE6_CODEX_DESIGN.md` DoD：手动录入缓存模块已实现。
- 全后端 `pytest`：**125 passed**（115 + 10 codex_manual）；`compileall` 通过；`git diff --check` 干净。
  **真实 Provider API 仍为零**（Codex 走手动录入，不调用任何内部端点）。

### 补充：Codex 手动录入接入聚合（三家统一流水线，2026-07-23）

- 新增 `backend/app/providers/codex_adapter.py`：`CodexManualAdapter` 把 `CodexManualEntryCache`
  适配为 `ProviderAdapter`，使 Codex 手动录入值像其他家一样流经 `QuotaAggregator`。
- 新增 `backend/tests/test_codex_aggregate.py`：4 个集成测试，证明三家（Codex 手动 + Kimi fixture +
  GLM fixture）并行聚合；Codex 未录入显示 unknown 但不拖垮其他家；手动录入值在多次聚合间稳定。
- 至此三家统一离线流水线打通：Codex（手动）+ Kimi（L2 fixture）+ GLM（L2 fixture，默认禁用真实调用）。
- 更新 `STAGE6_CODEX_DESIGN.md` DoD：手动录入缓存与聚合接入均完成。
- 全后端 `pytest`：**129 passed**；`compileall` 通过。**真实 Provider API 仍为零**。

### 补充：开源前安全/凭据审计（阶段 9 准备，2026-07-23）

- 全仓库 secret 扫描（`.py/.dart/.json/.yaml/.md/.ps1/.txt`，排除 `.venv/build/.dart_tool/.git`）：
  无 `sk-*/AKIA*/Bearer` 等凭据模式命中。
- `.gitignore` 覆盖审计：`.env*`、`**/auth.json`、`*.key`、`*.pem`、`*.p12`、`secrets*`、
  `.venv/`、`build/`、`.dart_tool/` 均已覆盖。
- 敏感路径追踪检查：`git ls-files` 无 `auth.json/.env/*.key/*.pem/token/credential`；
  worktree 中无敏感文件；17 MB 完整源字体不在仓库。
- 模拟暂存内容扫描（tracked + untracked-non-ignored）：无凭据命中。
- 结论：当前满足 `AGENTS.md` 安全不变量，达到开源前凭据安全基线（阶段 9 的前置条件之一）。

### 补充：并发竞态测试 + 官方衍生 Fixture 回归（2026-07-23）

- **并发竞态**：新增 `test_aggregator_concurrency.py`（7 测试），覆盖阶段 5/8 关注的
  “并发刷新、重复请求和竞态”风险——50 路并发 `fetch_all` 不损坏缓存/不抛错、每次返回完整三家；
  混合成功/失败并发；重复请求一致无漂移；成功→失败回退→恢复刷新序列；共享有状态 adapter 并发隔离；
  fetch_all 进行中清空缓存不崩溃；多家同时失败文案互不串扰。
- **官方衍生 Fixture 回归**：新增 4 个脱敏 fixture（`fixtures/kimi/usage_only_5h_limit.json`、
  `usage_nanosecond_reset.json`；`fixtures/glm/usage_typical.json`、`usage_with_details.json`），
  + `test_parser_fixture_files.py`（12 测试，含参数化“所有 fixture 必须可解析”防漏写）。
- 全后端 `pytest`：**148 passed**（129 + 7 并发 + 12 fixture 文件）；`flutter analyze` 无问题；
  `git diff --check` 干净；fixture secret 扫描为空。**真实 Provider API 仍为零**。

### 补充：实验性路由改为真实阶段 6 流水线（2026-07-23）

- `/api/v1/experimental/aggregate` 的演示聚合器从 Fake Codex 改为 `CodexManualAdapter`
  （手动录入缓存），使其端到端演示真实阶段 6 形态：Codex（手动录入，带“手动录入”标注）+
  Kimi（L2 fixture）+ GLM（L2 fixture，默认禁用真实调用）。
- 同步更新实验路由测试（断言 Codex 手动标注），过期回退 HTTP 测试仍通过。
- 实时验证三家 status=ok，Codex note 显示“手动录入（Codex 无公开 API）”。
- 全后端 `pytest`：**148 passed**。**真实 Provider API 仍为零**。

### 补充：Fixture 契约形状测试（2026-07-23）

- 在 `test_parser_fixture_files.py` 增加 3 个契约形状测试，把 fixture 提升为权威契约样例：
  - Kimi fixture 顶层必须是对象且含 usage 或 limits；
  - GLM fixture 必须有 data.limits 或顶层 limits，每条 limit 有 type 与 usage；
  - GLM `usage`（上限）必须 >= `currentValue`（已用），固化“字段名误导”语义。
- 后续新增 fixture 若违反官方契约形状，这些测试会先失败。
- 全后端 `pytest`：**151 passed**。**真实 Provider API 仍为零**。

### 补充：抽取共享解析模块消除重复（2026-07-23）

- Kimi 与 GLM 解析器原各自重复实现数字容忍转换与 ISO8601（含纳秒截断）解析，有细微漂移风险。
- 新增 `backend/app/providers/_parsing.py`：`to_number`/`to_int`/`parse_iso_to_utc`/`truncate_subseconds`
  作为单一来源；重构 `kimi_parser.py` 与 `glm_parser.py` 复用（`_to_int=_parsing.to_int`、
  `_to_number=_parsing.to_number`、ISO 委托 `parse_iso_to_utc`）。
- 重构后 94 个既有 parser 测试全部通过（行为零回归）；新增 `test_shared_parsing.py`（35 测试），
  含参数化数字容忍、纳秒截断、时区标记、以及“Kimi 与 GLM 对同一 ISO 解析结果一致”的跨解析器一致性。
- 全后端 `pytest`：**186 passed**；`compileall` 通过；`flutter analyze` 无问题；`git diff --check` 干净。
  **真实 Provider API 仍为零**。

### 补充：_parsing 健壮性属性测试 + 代码清理（2026-07-23）

- 新增 `test_parsing_robustness.py`（106 测试）：参数化喂入 27 种极端/畸形输入
  （None/NaN/Inf/全角数字/bytes/complex/超大 int/溢出 float/`0x10` 等），锁定 _parsing 的
  “永不抛异常”契约——任意输入返回 None 或合法值，绝不抛异常。
- 代码清理：移除 `kimi_parser.py` 中 `_seconds_timedelta` 的惰性 import，改为顶层 `timedelta`。
- 更新 `backend/README.md` provider 表：补 `_parsing.py` 与 `codex_manual.py`/`codex_adapter.py`。
- 全后端 `pytest`：**292 passed**；`compileall` 通过；`flutter analyze` 无问题；`git diff --check` 干净。
  **真实 Provider API 仍为零**。

### 补充：聚合层 last_error 诊断（阶段 6 §3 CachedQuota，2026-07-23）

- `QuotaAggregator` 新增 `_last_errors`（每家最近一次失败的异常类型名+归一化文案+时间）与只读
  `last_error(provider)`，落地 STAGE6_PROVIDER_DESIGN §3 的 CachedQuota 诊断字段；不含原始敏感响应、
  不进入前端 JSON（6 个测试：无失败返回 None、记录失败、回退旧值时仍记录、更新为最近失败、各家隔离、
  成功后不清除诊断）。
- 全后端 `pytest`：**298 passed**；**真实 Provider API 仍为零**。

### 补充：聚合层 HTTP 端到端失败传播测试（阶段 6/8，2026-07-23）

- 新增 `test_aggregator_http_failure_propagation.py`（9 测试），经 `/api/v1/experimental/aggregate`
  端到端验证失败传播：401/429/超时/契约变化经适配器 -> 聚合层 -> HTTP JSON 归一；
  失败有旧值时 JSON 返回旧值 + 过期提示；`last_error` 诊断可读但不进 JSON；多家同时失败互不串扰；
  全部失败仍返回 HTTP 200（聚合层不升级为 5xx）；Codex 手动录入永不传播 fetch 失败（只 unknown/ok）。
- 全后端 `pytest`：**307 passed**；`flutter analyze` 无问题；`flutter test` 41/41；`compileall` 通过；
  `git diff --check` 干净。**真实 Provider API 仍为零**。

### 补充：ProviderError 异常层级直接单元测试（2026-07-23）

- 新增 `test_provider_errors.py`（12 测试）：直接锁定归一化异常的 `user_message` 契约——基类默认
  “查询失败”、五个子类各自覆盖文案、消息两两不同（防误改重复）、可抛可捕获（基类与子类）、
  `user_message` 是类属性（所有实例共享）。此前仅经聚合层间接测试，现直接固化。
- 全后端 `pytest`：**319 passed**；`flutter analyze` 无问题；`git diff --check` 干净。
  **真实 Provider API 仍为零**。

### 补充：聚合层 provider 返回顺序契约测试（2026-07-23）

- 新增 `test_aggregator_order.py`（6 测试）：锁定 `fetch_all` 返回三家稳定顺序（codex, kimi, glm），
  前端依赖该顺序定位卡片——标准三家顺序、乱序注册仍归一、子集注册保相对顺序、单家、多次调用稳定、
  混合成功/失败仍保序。
- 全后端 `pytest`：**325 passed**；`flutter analyze` 无问题；`git diff --check` 干净。
  **真实 Provider API 仍为零**。

### 补充：修复 _parsing 非零时区偏移丢失 bug（2026-07-23）

- **发现并修复一个真实正确性 bug**：`_truncate_subseconds` 原只用固定列表（`Z`/`+00:00`/`+0000`）
  剥离时区标记，对非零偏移（如 `+08:00`/`+05:30`）会把偏移当小数部分截掉，导致本地时间被当作 UTC，
  对中国区 GLM/Kimi 重置时间会造成数小时误差。改为按 `+`/`-` 通用匹配保留任意偏移；移除已无用的
  `_ISO_TZ_MARKERS` 常量。
- 新增 `test_parsing_offsets.py`（11 测试）：保留 `+08:00`/`-05:30`/`+0800` 偏移；`+08:00` 的
  05:24 正确转 UTC 为前一天 21:24；零偏移/Zulu 不变；跨解析器（Kimi/GLM）偏移一致性。
- 全后端 `pytest`：**336 passed**；`compileall` 通过；`flutter analyze` 无问题；`git diff --check` 干净。
  **真实 Provider API 仍为零**。

### 补充：解析器内部辅助函数直接单元测试（2026-07-23）

- 新增 `test_parser_helpers_direct.py`（21 测试）：此前仅经 parse_* 主入口间接测试的 helper 直接锁定——
  Kimi `_window_label`（DAY/未知单位/分钟非整除/大小写不敏感/0 duration）、`_label`（name/title/scope
  回退、item 优先于 data、“Limit #N”兜底）；GLM `_extract_limits`（data.limits 优先、顶层兜底、
  data 非 dict/limits 非 list 的漂移容忍、二者皆缺返回空）。
- 全后端 `pytest`：**357 passed**；`flutter analyze` 无问题；`git diff --check` 干净。
  **真实 Provider API 仍为零**。

### 补充：聚合层 last_error 生命周期管理（2026-07-23）

- `QuotaAggregator` 新增 `clear_last_error(provider)`：供运维/测试在确认问题解决后重置诊断，
  避免长运行进程残留误导性旧失败记录；返回是否确实清除（4 个测试：清除、无记录返回 False、
  各家隔离、清除后再次失败能重新记录）。
- 全后端 `pytest`：**361 passed**；`compileall` 通过；`flutter analyze` 无问题；`git diff --check` 干净。
  **真实 Provider API 仍为零**。



















### 补充：Codex 官方本地 app-server 真实额度纵切片（2026-07-23）

- 用户明确授权“先接入 Codex”，任务边界记录在 `STAGE6_CODEX_REAL_TASK.md`；Kimi/GLM 不在本卡范围。
- 用官方 app-server 文档和本机 `codex-cli 0.130.0-alpha.5` 生成的稳定 JSON Schema 复核：JSONL
  握手为 `initialize → initialized → account/rateLimits/read`，无需把登录凭据交给 Quota Watch。
- 新增 `codex_app_server.py`：白名单解析主/次额度窗口、套餐类型和 UTC 重置时间；多 bucket 优先
  `limitId=codex`；错误固定归一，stderr/原始 JSON 不进入日志或响应。
- 新增默认关闭的 `QUOTA_WATCH_CODEX_REAL=1`、`codex_real` HTTP/Flutter 场景；开关关闭返回结构化
  503 且不启动进程。Kimi/GLM 在该场景明确显示“本卡尚未接入”。
- 离线假 app-server 覆盖成功、未登录、超时、损坏 JSON、命令安全和进程清理；Windows 实现改为
  同步队列读取，消除了事件循环关闭警告。
- 本机真实行为检查：HTTP 200、Codex 返回 **1 个有效窗口**；只记录结构，不打印实际百分比、套餐、
  账户或原始响应；响应字段扫描没有邮箱、token、账号 ID、Authorization、Cookie、auth。
- 最终自动验证：`compileall` 通过；全后端 `pytest` **376 passed**；`flutter analyze` 无问题；
  `flutter test` **42 passed**。
- 尚缺学习者证据：按 README 启动并亲自查看自己的额度，然后说明“改了什么、为什么不需要 Key、
  怎样证明显示的是实际读取结果”。

### 补充：Kimi Code 实际额度纵切片（2026-07-23）

- 用户明确授权“接入实际额度”，任务边界记录在 `STAGE6_KIMI_REAL_TASK.md`；本卡不修改 Codex
  查询方式，也不接入 GLM。
- 用 Kimi Code 官方文档与 `MoonshotAI/kimi-code` 官方源码复核：会员可创建供第三方平台使用的
  API Key；额度请求为 `GET https://api.kimi.com/coding/v1/usages`，不发送自定义 User-Agent。
- 新增 `kimi_adapter.py`：生产 URL 固定、禁止重定向、8 秒超时、1 MiB 响应上限；只在请求时读取
  `QUOTA_WATCH_KIMI_API_KEY`，不读取 Kimi CLI/OAuth/浏览器 Cookie 或开发 worker 的变量。
- 新增默认关闭的 `QUOTA_WATCH_KIMI_REAL=1`、`kimi_real` HTTP/Flutter 场景。Kimi 真实场景只查询
  Kimi；Codex 显示“当前场景未查询”，GLM 显示“本卡尚未接入”，避免把未查询误写成零额度。
- 离线 HTTP 替身覆盖固定 URL、安全 Header、缺 Key、401/402/403、404、429、5xx、超时、重定向、
  损坏/超大 JSON 与空额度窗口；没有消耗真实额度。
- 最终自动验证：`compileall`、`pip check`、Flutter 格式化与静态分析均通过；全后端 `pytest`
  **395 passed**，`flutter test` **43 passed**，Web Release 构建成功。
- 用户本人把已有 Kimi Code 环境变量安全映射到项目变量并启动本地后端；脱敏真实检查返回 HTTP 200、
  Kimi status=ok、2 个有效窗口、`fetchedAt` 存在、敏感字段 0。检查没有打印或保存额度值、套餐名、
  Key 或原始响应。下一项学习证据是用户在界面查看真实窗口并说明数据链路。

### 补充：GLM 默认关闭 Adapter 与综合实际额度模式（2026-07-23）

- 用户明确授权建立 `STAGE7_GLM_REAL_AND_ALL_REAL_TASK.md`、实现默认关闭的 `GlmProviderAdapter`，
  并增加 Codex + Kimi + GLM 综合实际额度模式。
- 复核智谱官方资料与 `zai-org/zai-coding-plugins` 官方源码：quota endpoint 的 wire contract 属于
  L2 官方开源证据；但官方 FAQ/订阅边界没有明确授权任意第三方监控工具，所以“代码可实现”不等于
  “已获真实调用许可”。
- 本机存在并正在运行 ZCode 3.4.2。官方 Usage Stats 可显示编程套餐额度，但本轮官方文档未发现
  导出、CLI 或本地只读 API；项目没有读取 ZCode 私有数据库、缓存、Token、Cookie、日志或流量。
- 新增 `glm_adapter.py`：只读项目变量 `QUOTA_WATCH_GLM_API_KEY`，固定 HTTPS endpoint、禁止重定向、
  8 秒超时、1 MiB 上限，复用 `parse_glm_usage`；`QUOTA_WATCH_GLM_REAL=1` 默认关闭。
- 新增 `glm_real` 与 `all_real`：综合模式只调用各自开关已开启的 Provider，并发执行、稳定返回
  Codex/Kimi/GLM 顺序；未开启项为 `unknown`，单家失败不阻断其他结果。
- Flutter 设置页新增“GLM 真实额度（本机）”与“综合实际额度（本机）”，Fixture 模式不会保留这些
  后端专用场景；可见中文加入 Noto Sans SC 子集。
- 离线测试覆盖缺 Key、固定 URL/Header、401/402/403、404、429、5xx、超时、重定向、损坏/超大 JSON、
  空窗口、开关关闭、只调用已开启项、并发、单家失败与异常信息脱敏。
- 最终验证：`compileall`、`pip check`、Dart format、`flutter analyze` 均通过；全后端 `pytest`
  **419 passed**，`flutter test` **44 passed**，Web Release 构建成功。
- 本卡按原边界没有发真实 GLM 请求。之后用户另行确认风险并授权一次本机脱敏检查：HTTP 200、
  GLM `status=ok`、两个有效窗口、`fetchedAt` 存在且无错误；没有打印或保存额度值、套餐、Key、
  账号信息或原始响应。该结果只证明本机当前技术链路，不扩展为公开使用授权。

### 补充：一键启动 Quota Watch（2026-07-23）

- 建立 `STAGE8_ONE_CLICK_LAUNCHER_TASK.md`，新增根目录 `启动 Quota Watch.cmd` 与
  `scripts/start_quota_watch.ps1`。入口完成“检查依赖 → 后台 FastAPI → 健康等待 → Flutter Edge
  backend/all_real → 仅清理自有后端”的完整启动链。
- 启动器只把已有 `KIMI_CODING_API_KEY`/`GLM_API_KEY` 临时映射给新后端子进程；不修改用户级变量、
  不写 `.env`、不输出 Key。已有 Quota Watch 后端只复用；无关端口占用会安全失败且不结束对方。
- 新增 6 个启动器测试，覆盖 Validate、强制离线 SmokeTest、进程清理、现有后端复用、端口保护、
  CMD 连线以及日常模式的 `all_real` Flutter 参数。自动测试不调用真实 Provider。
- 首次 Windows PowerShell 5.1 解析暴露 UTF-8 无 BOM 中文脚本兼容问题；运行期提示改成 ASCII 后，
  真实解析和启动通过。这说明“脚本内容正确”还需在目标 Shell 上执行验证。
- 最终回归：后端 **425 passed**、Flutter **44 passed**、Dart format、`flutter analyze`、
  Python compileall、pip check 与 Web Release build 均通过。Playwright 打开构建产物并稳定渲染；
  离线证据截图确认中文字体、三卡布局与部分失败状态，无真实额度。
- 用户停止旧手动后端后，Codex 运行一键入口；新 FastAPI 的 `/health` 为 `ok`，Dart/Flutter 进程
  已运行。该检查没有读取、打印或截图实际 Provider 额度；页面内容仍由用户本人验收。

### 补充：GLM 当前契约漂移修复（2026-07-23）

- 用户确认一键启动、Codex 与 Kimi 正常，但 GLM 与 ZCode 不一致，并明确要求继续直接测量，禁止
  使用截图数值作为数据源。
- 脱敏结构探针只输出字段名、类型和数量：官方响应实际有三条 limits；5 小时/每周 TOKENS_LIMIT
  当前只有 `number/percentage`，工具 TIME_LIMIT 当前为 unit 5。旧解析器错误套用历史 40M 默认值、
  丢弃每周窗口并把 unit 5 显示为未知。
- 新增当前/历史双契约分支。第一轮误把 ZCode 页面“剩余额度”标题当作原始字段语义，将三项
  `percentage` 全部取反；用户无数值对照指出 5 小时和每周方向相反。第二轮只修 Token 两项后，
  用户继续指出工具调用也反了。最终当前契约统一为 `used = percentage`，三项都不取反；历史
  `usage/currentValue` 仍按绝对值解析。所有 Fixture 数值完全虚构。
- Flutter 详情页补齐 percent/calls 格式，避免把百分比和调用次数显示成分钟；字体子集由 817 个
  唯一码点重建。
- 解析器/Adapter 专项 **71 passed**、详情页专项 **9 passed**；最终完整回归为后端 **431 passed**、
  Flutter **45 passed**，format/analyze、compileall、pip check、Web Release 与 Playwright E2E
  均通过。早期 E2E 因默认离线 build 与脚本等待 partial 场景不匹配而超时；改用明确的
  backend/partial 构建后通过。最终方向修复复验时，第一次临时静态服务在 7358 返回空响应，
  换用干净端口 7359 后通过，并最终恢复默认 Release build。
- 一次“拒绝连接”排查发现后端仍存活但 Flutter 启动进程已退出；重新运行一键入口后
  `/health=ok` 且 Flutter/Dart 恢复。最终方向修复后再次重启。
- 脱敏真实复验只保留关系结论：三个窗口的统一 `used` 均等于各自服务端 `percentage`；没有输出
  或保存实际比例、套餐、Key 或原始响应。最后页面证据仍由用户仅反馈一致/不一致，不发送额度值。

### 结论

Codex、Kimi 与 GLM 已完成代码、离线自动验证和各自的脱敏本机结构检查；GLM 仍默认关闭，公开使用
边界没有扩大。一键启动链已通过自动与真实启动健康检查，下一项是用户核对页面三张卡并解释一次
失败状态。


1. 已完成基础注释、模型边界和 Widget 测试。
2. 已建立 `QuotaRepository`，页面与具体 Mock 数据源解耦。
3. 正在用本地 JSON fixture 补齐正常、空和失败状态。
4. 下一阶段创建 FastAPI 假后端的 `/health` 与假额度路由。
5. 再让 Flutter 调用本地假后端，完成第一个“前端 → HTTP/JSON → 后端 → 测试 → 人工验收”的纵向闭环。

这条路线不要求先精通 Dart 或 Python；每一步只补完成当前交付切片所需的技术知识。

## 2026-07-22 / 阶段 1→2 / 卡 2 完成记录

### 本卡完成内容

- 用户先预测了正常额度 `40/100` 和超额额度 `120/100` 的结果：剩余量、使用率和状态均符合模型规则。
- 根据用户的产品判断，将 `95%～不足 100%` 定义为“紧张”，达到或超过 `100%` 定义为“耗尽”；模型新增 `isExhausted`，卡片标签和 Widget 测试同步更新。
- 新增 `QuotaWindow` 的正常、零上限、紧张、耗尽/超额、已过期重置时间测试，并补充 100% 卡片显示“耗尽”的 Widget 测试。
- 通过 `dart format`、`flutter analyze --no-fatal-infos`（无 error，保留 14 条已有 info）和 Codex 运行的测试。

### 用户验收证据

- 用户亲自运行 `flutter test`，确认输出 `All tests passed!`。
- 最终共 8 个测试场景通过：5 个模型测试、3 个 Widget 测试。
- 用户已理解 `expect(实际结果, 预期结果)` 的位置和测试通过标准。

### 本卡结论

- 阶段 1 的基础 UI、模型边界和测试闭环已有证据；不把未覆盖的功能宣称为已验证。
- 下一张任务卡：阶段 2 / 卡 1 / Repository 解耦。目标是让 UI 依赖接口而非直接依赖 Mock 实现，为 JSON fixture 和 FastAPI 假后端保留替换点。

## 单次学习会话模板

复制本节到文件末尾填写。

```markdown
## YYYY-MM-DD / 阶段 X / 任务卡 X

### 1. 开始前

- 今天的可见目标：
- 相关文件或错误原文：
- 我已经知道的：
- 我最不确定的：
- 明确不做的：

### 2. AI 协作记录

- 我使用的 Prompt：
- AI 提出的方案：
- 我选择的方案与理由：
- 我拒绝或修改了哪些建议：

### 3. 工程修改

- 修改文件：
- 核心 diff：
- 关键设计决定：

### 4. 验证证据

- 执行命令：
- 测试结果：
- 人工操作结果：
- 截图/日志路径：
- 仍未验证的内容：

### 5. 反向讲解

- 数据从哪里来、到哪里去：
- 最可能失败的三个位置：
- 这次测试实际证明了什么：
- 如果需求变化，我会先改哪里：

### 6. 复盘

- 今天真正学会的：
- AI 曾经错误或无证据的地方：
- 我仍无法解释的：
- 下一张最小任务卡：
```

## 月度能力自检

每四周为每项填写 `不能 / 提示后能 / 独立能 / 能教别人`。

| 能力 | 当前等级 | 最近证据 |
|---|---|---|
| 写清楚目标、范围和验收 |  |  |
| 让 AI 先计划再编辑 |  |  |
| 阅读并解释完整 diff |  |  |
| 运行并解释静态分析和测试 |  |  |
| 根据错误提出可证伪假设 |  |  |
| 识别凭据与隐私风险 |  |  |
| 解释 Flutter 数据流 |  |  |
| 解释前后端请求链路 |  |  |
| 为边界情况补测试 |  |  |
| 独立完成一次小功能闭环 |  |  |

## 学习会话记录

## 2026-07-22 / 阶段 0 / 卡 2 / Git 基线与 Web 验证准备

### 本次目标

- 在不接入真实 API、不上传凭据的前提下，让现有 Flutter 草案具备 Web 运行入口、最小测试和可回退的 Git 节点。

### 已完成

- 补齐 Flutter Web 工程文件：`web/`、测试目录、分析配置和依赖锁定文件。
- 修复路由实现：当前使用 `MaterialApp` + `onGenerateRoute`，首页可以跳转详情页。
- 增加两个 Widget 测试：验证三家模拟套餐显示，以及点击 Codex 卡片进入详情页。
- `flutter test`：2/2 通过。
- `flutter build web`：构建成功，构建目录由 `.gitignore` 排除。
- 完成密钥模式检查，没有发现明显 API key；本次仍未接入真实 API。
- Git 提交并推送：`fe6a3ba feat: add web scaffold and smoke tests`；本地 `main` 与 `origin/main` 已同步。

### 本次遇到的终端知识点

- 之前给出的命令是 PowerShell 写法，但当前终端实际是 Git Bash。
- Git Bash 中 Windows 的 `D:\APPDEsign\quota_watch` 应写成 `/d/APPDEsign/quota_watch`；PowerShell 的调用符号 `&` 不能直接照搬。

### 人工验收结果

- 用户已在 Git Bash 中亲自运行：

  ```bash
  cd /d/APPDEsign/quota_watch
  /e/Move/flutter/bin/flutter.bat run -d edge
  ```

- 用户回报 Edge 人工验收已完成；这证明当前 Web 启动路径和本次人工检查的界面操作可用。
- 运行截图已保存为 [`docs/evidence/2026-07-22-stage0-edge-home.png`](evidence/2026-07-22-stage0-edge-home.png)；截图显示首页、Codex/Kimi/GLM 三张卡片及模拟额度信息。
- 本记录没有单独保存浏览器控制台输出，因此不把“控制台无错误”列为已验证结论。

### 尚缺的学习证据

- 能指出 `main()` → `MaterialApp` → `HomePage` 的启动路径。

### 用户反向讲解

- 改了什么：增加了基础功能。
- 为什么：让应用实现基础功能。
- 怎样证明：Edge 能打开并显示首页，点击具体项目能进入详情页并显示详细信息。
- 启动与功能边界：页面打开可以证明程序启动和首页正常，但详细功能要分别测试。

这段讲解已经覆盖“改了什么、为什么、怎样证明”的基本结构，也正确区分了启动证据与功能证据；后续任务会继续训练把“基础功能”说成更具体的代码和行为变化。

## 2026-07-22 / 计划校准 / 访谈基线

### 已确认目标与条件

- 希望独立掌握软件开发流程，以及 Vibe Coding 的规则、流程和风险；“独立”指允许持续使用 AI，但能自己判断和验收。
- 有 C 语言学习经历但已遗忘较多；用过终端、Git、commit、push、diff，并借助 AI 完成过博士论文 TeX 流程优化。
- 英文技术文档阅读轻松；Codex、Kimi、GLM 均已订阅，Codex 最重要。
- 产品希望开源，并让其他人能够安装、使用和贡献。

### 当前知识缺口

- 尚不能解释源代码怎样成为可运行 App。
- 尚不能解释“程序运行成功”为什么不等于功能正确。
- 对 HTTP/API 有初步印象；需要通过 fixture 练习建立“JSON 是数据格式，不是脚本”的正确模型。
- 遇到错误目前习惯让 AI 自行排查，后续要逐步增加“阅读完整错误 → 判断假设 → 亲自验证”的参与度。

### 已验证的工作区事实

- Flutter 3.44.2 与 Dart 3.12.2 已安装到 `E:\Move\flutter`，用户 PATH 已加入 `E:\Move\flutter\bin`。
- `flutter doctor -v` 已完成：Chrome/Web 可用；Android SDK 与 Visual Studio C++ 缺失，但当前 Web 学习不阻断。
- 仓库根目录尚未初始化 Git。
- Flutter 代码只连接 Mock 数据，尚无 FastAPI 后端或真实额度 API 实现。
- Codex 当前可见 Kimi/GLM worker；它们是辅助开发模型，不是 Quota Watch 的额度数据接入。

### 下一步

进入“阶段 0 / 卡 2”：初始化 Git、保存现有代码基线，不接 API、不重做 UI。

## 2026-07-22 / 阶段 0 / 卡 1 / Flutter 工具链诊断

### 验证证据

- SDK 来源：用户提供的 `E:\Move\flutter_windows_3.44.2-stable.zip`。
- 安装位置：`E:\Move\flutter`。
- `flutter --version`：Flutter 3.44.2、Dart 3.12.2、DevTools 2.57.0。
- `flutter doctor -v`：Flutter、Windows、Chrome、网络资源均通过；Android SDK 和 Visual Studio C++ 未安装。

### 结论

- 当前使用 Chrome 作为第一运行目标，不需要立即安装 Android Studio 或 Visual Studio。
- “SDK 可用”已经得到证明；“项目可运行”仍需阶段 0 / 卡 2 补脚手架后验证。
- 下一张最小任务卡：初始化 Git，保存现有 Flutter 草案基线。

## 2026-07-26 / 阶段 11 / Windows 开机自启动与默认桌面组件

### 本次目标

- 在 Windows 设置页增加当前用户级“开机时自动启动”开关。
- Windows 桌面版启动后默认进入桌面悬浮插件，同时保留托盘里的置顶小窗切换。

### 工程修改

- Windows runner 在 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
  读取、写入和删除 `Quota Watch` 启动值，不要求管理员权限。
- 启动命令只包含仓库根目录 `启动 Quota Watch.exe` 的带引号路径，不携带
  Provider Key、后端参数、额度值或原始响应。
- runner 从当前 Release EXE 逐级向上寻找启动器和
  `scripts/start_quota_watch.ps1`，不写死开发者的绝对仓库路径；仓库移动后旧
  路径不会被误判为已启用，重新开启即可更新。
- 设置页新增读取态、忙碌态、成功提示和失败回滚。
- Windows 真正执行桌面 `init()` 时默认应用 `desktop_widget`；Web、Android
  和未执行桌面初始化的 Widget 测试仍保持普通窗口行为。

### 验证证据

- `flutter analyze`：无问题。
- `flutter test`：64 项全部通过；新增用例覆盖开启成功与原生写入失败回滚。
- `pytest -c backend/pytest.ini backend/tests`：428 项全部通过；源码守卫覆盖
  HKCU、Run 键、GUI 启动器、删除路径和默认桌面模式。
- `flutter build windows --release`：成功生成 Windows Release。
- `git diff --check`：本卡文件无空白错误。
- 实际 GUI 启动链：`/health=ok`，`127.0.0.1:8000` 单监听，前端和 launcher
  各 1 个进程。
- 实际窗口观察：启动后是无应用栏三磁贴桌面组件，普通窗口可覆盖它，符合
  桌面层模式；没有把置顶小窗当成默认状态。
- 当前 Windows 启动项仍为关闭；实现没有替用户改变该个人选择。

### 仍需用户验收

- 在托盘右键进入“数据设置…”，开启“开机时自动启动”，确认成功提示。
- 注销并重新登录 Windows，确认 Quota Watch 自动出现且仍是桌面悬浮插件。
  这一步证明真实登录触发链，不能由应用当前已启动或自动化测试替代。

### 反向讲解

- 设置页开关只是输入；MethodChannel 把选择传给 Win32，注册表保存下一次
  Windows 登录时要运行的 GUI 启动器，启动器再负责后端和 Flutter 前端。
- 自动测试证明读写协议、失败回滚和回归安全；Release 编译证明 C++ 可构建；
  当前启动成功仍不等于“下一次登录自启动”已经人工验收。

### 下一张最小任务卡

- 完成一次注销/登录人工验收；若后续制作安装器，再把启动器定位从仓库搜索
  升级为安装目录契约，并增加卸载时清理启动项。

## 2026-07-27 / 瘦身路线 / Stage 12 纯净生产运行环境

### 本次目标

- 保留现有 Flutter UI，把 Python 开发依赖与生产运行依赖彻底分开。
- 让实际 GUI 启动器优先使用经过验证的 `.venv-runtime`。

### 工程修改

- 新增 `backend/requirements-runtime.lock`，锁定16项直接和传递运行依赖。
- 新增 `scripts/build_runtime_venv.ps1`：精确重建
  `backend/.venv-runtime`，使用 `--without-pip`、`--no-compile` 和
  `--no-deps`，并验证核心导入与开发包排除。
- 启动脚本优先使用 `.venv-runtime/Scripts/pythonw.exe`，缺失时才回退
  `.venv`，因此现有开发流程仍然可用。
- 后端以 Python `-B` 和 `PYTHONDONTWRITEBYTECODE=1` 启动，避免首次运行
  生成 `.pyc` 让生产环境重新膨胀。
- 更新源码守卫；同时校准已被 Stage 12 悬浮窗淡出功能淘汰的旧透明度断言，
  没有修改 Flutter UI。

### 体积证据

- 开发环境 `.venv`：55.75 MiB。
- 纯净运行环境 `.venv-runtime`：11.64 MiB。
- 减少：44.11 MiB，约79%。
- Smoke Test 前后均为 `12,208,005` bytes，新增 `.pyc` 数量为0。
- 运行环境不包含 Pillow、pytest、Pygments 或 pip。

### 验证证据

- 运行环境构建和 `-ValidateOnly`：通过。
- 离线 Launcher Smoke Test：启动、健康、响应和清理全部通过。
- 后端：432项测试全部通过。
- Flutter：74项测试全部通过。
- `flutter analyze`：无问题。
- 实际 GUI 重启：`/health=ok`，8000单监听，前端和 launcher 各1个；
  `.venv-runtime` 后端1个，开发 `.venv` 后端0个。
- 第一次重启曾复用旧开发后端；清理精确的8000端口所有者及其 venv 父进程后
  再启动，才得到有效的生产环境证据。

### 反向讲解

- `requirements.txt` 写得少并不等于发布环境真的小；必须在独立目录安装并
  验证实际内容。
- 本阶段节省的是磁盘，Python进程仍然存在；下一阶段只有把 Provider 解析和
  请求逐步迁入 Dart，才会开始减少常驻内存。

### 下一张最小任务卡

- 迁移 Kimi Provider 的纯解析契约到 Dart：先用相同 Fixture 做 Python/Dart
  对照，不改变真实请求、凭据存储或现有 UI。

## 2026-07-26 / 阶段 11 / 桌面悬浮窗自治与视觉修正

### 改动摘要

- 数据自治：`QuotasController` 增加 5 分钟自动刷新（Timer 随 build 重建、
  onDispose 取消）；新增 `tickerProvider` 每分钟 tick（Notifier + Timer），
  `QuotaWindowBlock` watch 后倒计时文案随时间重算。
- 失败保留旧数据：`reload()` 改用 `copyWithPrevious`；首页 body 基于
  `valueOrNull` 构建，`hasError && hasValue` 时保留卡片并在列表顶部显示
  “刷新失败，显示上次数据”提示条（带“重试”）；seamless 卡片底部显示
  “更新于 HH:mm”（fetchedAt）。
- 悬浮交互：整卡 `WindowDragArea`（move 光标），hover 浮现刷新 / 隐藏到
  托盘 / 切换置顶小窗三个小按钮（Stack 上层，在拖动区之外）。
- 视觉：seamless 跳过 `BackdropFilter`（Flutter 模糊不到桌面壁纸），玻璃
  边框 alpha 提升（暗 0.10→0.22 / 亮 0.30→0.45）并加极淡投影；圆角收敛为
  `AppTheme.cardRadius`（卡片、主题、原生区域通道三处共用）。
- 性能：原生区域下发加脏检查（enabled/区域/像素比签名相同则跳过
  MethodChannel）；内容溢出时挂常驻 Scrollbar 并把卡片区域合并为一条
  视口全宽区域保证滚动条可命中，未溢出保持逐卡片间隙点击穿透。

### 验证结果

- `dart format lib test`：通过（2 个文件被格式化）。
- `flutter analyze`：无问题。
- `flutter test`：70 项全部通过（新增 6 项：controller 失败保留旧数据 1 项 +
  desktop_floating_ux_test 5 项）；玻璃磁贴 dark/light golden 按新视觉重建。
- `scripts/build_font_subset.ps1 -SourceFont <官方源字体>`：成功，969 码点、
  428300 字节；U+2715 为既有字符的既有告警，与本次新增文案无关。

### 偏离记录

- `tickerProvider` 用 Notifier + Timer 而非设计中的 StreamProvider：
  Stream.periodic 的取消是异步的，widget 测试在树上缴后仍报 pending
  timer；Timer + onDispose 与自动刷新同模式，测试可验证。
- ListView 的 ScrollController 只在 seamless 挂载：普通模式下显式
  controller 会使下拉刷新手势（测试与真机）不再触发 RefreshIndicator。

### 仍需用户验收

- 悬浮模式手动冒烟：自动刷新触发、断后端时旧卡保留且出现提示条、hover
  三按钮可用、整卡可拖动、未溢出时卡片间隙仍可点击穿透。

## 2026-07-26 / 阶段 12 / 悬浮窗"无感"化（紧凑行 + 半透明 + 闲置淡出）

### 改动摘要

- 紧凑行（方案 B）：`QuotaCard` 新增 `expanded` 参数；seamless 未 hover 时
  渲染单行（小 logo + 名称 + 主窗口"已用 X%" + 3.5px 细进度条 + 6px 状态
  圆点），主窗口为空时退化为名称 + 状态文字。`_SeamlessCardShell` 用
  `AnimatedSize`（150ms, easeOut）在紧凑/完整两形态间原地切换；外壳内套
  `SizeChangedLayoutNotifier`，首页经 `NotificationListener` 逐帧重算原生
  点击区域（外壳内部 setState 不触发首页 build，此通道替代显式回调）。
- 半透明降存（方案 A）：seamless 面板 tileColor alpha 0.65，边框 alpha
  暗 0.22→0.12 / 亮 0.45→0.25，删除阶段 11 的 seamless 投影。状态颜色
  抽取为 `quotaStatusColor`（_StatusChip 与紧凑行共用）；"充足"时紧凑行
  百分比/圆点/进度条用 outline/onSurfaceVariant 级 muted 色，只有
  告警/紧张/耗尽/错误等异常才着彩色。
- 闲置淡出：`DesktopController` 接口新增 `setOpacity`（io 走
  `windowManager.setOpacity` 并容错 MissingPlugin/PlatformException，
  web no-op）；首页 seamless 列表挂 MouseRegion + 500ms 防抖 Timer——
  进入立即恢复 1.0，离开 500ms 后降到 0.45；切回非 seamless 与 dispose
  时恢复 1.0（`_opacityIdle` 脏标记避免重复通道调用）。

### 验证结果

- `dart format lib test`：通过。
- `flutter analyze`：无问题。
- `flutter test`：74 项全部通过（新增 5 项、改写 4 项阶段 11 用例）：
  紧凑行默认形态（有"已用"无"更新于"）、hover 展开/移开收回、
  充足 muted / 告警彩色、主窗口为空退化、setOpacity web no-op、
  闲置淡出防抖与恢复（mock window_manager 通道）。
- golden compact_glass_tile dark/light 已用 `--update-goldens` 重建并目检：
  三条紧凑行、GLM 87% 告警着色、其余 muted，符合设计。
- 未新增可见中文（复用"已用 X%"与状态文字），字体子集无需重建。

### 偏离记录

- 展开后区域重算用 `SizeChangedLayoutNotifier` 通知链替代设计建议的
  hover 回调/状态上移：无定时器、不在测试中引入 pending timer，
  且逐帧跟随动画；原生区域下发的脏检查吞掉重复签名。
- 亮主题 seamless 边框 alpha 定为 0.25（设计只给出暗色 0.12；按同比例
  从 0.45 下调）。

### 仍需用户验收

- 日常三条紧凑行、hover 展开、离开约半秒淡出、告警状态变色。

## 2026-07-27 / 阶段 13 / Kimi 纯解析器迁入 Dart

### 改动摘要

- 新增 `KimiUsageParser`：把 Kimi `/coding/v1/usages` 的 `usage` 与
  `limits` 归一为现有 Dart `QuotaWindow`；覆盖 `remaining` 回退、
  used/limit 钳制、标签优先级、数字字符串、reset 别名、相对秒数和
  纳秒截断。
- 解析器是纯函数边界：没有 HTTP、存储、凭据或 UI 依赖；本卡没有修改
  Flutter 页面、悬浮窗布局或可见文案。
- 四个现有脱敏响应样例共用
  `backend/fixtures/kimi/parity/parser_expected.json` 黄金结果；Python
  测试验证旧解析器，Dart 测试验证新解析器，形成跨语言同输入/同输出锁。
- 黄金文件放入 `parity/` 子目录，避免被既有“每个 Kimi 根目录 JSON 都是
  Provider 原始响应”的发现规则误判。

### 验证结果

- Dart 定向测试：11 项通过（4 个 Fixture 对等 + 7 个关键边界）。
- Python Kimi 定向回归：55 项通过。
- Python 全量回归：433 项通过。
- Flutter 全量测试：85 项通过。
- `flutter analyze`：无问题（首次发现 1 条 null-aware 风格提示，修正后
  复跑通过）。

### 当前边界与下一卡

- 已迁移的是 `JSON -> QuotaWindow`，真实 Kimi HTTP 和 API Key 读取仍由
  Python/FastAPI 承担；因此这一步本身不减少运行时进程。
- 下一卡迁移 Windows 端安全凭据读取和 Kimi HTTP 到 Dart Repository，
  用本解析器接入现有统一模型；真实 Key 不进入测试、日志、截图或 Git。

## 2026-07-27 / 阶段 14 / Kimi 真实查询迁入 Windows Dart

### 改动摘要

- 新增 `KimiQuotaRepository`：固定调用官方
  `https://api.kimi.com/coding/v1/usages`，关闭重定向，响应限制 1 MiB，
  通过阶段 13 解析器产出统一模型。
- Windows runner 的既有 MethodChannel 增加只读凭据桥；原生端只接受
  `kimi` / `glm` 两个名字并映射到固定 WinCred 目标，不枚举凭据、不输出
  Key、不把秘密放进错误信息。
- 新增条件平台 Repository 工厂：只有 Windows `kimi_real` 改走 Dart；
  Web、Android、Codex、GLM 和 `all_real` 仍走原 FastAPI，避免迁移中途
  改变其他平台/场景。
- Dart Kimi 链路保留进程内最后成功值；后续刷新失败时继续显示旧窗口，
  `status=error` 并附归一化“数据可能已过期”提示。
- 生产 GUI 启动器仍清除 Provider 环境变量，不把 Key 注入 Flutter；
  正常发布路径从 Windows 凭据管理器按需读取。环境变量入口仅保留给开发者
  直接启动调试。

### 验证结果

- Kimi Repository + parser + WinCred 通道定向测试：29 项通过。
- Windows 原生源码安全守卫：12 项通过。
- `flutter analyze`：无问题。
- Windows Profile 原生构建成功：
  `build/windows/x64/runner/Profile/quota_watch.exe`。
- Release 构建先完成编译、在链接时因当前正在运行的正式悬浮窗锁住
  `Release/quota_watch.exe`（LNK1104）而停止；为避免打断用户，改用独立
  Profile 目录完成同一 C++/Dart 源码的完整链接验证。

### 当前边界与下一卡

- `kimi_real` 已成为第一条不经过 Python/FastAPI 的真实 Provider 纵向链；
  默认 `all_real` 仍需要后端，因此当前生产启动进程数和常驻内存尚未下降。
- 下一卡迁移 GLM、Codex、配置元数据与凭据写入，再把默认综合查询切到
  Dart，届时才删除 FastAPI 启动职责并测量真实单进程收益。

## 2026-07-27 / 阶段 15 / 三家 Provider 与本机配置全部迁入 Dart

### 改动摘要

- GLM 新增 Dart 解析器与固定官方 HTTPS Repository；Codex 新增官方
  `codex app-server` JSONL Client、解析器和 Repository。Kimi 沿用阶段 14
  的直接链路。
- 三家解析器各用脱敏 Fixture 与 Python/Dart 共用黄金结果锁定语义；网络
  响应限 1 MiB、禁重定向，Codex 子进程不经过 shell，超时后确定性清理。
- 新增 `AllRealQuotaRepository`：并发查询、稳定排序、单家失败隔离和最后
  成功缓存；Windows 四个真实场景都直接走 Dart，Web/Android 继续走后端。
- 凭据保存、替换、删除迁入固定目标 WinCred 原生通道；本地 JSON 只存标签
  与手动备注。现有设置页只替换内部 Repository，没有调整可见 UI。

### 验证证据

- Python/Dart 解析对等、错误映射、缓存、并发隔离、进程限长与超时路径均有
  离线测试。
- Windows Profile 与 Release 原生构建均成功。
- 未读取或记录真实 Key、额度值、原始 Provider 响应。

### 反向讲解

- “把解析器搬到 Dart”还不能删除后端；请求、凭据、元数据、聚合与失败回退
  全部迁完，默认 `all_real` 才真正脱离 Python。

## 2026-07-27 / 阶段 16 / 单进程启动器与最终瘦身

### 改动摘要

- 根 GUI 启动器缩减为单实例唤醒、Release 定位、Provider 环境变量清理、
  早期失败提示；直接启动 Flutter 后退出，不再监督 PowerShell/FastAPI。
- Windows 自启动仍写当前用户 `HKCU Run`，目标是根启动器；原生查找与根
  启动器均已解除对 `scripts/` 的隐性依赖。现有开关状态未被自动修改。
- Python 后端、纯运行 venv 和开发脚本保留在仓库用于 Web/Android 与离线
  回归，但不进入 Windows 发布运行链。

### 最终验证证据

- Python：432 项全部通过；Flutter：145 项全部通过；`flutter analyze`
  0 问题；Windows Release、根启动器和 Web Release 均构建成功。
- 根启动器实际重启后：1 个 `quota_watch.exe`、0 个常驻 launcher、0 个
  backend Python、8000 端口 0 监听；刷新稳定后无遗留 Codex 子进程。
- 窗口探针：可见、顶层桌面窗口、非 TopMost、非 ToolWindow；保留原桌面
  悬浮窗行为，没有修改 UI。
- 当前 Windows Release 为 32.12 MiB，启动器约 0.04 MiB；淘汰的纯运行
  `.venv-runtime` 为 11.64 MiB。
- 另建 32.16 MiB 最小发布树，只含根启动器与嵌套 Release：在没有
  `backend/`、`scripts/`、venv 的情况下实际启动成功，launcher 随即退出，
  无 Python 与 8000 监听；验证后已清理临时副本并恢复正式实例。
- 同机空闲采样：新 Flutter 单进程 134.12 MiB 工作集、104.53 MiB 私有
  内存；旧离线 FastAPI 运行链单独为 57.31 MiB 工作集、39.50 MiB 私有
  内存，因此至少省去这部分常驻开销。
- 现有自启动注册表值已启用且正确指向根启动器；本轮只读取验证，没有擅自
  改动用户设置。

### 反向讲解与用户验收

- 真正瘦身来自删除常驻运行层，不是删一个置顶按钮；置顶功能本身只占少量
  代码与近乎不可测的闲置内存。
- 仍需用户做一次注销/登录验收：确认登录后直接恢复桌面悬浮插件、三家卡片
  的方向和状态正常。该步骤验证 Windows 登录时序，自动测试不能替代。

# Stage 9 / 托盘菜单、窗口恢复与可见悬浮组件修复任务卡

> 状态：第五次桌面层语义修复已完成，用户 `Win+D` 实机验收通过
>
> 用户连续反馈：
>
> 1. 托盘图标右键没有菜单。
> 2. 打开后窗口没有出现在屏幕上方。
> 3. 没有形成常驻桌面的小组件。
> 4. 收起后无法重新打开，托盘右键仍没有菜单。
> 5. 修复后仍“打不开”。
> 6. 点击托盘“桌面悬浮插件”完全无效，屏幕上不显示任何内容。
> 7. 可见性修复后变成始终置顶，普通应用最大化无法覆盖，不符合真正桌面组件语义。

## 第五次任务边界

- 目标：`desktopWidget` 保持在 Windows 桌面之上，但不是 topmost；激活或最大化普通应用后
  应被覆盖，显示桌面时应重新出现。
- 实现约束：保持 Flutter 主窗口为无 owner 的普通顶层窗口，不切换 `WS_CHILD`、不对主窗口启用
  `WS_EX_TOOLWINDOW`；通过桌面层 Z-order 与独立的隐藏状态窗口表达桌面归属。
- 完成证据：源约束测试、Win32 owner/style/z-order 检查、最大化应用遮挡的局部像素对比，
  以及用户执行一次 `Win+D` 验收。
- 非目标：不修改额度数据、Provider、页面布局、凭据或启动器生命周期。

## 目标

```text
双击启动
  → 只启动一个实例
  → 340×520 悬浮窗真实显示在当前显示器右上角
  → 关闭/收起后仍可从托盘恢复
  → 即使再次选择当前已勾选模式，也会显示并重新应用该模式
  → 托盘右键明确弹出菜单
```

这张卡位于 Windows 原生窗口、托盘和 launcher 层，不修改额度数据、Provider、后端契约或凭据边界。

## 已确认根因

- `tray_manager` 只报告托盘右键事件；应用原先没有显式弹出菜单。
- `HWND_BOTTOM` 会把普通顶层窗口压到壁纸之后；进程和 HWND 存在不等于用户可见。
- 第一次桌面宿主方案使用 `SetParent(..., Progman)`。窗口成为 Shell 子窗口后，
  托盘插件可能把 `GA_ROOT` 解析成 `Progman`，回调和 popup owner 都会漂移。
- Shell 子窗口没有可靠的 `SC_MINIMIZE/SC_RESTORE` 语义，普通应用也会覆盖它。
- 把顶层 Flutter 窗口切为 `WS_EX_TOOLWINDOW` 后，运行期窗口矩形仍存在，但
  Flutter surface 只剩透明区域；继续依赖 Win32 style 证据会误判为成功。
- `WindowOptions.backgroundColor` 使用透明背景会进入 layered/composition 路径，
  增加“窗口存在、像素透明”的风险。
- `setDisplayMode` 原先遇到“所选模式等于当前模式”会直接返回；窗口已经隐藏时，
  点击当前已勾选的“桌面悬浮插件”因此确实没有任何可见结果。
- launcher 的第二实例原先只尝试唤醒一次；旧 launcher 正在退出、互斥量尚未释放而
  Flutter 窗口已消失时，新双击会静默返回。
- `Win+D` 不是普通的“逐个最小化”：Windows 会把承载桌面图标的 Shell 窗口整体抬到普通窗口
  之上。主窗口仍然 `Visible=True`、`Minimized=False`，但会被桌面本身覆盖，所以只拦截
  `SC_MINIMIZE` 无法解决。
- Windows 11 24H2 以后，`SHELLDLL_DefView` 可能直接位于 `Progman` 下，而不是旧版常见的
  `WorkerW` 下；桌面状态检测必须兼容两种层级。

## 当前实现决定

- `desktopWidget` 保持无 owner、非 topmost 的 Flutter 普通顶层窗口；正常状态插在 Explorer
  最高 `WorkerW/Progman` 桌面合成层正上方，所以壁纸在它下面、普通应用在它上面。
- 原生侧创建两个与 Flutter surface 完全分离的 0×0 隐藏窗口：底部 sentinel 用来判断桌面层
  是否被 `Win+D` 抬起，topmost helper 只在“显示桌面”期间进入 topmost 带的最底部。
- 检测到显示桌面后，主窗口临时跟在 helper 后面，因而高于被抬起的桌面但仍低于已有 topmost
  应用；恢复任一普通应用后，主窗口立刻退出 topmost 带并重新停回桌面层。
- 生产路径明确不对 Flutter 主窗口调用 `SetParent`、不修改 `WS_CHILD/WS_POPUP`，也不启用
  `WS_EX_TOOLWINDOW`，避免再次破坏 Flutter renderer。
- 当前仍不承诺从 Alt+Tab 列表消失；任务栏按钮由 `setSkipTaskbar(true)` 隐藏。

## 允许范围

- 修改桌面控制器的托盘右键、隐藏、恢复和显示模式时序。
- 使用固定应用 HWND 创建 Windows 原生托盘菜单。
- 把悬浮窗放到当前光标所在显示器工作区右上角。
- 修复 GUI launcher 的单实例唤醒和退出竞态。
- 增加离线源约束、launcher 生命周期测试、Win32 运行态检查和文档。

## 非目标

- 不修改页面内容、卡片布局或数据刷新协议。
- 不创建开机自启、安装包或 Windows 服务。
- 不读取、打印、保存或截图 Key、额度值、账户信息或 Provider 原始响应。
- 不依赖 ZCode、浏览器或其他应用的私有状态。

## 完成条件

- [x] 托盘图标在初始显示模式前注册，回调 HWND 保持为应用窗口。
- [x] Windows 托盘菜单使用保存的应用 HWND 和 `TPM_RETURNCMD`。
- [x] 收起使用 `hide()`，不使用桌面子窗口的 minimize/restore。
- [x] 托盘“显示”、左击和重复双击 launcher 都能唤醒已有窗口。
- [x] 选择任一显示模式都会 `show → apply`；置顶模式再 focus，当前模式不会提前返回。
- [x] Flutter 主窗口不使用 `HWND_BOTTOM`、Shell 子窗口或 `WS_EX_TOOLWINDOW`。
- [x] 正常状态保持无 owner、非 topmost、非最小化，并位于工作区右上角。
- [x] 普通最大化应用能完整覆盖同一屏幕区域。
- [x] 显示桌面状态由独立 sentinel 检出，主窗口只在该状态临时进入 topmost 带。
- [x] 恢复普通应用后主窗口自动回到 `Topmost=False` 的桌面层。
- [x] 实际窗口截图出现 Quota Watch 标题、设置、收起/退出按钮和页面内容，不再是透明矩形。
- [x] 隐藏后真实选择当前已勾选的“桌面悬浮插件”，同一个窗口 ID 重新出现。
- [x] launcher 在“旧互斥量稍后释放、窗口已不存在”时可等待并接管。
- [x] 连续双击不会产生第二个桌面实例。
- [x] Flutter format/analyze/test、Windows release build、launcher build 和后端回归通过。
- [x] 用户最终确认：`Win+D` 后小组件仍存在，返回应用后不再永久置顶。

## 学习点

- “进程存在”“Win32 `visible=True`”“自动化能识别控件”和“屏幕上确实有像素”是四种不同证据。
- Windows style 可以改变 Flutter renderer 的 surface；不能只看 HWND 属性推断画面。
- 模式选择不仅是状态变更，也是一条用户明确要求“显示窗口”的命令。
- 单实例互斥要同时处理“已有窗口”“启动中”和“退出中”三种时序。
- Microsoft 对 Show Desktop 的说明明确区分了“最小化窗口”和“抬起桌面”：
  [What is the difference between Minimize All and Show Desktop?](https://devblogs.microsoft.com/oldnewthing/20040527-00/?p=39153)
- Windows 11 24H2 的 `Progman/WorkerW` 层级变化参考了 Rainmeter 的已发布修复证据：
  [Fix 'Show Desktop' hiding skins on Windows 11 24H2](https://github.com/rainmeter/rainmeter/commit/b1128fb)

## 验证记录

- 失败态 1：两个窗口 `visible=True`、parent=None，但被 `HWND_BOTTOM` 压到壁纸后。
- 失败态 2：父类为 `Progman` 的 Shell 子窗口存在，普通应用覆盖后用户仍看不见。
- 失败态 3：普通顶层窗口启用 `WS_EX_TOOLWINDOW` 后，窗口截图只有透明背景。
- 第四次成功态解决了“完全不可见”，但 `Topmost=True` 造成普通应用无法覆盖，因此不是最终语义。
- 最终正常态：Flutter 主窗口 `Parent=0`、`Owner=0`、`Visible=True`、
  `Minimized=False`、`Topmost=False`、`ToolWindow=False`；矩形
  `[2204,16,2544,536]`，紧邻 Explorer 最高桌面合成层。
- `Win+D` 实机验收：桌面抬起后小组件仍显示；再次返回普通应用后运行态恢复
  `Topmost=False`、`DesktopRaised=False`。
- 真实桌面控制可识别 Quota Watch 标题、数据设置、最小化到托盘和退出控件；画面有实际内容。
- 真实收起后窗口从可见列表消失；托盘菜单选择当前 `desktopWidget` 后，同一个窗口 ID
  再次出现，证明“同模式恢复”不是只靠源代码断言。
- 原生托盘右键路径创建 8 项菜单窗口，5 个可见命令为“显示 Quota Watch / 置顶小窗 /
  桌面悬浮插件 / 数据设置… / 退出”。
- launcher 互斥量人工占用 2 秒后释放：新版 launcher 成功接管，最终应用 1 个、launcher 1 个。
- 当前回归：Flutter analyze 无问题、44 个 Flutter 测试通过、412 个后端测试通过；
  Windows release、根目录 GUI launcher 和 `-ValidateOnly` 均成功。
- 当前运行实例由根目录 `启动 Quota Watch.exe` 启动；后端 `/health` 返回 `ok`。

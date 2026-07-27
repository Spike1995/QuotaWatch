# Stage 9 / 桌面磁贴黑边修复任务卡

> 日期：2026-07-24
> 状态：等待用户复验

## 目标

消除三张桌面磁贴周围的 Windows 黑色非客户区边框，让原生窗口区域与 Flutter 圆角表面直接贴合，
同时保持普通应用可覆盖、`Win+D` 保留、托盘恢复和不透明 Flutter 渲染路径。

## 当前证据

- 实机窗口仍带 `WS_CAPTION`、`WS_THICKFRAME`、`WS_BORDER` 和 `WS_EX_WINDOWEDGE`。
- 外窗为 360×680，但 Flutter 客户区只有 352×675，左右各有约 4px、底部约 5px 的系统边框。
- 多区域 `SetWindowRgn` 已正确排除卡片间隙；黑边不是数据卡片布局问题，而是 Windows
  非客户区仍参与绘制。

## 实现方向

- 进入桌面组件模式时保存原始 `STYLE/EXSTYLE`，仅移除标题、缩放框和系统边缘样式，
  保留无 owner 的普通顶层窗口。
- 退出桌面模式时完整恢复原始样式，置顶小窗仍保留正常系统窗口行为。
- 不启用 layered window、透明背景、运行期 opacity、Shell `SetParent` 或
  `WS_EX_TOOLWINDOW`。
- 继续由现有 `SetWindowRgn` 负责三个圆角磁贴区域。

## 允许范围

- `quota_watch/windows/runner/flutter_window.cpp`
- `backend/tests/test_windows_widget_source.py`
- 对应任务卡、学习日志和交接文档

## 非目标

- 不修改额度数据、Provider、重置时间或真实请求。
- 不截图、输出或记录真实额度值。
- 不重新设计卡片内容和响应式布局。
- 不改变托盘菜单、单实例或启动器安全边界。

## 完成条件

- [x] 桌面模式不再带 `WS_CAPTION`、`WS_THICKFRAME` 或 `WS_EX_WINDOWEDGE`。
- [x] 实际 360×680 外窗与客户区同为 360×680。
- [x] 三段原生磁贴区域仍存在，窗口仍为非置顶、parent/owner 为 0。
- [x] 切回置顶小窗时原始窗口样式可恢复。
- [x] Flutter/后端相关回归与 Windows Release 构建通过。
- [x] 根目录 EXE 重启后单实例、8000 端口和 `/health` 正常。

## 验证证据

- 修复前实机：`STYLE=0x14CF0000`、`EXSTYLE=0x100`，仍带 caption、thick frame 和
  window edge；360×680 外窗的客户区只有 352×675，客户区偏移为 `4,0`。
- 仅移除 Win32 样式后客户区仍为 352×675；继续检查 `window_manager 0.5.2` 后确认，
  `TitleBarStyle.hidden` 会在 `WM_NCCALCSIZE` 中保留缩放边界。
- 最终方案同时调用 `windowManager.setAsFrameless()` 和原生样式收敛。修复后实机为
  `STYLE=0x94000000`、`EXSTYLE=0x0`，无 caption、thick frame 或 window edge；
  外窗与客户区均为 360×680，偏移为 `0,0`。
- 原生窗口仍为复杂区域，中心线包含 `8–151`、`161–338`、`348–589` 三段磁贴；
  `Parent=0`、`Owner=0`、`Topmost=False`。
- `flutter analyze` 无问题，Flutter **50 tests**、后端 **414 passed**、
  黑边/桌面源约束专项 **9 passed**，Windows desktop-widget Release 构建成功。
- 根目录 `启动 Quota Watch.exe` 已重启；前端、launcher、8000 端口监听各 1 个，
  `/health=ok`。

## 用户验收回退

- 2026-07-24：虽然非客户区探针全部通过，用户仍明确反馈“依然有黑边”。
- 因此上述证据只证明 Windows 系统框已消除，不能证明最终可见像素无黑边；任务重新打开。
- [x] 使用虚构额度的实际 Windows 桌面实例完成边缘截图/像素检查。
- [ ] 用户确认最终桌面观感不再有黑边。

## 第二根因与修复

- 使用本地虚构额度启动实际 Release 窗口，并在 200% DPI 下截取卡片右边缘的物理屏幕像素。
- 修复前：卡片与外窗右边界之间的 10px 逻辑空白为固定 `#121318`，与
  `WindowOptions.backgroundColor` 完全一致；外窗之外才恢复桌面下层颜色。
- 这证明 `SetWindowRgn` 已裁掉 Flutter 内容和点击区域，但 `window_manager` 的
  Accent 原生底色仍按完整矩形合成，形成用户看到的黑带。
- 最终时序：
  1. 启动阶段保持不透明底色，避免历史上的“Flutter surface 全透明”。
  2. 首页测量完三张卡片、即将应用原生区域时，才调用
     `setBackgroundColor(Colors.transparent)`。
  3. 进入设置、加载/空/错误状态或置顶小窗时，先恢复 `#121318`，再清除窗口区域。
  4. frameless 模式显式关闭 DWM shadow。
- 修复后同一物理像素位置从固定 `#121318` 变为桌面下层的
  `#6B3230`、`#481C1B` 等实际颜色；白色圆角卡片直接与桌面相接，不再经过黑带。
- 当前验证：`flutter analyze` 无问题，Flutter **50 tests**、后端 **414 passed**、
  桌面源约束专项 **9 passed**，Windows Release 构建成功。
- 最终根目录 EXE 重启后再次只截取不含文字/额度的右侧 32px 边缘；实际运行实例同一位置为
  `#6B3230`、`#481C1B`、`#4A1D1D` 等下层像素，没有 `#121318` 黑带。前端、launcher、
  8000 端口监听各 1 个且 `/health=ok`。

## 学习点

Flutter 的圆角卡片只控制客户区像素；Windows 的标题框、缩放框和扩展边缘属于非客户区。
要做到真正无黑边，需要让“Flutter 画布尺寸、原生客户区尺寸和 `SetWindowRgn` 区域”三者一致。

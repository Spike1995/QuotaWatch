# Stage 9 / 无面板桌面磁贴任务卡

> 日期：2026-07-24
> 状态：已完成并验证

## 目标

把桌面组件从“一整块应用面板”改成三张独立浮在桌面上的圆角磁贴：

- 桌面组件模式只显示磁贴所在区域，卡片间隙和下方空白不再遮住桌面。
- 保持 Flutter 主窗口的不透明渲染路径，避免再次出现“进程和窗口存在但画面全透明”。
- 设置页与置顶小窗继续使用完整矩形窗口。
- 弱化外阴影和徽标底色，减少视觉噪声，同时保持文字与进度条对比度。

## 当前证据

- 去掉顶部应用栏后，360×680 窗口仍有一整块深/浅色背景，第三张磁贴下方还有明显空白。
- 既往实机证明：透明 `WindowOptions.backgroundColor`、运行期 opacity 或
  `WS_EX_TOOLWINDOW` 可能破坏 Flutter surface。
- 当前桌面层的普通应用覆盖、`Win+D`、托盘恢复和单实例启动已通过验收，不能因视觉优化回退。

## 实现方向

- 使用 Win32 `SetWindowRgn` 把普通不透明窗口裁成多张圆角磁贴的并集；不启用 layered window、
  原生透明背景、Shell `SetParent` 或 `WS_EX_TOOLWINDOW`。
- Flutter 布局完成后读取每张卡片的真实几何位置，通过现有 MethodChannel 传给 Windows runner。
- 首页被设置页覆盖、切到置顶小窗、加载/空/错误状态时恢复完整窗口；返回桌面首页后重新应用磁贴区域。
- 桌面磁贴的服务商标题区域继续承担拖动入口，不增加可见标题栏。

## 允许范围

- `quota_watch/lib/app/desktop/`
- `quota_watch/lib/presentation/pages/home_page.dart`
- `quota_watch/lib/presentation/widgets/quota_card.dart`
- `quota_watch/lib/presentation/widgets/quota_window_block.dart`
- `quota_watch/windows/runner/flutter_window.cpp`
- 对应 Flutter/后端源约束测试、Golden、任务卡、学习日志与交接文档

## 非目标

- 不修改 Provider、额度百分比语义、重置时间规则或真实服务请求。
- 不截图、记录或输出真实额度值。
- 不改变桌面组件的 owner、parent、topmost、普通应用覆盖或 `Win+D` 逻辑。
- 不增加新的 Flutter UI 依赖，不制作安装包。

## 完成条件

- [x] Windows 桌面组件窗口区域是至少三块圆角区域的并集，而不是整块矩形。
- [x] 卡片间和底部空白点击可穿透到桌面。
- [x] 设置页、加载/空/错误状态和置顶小窗恢复完整窗口。
- [x] 三张磁贴仍完整显示，滚动或数据刷新后裁形同步更新。
- [x] 暗/亮虚构数据 Golden 可读，无 RenderFlex overflow。
- [x] Flutter format、analyze、test 与 Windows Release 构建通过。
- [x] 根目录 EXE 重启后进程数量、8000 端口与 `/health` 正常。

## 验证证据

- 实际 Release 窗口的 `GetWindowRgn` 返回复杂区域，纵向中心线只命中
  `9–151`、`162–338`、`349–589` 三段；两处 10px 间隙和 `590–679` 底部空白均不属于
  Quota Watch 窗口区域。
- 实机 `WindowFromPoint` 探针确认卡片间隙和底部空白不再命中 Quota Watch HWND；
  Windows 会把这些位置的输入继续交给下层窗口。
- Flutter 路由回归确认桌面首页上报 3 个区域；进入设置页时清空裁形并恢复完整窗口，
  返回首页后重新上报 3 个区域。
- 暗/亮 Golden 均使用虚构数据；三张磁贴、状态圆点、百分比、进度条和重置时间可读，
  没有 overflow。
- `flutter analyze` 无问题，Flutter **50 tests**、后端 **413 passed**，
  Windows desktop-widget Release 构建成功。
- 根目录 `启动 Quota Watch.exe` 已重启；前端、launcher、8000 端口监听各 1 个，
  `/health=ok`。运行窗口仍为无 owner 的普通非置顶顶层窗口。

## 学习点

- 视觉透明与渲染透明不是一回事：窗口裁形可以让桌面穿过空白区域，同时不改变 Flutter
  渲染表面的合成模式。
- Flutter 负责测量真实卡片矩形，MethodChannel 传递几何数据，Win32 负责最终窗口区域；
  这是一次“UI → 平台通道 → 原生窗口 → 实机验证”的完整纵切片。

# 阶段 11 任务卡：桌面悬浮窗自治与视觉修正

> 遵循 `AGENTS.md` 任务流程。本卡覆盖一次对话中确认的四项高价值改动与四项视觉/性能修正，
> 目标：悬浮窗"放着不管也始终可信"。

## 目标

桌面悬浮（`DisplayMode.desktopWidget` / seamless）模式下：

1. 数据自动刷新（5 分钟定时）+ 倒计时/时间文案每分钟随时间推进。
2. 刷新失败保留上次卡片，错误缩小为列表顶部一条可点击提示；卡片显示"更新于 HH:mm"。
3. 悬浮态提供鼠标可用入口：hover 卡片浮现刷新 / 隐藏到托盘 / 切回置顶小窗按钮；整张卡片可拖动。
4. seamless 模式跳过无效的 `BackdropFilter`（Flutter 模糊不到桌面壁纸，纯 GPU 浪费）。
5. 悬浮卡在壁纸上加强分离感：边框 alpha 提升 + 极淡投影。
6. 原生区域下发加脏检查：regions 未变化不走 MethodChannel（当前每次 build 与每帧滚动都调度）。
7. 内容溢出时悬浮窗可见可拖的滚动条：检测 `maxScrollExtent > 0` 时包 `Scrollbar`，并把该区域并入原生窗口区域（平时保持卡片间隙点击穿透）。
8. 圆角 18 收敛为 `AppTheme.cardRadius` 单一常量（`quota_card.dart`、`home_page.dart`、原生通道参数三处共用）。

## 上下文

- 相关文件：`quota_watch/lib/app/state/quota_state.dart`、`lib/presentation/pages/home_page.dart`、`lib/presentation/widgets/quota_card.dart`、`lib/presentation/widgets/quota_window_block.dart`、`lib/app/theme/app_theme.dart`、`lib/app/desktop/window_drag_area*.dart`。
- 模型已有未接线的 `isStale()`（`quota_models.dart:329`），本次失败保留 + "更新于"正好补上这条链路。
- Flutter SDK：`E:\Move\flutter`；测试命令见下方。

## 允许范围

- 上述六个文件 + `quota_watch/test/` 内新增/修改测试 + `docs/` 本卡与 `LEARNING_LOG.md` 证据。
- 新增可见中文（"更新于"、"刷新"、"隐藏到托盘"、"切换置顶小窗"、错误提示条）后须运行
  `scripts/build_font_subset.ps1` 重建 Web 字体子集；失败则如实报告。

## 非目标

- 不改后端、不碰凭据、不改托盘菜单与 `desktop_controller_io.dart` 的窗口层级逻辑。
- 不做 `layoutMode` 误触发网络重查（`quota_state.dart:122`）与设置持久化——留作后续卡。
- 不改普通窗口（alwaysOnTop）与 Web 的既有布局。

## 完成条件

- `dart format`、`flutter analyze`、`flutter test` 全部通过；新增测试覆盖：
  reload 失败保留旧数据、seamless 卡片无 BackdropFilter、hover 控制出现、整卡拖动区存在、
  seamless 显示"更新于"。
- 悬浮模式手动冒烟：自动刷新触发、断后端时旧卡保留且出现错误提示条、hover 三按钮可用、
  整卡可拖动、卡片间隙仍可点击穿透。

## 学习点

- `AsyncValue.copyWithPrevious`：刷新/失败时保留上次数据的 Riverpod 标准手法。
- Flutter `BackdropFilter` 只模糊自身 surface：跨进程"真玻璃"需要原生合成，理解平台边界。
- Windows 窗口区域（HRGN）同时决定可见性与命中测试：点击穿透与滚动条的取舍是同一把尺子。

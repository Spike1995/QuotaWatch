# 阶段 12 任务卡：悬浮窗"无感"化（紧凑行 + 半透明 + 闲置淡出）

> 遵循 `AGENTS.md` 任务流程。承接阶段 11。用户已明确选择：方案 B（紧凑单行 + 悬停展开）
> + 方案 A（半透明降存 + 状态驱动着色）+ 闲置淡出，三者打包。

## 背景约束

- Flutter 桌面无法对壁纸做真模糊，"无感"只能靠缩小面积、降低不透明度、减少彩色。
- 原生窗口尺寸不变（360×680 / 1120×340），点击穿透区域跟随卡片矩形自动缩小——
  无需改 `desktop_controller_io.dart` 的窗口层级逻辑。

## 目标

1. **紧凑行（B）**：seamless 卡片平时收成单行（约 36–40px 高）：小 logo + 服务商名 +
   主窗口"已用 X%" + 细进度条 + 状态圆点。hover 时原地展开为阶段 11 的完整卡片
   （含 hover 控制按钮、"更新于"），移开收回。展开/收起用 AnimatedSize（约 150ms）。
2. **半透明降存（A）**：seamless 面板色加 alpha（约 0.65），边框降到 0.12，去掉阶段 11
   加的投影；正常状态（充足）的百分比与圆点用 muted/outline 色，只有告警/紧张/耗尽/
   错误才用彩色。紧凑行进度条 3–4px 高，正常状态同样 muted。
3. **闲置淡出**：鼠标离开悬浮卡区域约 500ms 后整窗不透明度降到 0.45，进入立即恢复 1.0。
   `DesktopController` 接口加 `setOpacity`（io 走 `windowManager.setOpacity`，web no-op）。
   切回置顶小窗 / 页面销毁时恢复 1.0。hover 恢复要立即，淡出要防抖，避免卡片间隙
  穿越时闪烁。

## 允许范围

- `quota_watch/lib/presentation/pages/home_page.dart`、`widgets/quota_card.dart`、
  `widgets/quota_window_block.dart`（仅必要时）、`app/desktop/desktop_controller.dart`、
  `desktop_controller_io.dart`、`desktop_controller_web.dart`、`app/theme/app_theme.dart`（仅常量）、
  `quota_watch/test/`、`docs/`（本卡 + LEARNING_LOG）。
- 新增可见中文才需要重建字体子集；本次尽量复用现有文案（"已用 X%"等已有）。

## 非目标

- 不改窗口尺寸/定位/托盘；不改普通窗口与 Web 布局；不改后端与凭据；不做壁纸亮度自适应。

## 完成条件

- format / analyze / test 全绿；新增测试覆盖：seamless 默认渲染紧凑行、hover 展开为完整卡、
  移开收回；正常状态不着彩色（muted）；DesktopController.setOpacity 存在且 web 为 no-op。
- golden（compact_glass_tile）按新视觉重建并目检。
- 手动冒烟（用户验收）：日常三条紧凑行、hover 展开、离开约半秒淡出、告警状态变色。

## 学习点

- "无感"是信息密度的取舍：单行只留决策必需字段（谁、用多少、要不要管），细节交给 hover。
- 整窗 opacity 是原生合成器能力，与 Flutter 内 alpha 是两层；命中区域不变，淡出不影响点击。

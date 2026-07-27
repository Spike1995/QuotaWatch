# Stage 9 / 紧凑玻璃磁贴任务卡

> 日期：2026-07-24
> 状态：已完成并验证

## 目标

把当前 Windows 桌面小组件改成高信息密度的半透明磁贴界面：

- 360×680 的右侧竖向信息条中优先完整展示 Codex、Kimi、GLM 三个订阅。
- 宽屏继续把三张订阅磁贴排成长横条，保持 Web 与调试窗口的响应式能力。
- 每个额度窗口只显示统一名称、`已用 X%`、进度条和重置时间。
- 不再显示“已用 / 剩余 / 上限”三列数值。

## 当前证据

- 当前桌面窗口为 340×520，首页还有较高的总览卡，三张订阅卡需要明显滚动。
- 服务端原始标签同时包含 `5 小时窗口`、`周窗口`、`Weekly limit`、`5h limit`
  等中英文表达。
- `QuotaWindowBlock` 同时渲染百分比和“已用 / 剩余 / 上限”三列，信息重复。
- Win32 桌面层、`Win+D`、托盘恢复和 launcher 已通过验收，不能因视觉改版回退。

## 设计方向

- 采用 `ui-ux-pro-max` 推荐的高密度 Bento + Modern Dark 组合。
- 页面使用深色环境渐变；磁贴使用半透明表面、细描边和轻量模糊。
- 正文与次要文字保持足够对比度，不使用大面积低透明文字。
- 动效只保留 200～300ms 的轻量反馈；进度条尊重系统“减少动态效果”设置。
- 半透明只作用于 Flutter 内部磁贴，不启用 Windows 原生透明窗口，不修改已验收的
  desktop z-order、owner、topmost 或 Shell 层级逻辑。

## 允许范围

- `quota_watch/lib/presentation/pages/home_page.dart`
- `quota_watch/lib/presentation/widgets/`
- `quota_watch/lib/app/theme/app_theme.dart`
- Windows 小组件逻辑尺寸
- 对应 Flutter Widget/响应式测试、任务卡、学习日志和交接文档

## 非目标

- 不修改 Provider 请求、解析器、额度百分比语义或后端契约。
- 不显示、记录或截图真实额度值与原始服务响应。
- 不修改托盘、单实例、静默启动和 `Win+D` 的 Win32 实现。
- 不制作安装包，不增加新的字体或第三方 UI 依赖。

## 完成条件

- [x] 360×680 窄窗呈现三张纵向玻璃磁贴，无 RenderFlex overflow。
- [x] 700px 以上按两列、1100px 以上按三列形成横向磁贴。
- [x] 常见中英文窗口标签统一为“时间/用途 + 额度”。
- [x] 每个窗口只保留名称、`已用 X%`、进度条和重置时间。
- [x] “已用 / 剩余 / 上限”三列从首页和复用窗口块中移除。
- [x] 加载、空数据、未配置和错误状态仍可读、可重试。
- [x] Flutter format、analyze、test 和 Windows release build 通过。
- [x] 实际 launcher 重启后健康检查、进程数量和桌面视觉检查通过。

## 验证证据

- `flutter analyze`：无问题。
- `flutter test`：48 项全部通过，包含 360×680 首屏几何测试和暗/亮玻璃磁贴 Golden。
- 后端完整回归：412 项全部通过。
- Windows Release：按 `desktop_widget + backend + all_real` 构建成功。
- 根目录 EXE 实际启动：前端、launcher、后端各 1 个，`/health=ok`。
- Golden 只使用虚构数据；没有读取、保存或截图真实额度。
- 字体子集重新生成后补齐“周五”等字形；脚本现在跳过源字体不支持的注释符号，并在成功前
  保留上一版可用字体。

## 用户反馈修订：提高磁贴透明度

- 初版玻璃层偏实。暗色磁贴不透明度由约 70% 降至约 48%，亮色由约 85% 降至约 65%。
- 去掉磁贴底色与渐变重复叠加，避免两层半透明表面合成后再次接近不透明。
- 背景模糊从 14 提高到 18，并略增强描边和页面环境渐变；文字、图标和进度条继续使用原有
  高对比颜色，没有整体降低 opacity。
- 仍只调整 Flutter 内部磁贴；Windows 原生窗口底色、桌面层、托盘和 `Win+D` 逻辑未改。
- 修订后暗/亮 Golden、`flutter analyze`、全部 48 项 Flutter 测试和 Windows Release
  构建通过；根目录 EXE 已重新启动，前端、launcher、8000 端口监听各 1 个且
  `/health=ok`。

## 用户反馈修订：桌面组件去除应用栏

- `desktopWidget` 模式不再显示 `Quota Watch` 标题、设置、最小化和关闭按钮，三张磁贴从画布
  顶部 8px 内边距直接开始。
- 设置、显示/隐藏和退出仍由托盘菜单承担；切换回 `alwaysOnTop` 置顶小窗时应用栏自动恢复，
  不会让普通窗口永久失去控制入口。
- `DesktopController` 新增可监听的显示模式，Flutter 页面会随托盘模式切换即时重建，不依赖
  启动时的编译常量猜测当前模式。
- 新增模式切换 Widget 回归和 360×680 顶部几何断言；暗/亮 Golden 更新后只使用虚构数据。
- `flutter analyze` 无问题，全部 **49 项** Flutter 测试和 Windows Release 构建通过；根目录
  EXE 已重新启动，前端、launcher、8000 端口监听各 1 个且 `/health=ok`。
- Windows 原生桌面层和后端契约未修改。

## 学习点

- 这张卡位于“需求与验收标准 → Flutter UI/语义 → Widget 测试 → Windows 构建与实机
  验收”的交付链，不改变后端数据契约。
- 半透明不是把所有元素一起降低 opacity；应让表面透明、文字保持高对比。
- 原始接口标签属于数据事实，界面显示名属于表现层；在 UI 格式化层统一文案可以避免改坏
  Provider 解析与离线契约测试。

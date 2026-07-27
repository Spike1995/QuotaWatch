# Stage 11 / Windows 开机自启动与默认桌面组件任务卡

## 目标

在 Quota Watch 的设置页增加 Windows“开机时自动启动”开关，并让 Windows
桌面版每次启动时默认进入“桌面悬浮插件”模式。

本卡位于完整交付链的“系统集成与启动体验”环节：设置页产生用户选择，
Flutter MethodChannel 把选择交给 Windows runner，runner 写入当前用户的
登录启动项，已有根目录 GUI 启动器继续负责后端、前端与退出清理。

## 当前上下文

- 根目录 `启动 Quota Watch.exe` 已能无终端窗口地启动完整桌面运行链。
- Flutter Windows runner 已有 `quota_watch/window` MethodChannel。
- 当前 Windows 默认显示模式仍是“置顶小窗”，托盘可手动切换模式。
- 仓库存在其他未提交工作，本卡不整理或覆盖无关变更。

## 允许范围

- Windows runner 的当前用户启动项读写。
- 设置页的自启动状态、开关、忙碌态与失败提示。
- Windows 默认显示模式。
- 对应的 Dart Widget 测试、Windows 源码守卫测试与文档证据。

## 不做

- 不要求管理员权限，不写入全局机器启动项。
- 不把 Provider Key、原始响应或额度值写入启动项。
- 不制作安装器，不承诺仓库移动后旧路径仍然有效。
- 不改变 Web、Android 的启动行为。
- 不移除托盘中的“置顶小窗”手动切换入口。

## 完成条件

- Windows 设置页能读取、开启和关闭当前用户的开机自启动。
- 启动项只指向根目录 GUI 启动器；关闭后对应值被移除。
- 无根目录启动器或原生调用失败时，设置页给出可见错误且开关回滚。
- Windows 启动默认进入桌面悬浮插件；Web/Android 保持普通应用行为。
- Widget 测试覆盖成功开关与失败回滚，源码测试覆盖注册表边界和默认模式。
- `dart format`、`flutter analyze`、Flutter 测试、后端测试和 Windows build
  按风险完成验证。

## 学习点

- Windows 登录启动项保存的是“如何启动程序”，不是正在运行的进程状态。
- MethodChannel 负责把 Flutter UI 意图跨到 Win32；注册表写入只留在原生层。
- “开关显示成功”和“下次实际登录后启动成功”是两类证据，最终仍需一次
  用户登录后的人工验收。

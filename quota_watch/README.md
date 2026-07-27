# Quota Watch Flutter 前端

当前产品固定显示 Codex / Kimi / GLM 真实额度；界面统一只保留已用百分比、进度条和重置时间。
设置页支持安全配置 Kimi / GLM Key、Codex 手动重置次数备注，以及自动 / 竖向 / 横向三种磁贴
布局。Windows 与 Android 使用同一套 Flutter UI；Android 是可信后端的伴随端，不携带 Provider
Key 或 Python 后端。

日常打开请直接双击仓库根目录的 [`启动 Quota Watch.exe`](../启动%20Quota%20Watch.exe)。它会
自动启动本地后端并以 `backend + all_real` 打开 Windows 桌面悬浮窗；旧的 `.cmd` 保留为 Edge
开发入口。launcher 使用 Windows GUI subsystem，双击时不会显示终端窗口；失败时会弹出错误提示。
当前 launcher 依赖完整仓库，不是可单独分发的安装包。

桌面模式默认使用 360×680 的半透明玻璃磁贴小组件，停在当前显示器右上角并隐藏任务栏按钮。
设置页选择“横向”后窗口改为 1120×340 长横条；“竖向”保持右侧单列，“自动”按可用宽度使用
1～3 列。Provider 的中英文原始标签统一显示成“时间/用途 + 额度”。它位于 Windows
桌面层之上、普通应用之下：最大化应用会覆盖它，按 `Win+D` 显示桌面时它仍然存在。托盘右键可
切换“置顶小窗”（显示任务栏按钮并始终位于应用之上）或“桌面悬浮插件”（回到真正桌面层），
也可显示、打开数据设置或退出。即使当前模式已经勾选，再点一次也会恢复之前收起的窗口；托盘
“显示”和重复双击 launcher 同样会唤醒已有实例，不会生成第二个窗口或第二个托盘图标。

## 数据模式

- 生产前端固定通过 `BackendQuotaRepository` 请求
  `http://127.0.0.1:8000/api/v1/quotas`；样本数据只保留在离线测试 helper 中。
- 右上角设置页可以在本次运行期间切换真实场景和后端地址。
- `codex_real` 只在 backend 模式可选；后端须以 `QUOTA_WATCH_CODEX_REAL=1` 启动。
- `kimi_real` / `glm_real` 的 Key 可在 loopback 设置页安全输入，后端写入 Windows Credential
  Manager；输入框在请求结束后立即清空，不持久化、不回显。
- 远程后端必须是 HTTPS；安全配置写接口只允许 loopback，不应暴露到局域网或公网。
- `all_real` 只在 backend 模式可选；并发查询各自已开启的服务，未开启项显示 `unknown`。

也可以通过编译参数设置初始值：

```powershell
& E:\Move\flutter\bin\flutter.bat run -d edge `
  --dart-define=QUOTA_SCENARIO=all_real `
  --dart-define=QUOTA_BACKEND_URL=http://127.0.0.1:8000 `
  --dart-define=QUOTA_LAYOUT_MODE=auto
```

## Android

应用 ID 为 `com.quotawatch.app`，最低 Android API 24。正式/远程后端必须使用 HTTPS；Android
Network Security Config 只给 `127.0.0.1` 与 `localhost` 放行明文 HTTP。

真机通过 USB 调试连接本机后端：

```powershell
# 先启动 D:\APPDEsign\启动 Quota Watch.exe，让本机后端健康。
& D:\Android\sdk\platform-tools\adb.exe reverse tcp:8000 tcp:8000
& E:\Move\flutter\bin\flutter.bat run -d <设备ID> `
  --dart-define=QUOTA_BACKEND_URL=http://127.0.0.1:8000
```

`adb reverse` 很重要：它让手机的 `127.0.0.1:8000` 安全映射到开发电脑，而不需要把无鉴权本地
后端监听到局域网。Android 客户端不会保存 Provider Key；日常配置应在运行后端的 Windows 电脑上
完成。

构建 Debug APK：

```powershell
& E:\Move\flutter\bin\flutter.bat build apk --debug
```

按 CPU 架构拆分的 Release 体积更接近日常安装包：

```powershell
& E:\Move\flutter\bin\flutter.bat build apk --release --split-per-abi
```

当前 Android 模板的 Release 仍使用 debug signing config，只适合本机安装验收；公开分发前必须
配置独立发布签名。已验证的 arm64-v8a 包约 17.9 MB，Debug 通用包因同时包含三种 ABI 和调试符号
约 140.8 MB，不能用后者代表最终程序体积。

## 主要目录

```text
lib/
├── app/
│   ├── router/              页面路由
│   ├── state/               Riverpod 设置、Repository 和异步状态
│   └── theme/               全局主题
├── data/
│   ├── codecs/              统一 JSON 解码
│   ├── models/              额度契约与非敏感配置状态
│   └── repositories/        额度 / 安全配置 HTTP 实现与地址策略
└── presentation/
    ├── pages/               首页、详情页、设置页
    └── widgets/             卡片、进度条、总览组件
```

## 页面状态

首页已经覆盖加载、正常、空数据、未配置、部分失败、全部失败、后端不可达、超时和 HTTP 503。单家失败不会隐藏其他服务商结果。

## 验证

```powershell
& E:\Move\flutter\bin\flutter.bat pub get
& E:\Move\flutter\bin\flutter.bat analyze
& E:\Move\flutter\bin\flutter.bat test
& E:\Move\flutter\bin\flutter.bat build web --release
& E:\Move\flutter\bin\flutter.bat build windows --release
& E:\Move\flutter\bin\flutter.bat build apk --debug
```

完整的前后端启动和端到端检查见仓库根目录 [README](../README.md)。

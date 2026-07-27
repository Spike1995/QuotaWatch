# Quota Watch

Quota Watch 是一个 Flutter + FastAPI 全栈学习项目，用统一界面展示 Codex、Kimi 和 GLM Coding
Plan 额度。Windows 版本是普通应用可覆盖、`Win+D` 后仍存在的桌面磁贴；同一套 Flutter UI 也已
适配 Android 伴随端。

Codex 可通过本机官方 `codex app-server` 读取；Kimi 已通过官方 Kimi Code usages 接口完成代码、
自动验证和脱敏真实结构读取。GLM 的默认关闭适配器与三家综合模式也已实现；在用户另行确认本机实验
边界后，GLM 完成了脱敏真实结构检查，并修复了会丢失每周窗口及反转百分比方向的字段契约漂移。
当前可直接返回 5 小时、每周和月度工具调用三个窗口，三项服务端 `percentage` 均按已用比例显示；
数值一致性仍由用户在 ZCode 官方页面做最终对照。所有真实
路径仍只在本机后端显式开启，不代表已获得公开或商业化使用许可。

## 当前架构

```text
Flutter UI + Riverpod
        ↓ QuotaRepository
BackendQuotaRepository
        ↓ HTTP / JSON
本地 FastAPI
        ├─ 显式开启：本机 codex app-server → account/rateLimits/read
        ├─ 环境变量或 Windows 凭据：Kimi Code 官方 HTTPS → /coding/v1/usages
        ├─ 环境变量或 Windows 凭据：GLM 官方插件契约 → /api/monitor/usage/quota/limit
        └─ all_real：并发查询各自已显式开启的服务

Android Flutter 客户端
        ↓ HTTPS，或 USB adb reverse → 127.0.0.1:8000
可信 Windows FastAPI（凭据仍留在 Windows）
```

## 一键启动（推荐）

Windows 桌面模式直接双击仓库根目录的 [`启动 Quota Watch.exe`](启动%20Quota%20Watch.exe)：

```powershell
Set-Location D:\APPDEsign
& '.\启动 Quota Watch.exe'
```

启动器是 Windows GUI 程序，日常双击不会再打开终端窗口。若依赖、端口或启动流程失败，会显示一个
简短错误框，并把脱敏诊断信息写入 `%TEMP%\quota-watch-launcher`；日志不会记录 Key 或额度原始响应。

桌面模式默认把 360×680 的半透明玻璃磁贴小组件放在当前显示器右上角并隐藏任务栏按钮。三家订阅
在窄窗中纵向排列；设置页也可切换为 1120×340 长横条或自动响应式布局。每个额度窗口只显示统一
名称、`已用 X%`、进度条和重置时间。它位于 Windows
桌面层之上、普通应用之下：最大化应用会覆盖它，按 `Win+D` 显示桌面时它仍然存在。托盘右键可
切换“置顶小窗”（显示任务栏按钮并始终位于应用之上）或“桌面悬浮插件”（回到真正桌面层），
也可显示、进入数据设置或退出。即使当前模式已经勾选，再点一次也会恢复之前收起的窗口；托盘
“显示”和重复双击启动器同样会唤醒已有实例，不会创建第二个窗口。

启动器会依次检查依赖、在后台启动 FastAPI、等待健康检查，再以
`backend + all_real + http://127.0.0.1:8000` 打开 Windows 桌面悬浮窗。它会把已有的 Kimi/GLM 环境变量
只临时映射给本次后端子进程，不打印变量值、不写 `.env`，也不修改用户级环境变量。Flutter 结束后，
启动器只停止它自己创建的后端。旧的 [`启动 Quota Watch.cmd`](启动%20Quota%20Watch.cmd) 保留为
Edge 开发入口。

当前 launcher exe 是“仓库内一键入口”，依赖本仓库的 `backend/.venv`、PowerShell 脚本和
`quota_watch/build/windows/.../Release`，不能单独复制到另一台电脑；可分发安装包属于后续 Stage 9
打包任务。需要重新生成入口时运行：

```powershell
& .\scripts\build_windows_launcher.ps1
```

若 8000 端口已经运行 Quota Watch，启动器会安全复用它；但旧进程不会获得后来新增的环境变量，此时
先停止旧后端再重新双击即可。若端口属于其他程序，启动器会报错退出，不会结束对方进程。

排查时可使用：

```powershell
# 只检查依赖、端口和凭据是否存在，不启动应用
& '.\启动 Quota Watch.exe' -ValidateOnly

# 在独立端口完成纯离线启动/健康/响应/清理烟雾测试
& '.\启动 Quota Watch.exe' -SmokeTest -BackendPort 18080

# 日常启动，但本次不启用 GLM
& '.\启动 Quota Watch.exe' -DisableGlm
```

Flutter 桌面前端不接触 Key，也不负责创建 Python；因此“一键”入口仍由外部 launcher 管理两类进程。
下面的手动流程保留作学习和故障排查备用。

## 设置页安全配置

桌面组件模式隐藏了顶部栏，可从托盘右键选择“数据设置”。Kimi / GLM Key 的推荐录入路径是：

1. 后端地址保持 `http://127.0.0.1:8000`；
2. 在“本机账户与密钥”中填写配置标签和新 Key；
3. 点击“安全保存”；输入框会在请求成功或失败后立即清空；
4. Key 只写入当前 Windows 用户的 Credential Manager，接口只返回“是否已配置”和来源，不回显
   Key。

Codex 不接受在此粘贴 Token，仍使用官方本机登录。Codex 的“可重置次数 + 到期时间”是明确标注的
本机手动备注：当前官方本机 credits 契约没有这两个字段，程序不会把手动值伪装成 Provider 返回。
环境变量仍优先于 Windows 凭据；由环境变量管理的 Key 不能在设置页覆盖或删除。

## 打开应用并查看 Codex 实际额度

先在第一个 PowerShell 窗口启动后端：

```powershell
Set-Location D:\APPDEsign\backend
$env:QUOTA_WATCH_CODEX_REAL = '1'
& .\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

再在第二个 PowerShell 窗口启动 Flutter：

```powershell
Set-Location D:\APPDEsign\quota_watch
& E:\Move\flutter\bin\flutter.bat run -d edge
```

在应用右上角打开设置：

1. 数据来源选择“本地 FastAPI”。
2. 后端地址保持 `http://127.0.0.1:8000`。
3. 数据场景选择“Codex 真实额度（本机）”。
4. 点击“应用并返回”，之后首页刷新会重新读取。

不需要一直打开 Codex 桌面端或 CLI。只需本机 Codex 已经登录；每次查询时，后端会短暂启动官方
app-server，读取额度后立即关闭。停止应用时，在两个终端分别按 `Ctrl+C`。

如果自动找不到 `codex.exe`，可在启动后端前指定它的**绝对路径**：

```powershell
$env:QUOTA_WATCH_CODEX_COMMAND = 'C:\完整路径\codex.exe'
```

该变量是程序路径，不是 Key。不要把 token、Cookie 或 `auth.json` 内容填进项目。

## 打开应用并查看 Kimi 实际额度

先在 [Kimi Code Console](https://www.kimi.com/code/console) 创建 Kimi Code API Key。Key 只显示一次，
不要粘贴到对话、代码、`.env`、截图或 Git。日常使用首选上一节的设置页安全保存；下面的环境变量
方式只保留给自动化和故障排查。

在第一个 PowerShell 窗口安全输入 Key 并启动后端：

```powershell
Set-Location D:\APPDEsign\backend
$kimiSecureKey = Read-Host 'Kimi Code API Key' -AsSecureString
$env:QUOTA_WATCH_KIMI_API_KEY = [Net.NetworkCredential]::new('', $kimiSecureKey).Password
$env:QUOTA_WATCH_KIMI_REAL = '1'
Remove-Variable kimiSecureKey
& .\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

使用隐藏输入是为了避免把 Key 明文写进 PowerShell 历史。随后按上面的 Flutter 启动命令打开应用，
在设置中选择“本地 FastAPI → Kimi 真实额度（本机）”。Kimi 软件不需要保持打开；后端刷新时直接
请求官方额度接口。

停止后端后，在同一 PowerShell 窗口清除变量：

```powershell
Remove-Item Env:QUOTA_WATCH_KIMI_API_KEY -ErrorAction SilentlyContinue
Remove-Item Env:QUOTA_WATCH_KIMI_REAL -ErrorAction SilentlyContinue
```

## 查看 Codex + Kimi 综合实际额度

在同一个后端 PowerShell 窗口中，按上文安全设置 Kimi Key，然后在启动后端**之前**同时设置：

```powershell
$env:QUOTA_WATCH_CODEX_REAL = '1'
$env:QUOTA_WATCH_KIMI_REAL = '1'
Remove-Item Env:QUOTA_WATCH_GLM_REAL -ErrorAction SilentlyContinue
& .\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

在设置页选择“本地 FastAPI → 综合实际额度（本机）”。该场景会同时查询已开启的 Codex 和 Kimi；
GLM 因未开启而显示“真实查询未启用”，不会发出 GLM 请求。环境开关只在后端启动时读取，因此修改
开关后需要重启后端。这一步把“只能看一家”改成一个综合入口，同时保留每家的独立授权边界。一键
启动器会根据可用的本机环境变量分别开启 Kimi/GLM，并默认进入该综合场景。

GLM Adapter 只接受后端专用的 `QUOTA_WATCH_GLM_API_KEY` 与 `QUOTA_WATCH_GLM_REAL=1`，不会读取
ZCode、开发 worker 配置文件或 Flutter 中的凭据。一键启动器可按用户授权把已有 `GLM_API_KEY`
临时映射成项目变量。ZCode 仍只作为“使用统计 → 编程套餐”的人工对照；项目不读取其私有存储。
这条本机实验路径默认关闭，不得直接扩展成公开或商业服务。

## 后端真实场景与离线验证

产品 UI 已删除假额度场景，只保留四个真实查询入口：

| 场景 | 行为 |
|---|---|
| `codex_real` | 仅在显式开关开启时读取本机 Codex；Kimi/GLM 显示当前场景未查询 |
| `kimi_real` | 使用项目环境变量或 Windows 凭据查询 Kimi；其余两家不查询 |
| `glm_real` | 使用项目环境变量或 Windows 凭据查询 GLM；兼容当前/历史契约 |
| `all_real` | 并发查询已开启或已有安全凭据的服务；未启用项显示 `unknown` |

健康检查：`http://127.0.0.1:8000/health`；接口文档：`http://127.0.0.1:8000/docs`。
确定性的失败、空数据和契约漂移场景只存在于离线自动测试，不会混入真实产品页面或截图。

## Android 伴随端

Android 应用 ID 为 `com.quotawatch.app`，最低 API 24。APK 不包含 Python 后端和 Provider Key；
正式远程后端只允许 HTTPS。USB 真机调试时可让设备的 loopback 安全映射到电脑：

```powershell
& D:\Android\sdk\platform-tools\adb.exe reverse tcp:8000 tcp:8000
& E:\Move\flutter\bin\flutter.bat run -d <设备ID> `
  --dart-define=QUOTA_BACKEND_URL=http://127.0.0.1:8000
```

这样做是为了避免把当前无远程认证的本地 FastAPI 监听到局域网。Key 仍应在运行后端的 Windows
设置页录入；Android 只查看额度。

## 轻量化边界

- 日常 Windows 运行链保持 4 个关联进程：GUI 监督启动器、Flutter、venv `pythonw` 引导和实际
  Python；没有常驻 PowerShell、`cmd` 或 `conhost`。本轮最终 5 秒采样约 232 MB 工作集、
  179 MB 私有内存，CPU 增量在采样精度内为 0 ms。
- 当前 Windows Release 完整目录约 32 MB；图标字体在发布构建中已 tree-shake。
- Android 开发只安装命令行 SDK/JDK/必要 NDK，不安装 Android Studio 或模拟器；这些是构建工具，
  不进入 APK，也不随 Quota Watch 常驻。
- 不通过关闭 Defender、更新、索引、动画或调整系统服务换取数字上的“轻量”；这能避免破坏安全性
  与已验收的桌面行为。

## 验证命令

```powershell
Set-Location D:\APPDEsign
& .\backend\.venv\Scripts\python.exe -m pytest -c backend\pytest.ini backend\tests
python .\scripts\run_e2e.py

Set-Location D:\APPDEsign\quota_watch
& E:\Move\flutter\bin\flutter.bat analyze
& E:\Move\flutter\bin\flutter.bat test
& E:\Move\flutter\bin\flutter.bat build windows --release
& E:\Move\flutter\bin\flutter.bat build web --release
& E:\Move\flutter\bin\flutter.bat build apk --debug
```

自动测试不会启动任何真实 Provider 查询。真实行为检查只验证响应状态、窗口数量与安全字段，禁止把
个人额度、账户信息或原始响应保存到日志、截图、Fixture 或 Git。

详细路线见 [学习计划](docs/VIBE_CODING_LEARNING_PLAN.md)，本次任务见
[Codex 任务卡](docs/STAGE6_CODEX_REAL_TASK.md)、[Kimi 任务卡](docs/STAGE6_KIMI_REAL_TASK.md)、
[GLM 与综合模式任务卡](docs/STAGE7_GLM_REAL_AND_ALL_REAL_TASK.md)和
[一键启动任务卡](docs/STAGE8_ONE_CLICK_LAUNCHER_TASK.md)；GLM 漂移修复见
[GLM 契约修复任务卡](docs/STAGE8_GLM_CONTRACT_DRIFT_FIX_TASK.md)，完成证据见
[学习日志](docs/LEARNING_LOG.md)。

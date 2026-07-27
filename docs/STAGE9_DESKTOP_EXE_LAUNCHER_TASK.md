# Stage 9 / Windows EXE 一键启动任务卡

> 状态：代码与自动验证完成，待用户双击做功能验收
>
> 用户目标：继续 Stage 9，并确认能否通过 EXE 一键启动本地后端与 Windows 桌面前端。

## 目标

把已经验证的启动链扩展为 Windows 桌面入口：

```text
启动 Quota Watch.exe
  → 调用仓库内 PowerShell 启动器的 -Desktop 模式
  → 检查本地 Python、release 前端和端口
  → 安全映射已有环境变量并启动 FastAPI
  → 健康检查通过后启动 quota_watch.exe
  → 用户从托盘退出后，只清理本入口创建的后端
```

这张卡位于“本地运行与 Windows 产品化”层，连接构建产物、进程生命周期和真实数据链，不修改
Provider 协议、额度解析或页面数据模型。

## 允许范围

- 给 `scripts/start_quota_watch.ps1` 增加 `-Desktop` 模式。
- 新增可审查的轻量 C# 启动壳与本机构建脚本。
- 在仓库根目录生成 `启动 Quota Watch.exe` 供当前 Windows 主机双击。
- 增加离线测试，验证桌面程序调用、后端健康等待、退出码和自有进程清理。
- 更新 README、学习日志和 Stage 9 交接文档。

## 非目标

- 不把 Python、虚拟环境或 Flutter 运行库塞进单个 EXE。
- 不制作安装包、不注册开机自启、不修改注册表。
- 不让 Flutter EXE 读取、保存或传递 Kimi/GLM Key。
- 不在自动测试中调用真实 Provider。
- 不强制结束已有 Quota Watch 后端或占用端口的其他程序。

## 安全与架构边界

- `启动 Quota Watch.exe` 只是可审查的入口壳；凭据映射仍只发生在
  `start_quota_watch.ps1` 创建后端子进程之前。
- 前端仍只请求 `http://127.0.0.1:8000`，后端仍只监听回环地址。
- 当前 EXE 依赖本仓库中的 `backend/.venv`、PowerShell 脚本和 Windows release 构建目录；
  它不是可单独复制到另一台电脑的安装包。
- 桌面模式使用编译时默认端口 8000；自定义端口仍使用开发启动模式，直到前端增加安全的运行时配置。

## 完成条件

- [x] `-Desktop -ValidateOnly` 能检查 release 前端而不要求 Flutter CLI。
- [x] 桌面模式能完成“后端启动 → 健康检查 → 前端启动 → 前端退出 → 自有后端清理”。
- [x] 轻量启动壳可从源码在本机重新生成，并把参数传给 PowerShell 启动器。
- [x] 根目录生成的 EXE 可完成离线验证，且输出中不出现测试 Key。
- [x] 启动器专项测试、后端完整测试、Flutter analyze/test 和 Windows release build 通过。
- [x] README 与学习日志准确区分“当前仓库内一键 EXE”和“后续可分发安装包”。

## 验证记录

- 启动器专项：`9 passed`，覆盖编译入口壳、参数转交、端口保护、后端健康等待、假桌面前端与清理。
- 后端完整回归：`405 passed`。
- Flutter：格式化完成，`flutter analyze` 无问题，`flutter test` 45 项通过。
- Windows release：以 `QUOTA_DISPLAY_MODE=desktop_widget` 重新构建成功。
- 根目录 `启动 Quota Watch.exe -ValidateOnly` 通过；用户实际页面与托盘交互验收仍待完成。
- 启动体验后续已由 `STAGE9_SILENT_EXE_LAUNCHER_TASK.md` 收口为 Windows GUI subsystem，
  双击不显示终端窗口。

## 学习点

- 为什么前端程序、启动器和安装包是三个不同的交付物。
- 为什么进程生命周期必须明确“谁创建、谁等待、谁清理”。
- 为什么凭据留在后端启动边界，比嵌入桌面前端更安全。
- 为什么双击成功仍需用离线失败/清理路径证明启动链可靠。

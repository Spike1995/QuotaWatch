# Stage 9 / 无终端窗口 EXE 启动任务卡

> 状态：代码与自动验证完成，待用户双击做视觉确认
>
> 用户目标：双击 `启动 Quota Watch.exe` 时只显示桌面悬浮窗，不再出现终端窗口。

## 目标

把已有控制台启动壳改成 Windows GUI 启动壳：

```text
启动 Quota Watch.exe（GUI subsystem，无控制台）
  → 隐藏运行 start_quota_watch.ps1 -Desktop
  → 后端健康后显示 Flutter 桌面窗
  → 启动失败时弹出错误框并指向临时诊断日志
```

这张卡位于 Windows 启动体验层，不修改 Provider、数据契约、前端页面或凭据映射。

## 允许范围

- 修改 `QuotaWatchLauncher.cs` 的进程窗口与错误处理。
- 把 C# 编译目标从 console EXE 改为 Windows GUI EXE。
- 捕获 PowerShell 的安全状态输出，仅在失败时写入系统临时目录。
- 更新启动器测试、README、交接文档和学习日志。

## 非目标

- 不隐藏 Flutter 桌面窗口。
- 不吞掉启动失败；失败必须有可操作提示。
- 不把 Key、Provider 原始响应或实际额度写入日志或弹窗。
- 不改变后端端口、Provider 超时或当前进程清理规则。
- 不制作安装包或开机自启。

## 完成条件

- [x] 生成的 PE subsystem 是 Windows GUI，而不是 Console。
- [x] PowerShell 使用 `CreateNoWindow` 和隐藏窗口模式。
- [x] 正常启动仍完成后端健康、桌面前端和退出清理链。
- [x] 错误时显示安全提示，并仅把脱敏启动信息写入 `%TEMP%\quota-watch-launcher`。
- [x] 启动器专项测试和根目录 EXE 离线烟雾测试通过。
- [x] 启动壳源码与二进制均不包含任何凭据变量名或秘密值。

## 学习点

- PE 的 Console/Windows GUI subsystem 决定双击时是否自动创建终端窗口。
- 隐藏终端不能等于隐藏错误；GUI 程序需要单独的失败反馈通道。
- 前端窗口、启动器窗口和后端进程是三类独立生命周期。

## 验证记录

- 启动器专项：`9 passed`，包含现场编译和完整离线生命周期。
- 测试读取临时构建 PE 头：`IMAGE_SUBSYSTEM_WINDOWS_GUI (2)`。
- 根目录 `启动 Quota Watch.exe`：subsystem=2，离线 smoke exit code=0，测试端口已释放。
- `QuotaWatchLauncher.cs` 与生成 EXE 的凭据变量名扫描均为 0。
- 尚待用户亲自双击确认：只出现 Flutter 桌面窗，不出现终端窗。

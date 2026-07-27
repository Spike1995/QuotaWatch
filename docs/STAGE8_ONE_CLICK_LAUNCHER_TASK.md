# 阶段 8 / 一键启动 Quota Watch 任务卡

> 状态：完成；用户确认一键启动、Codex 与 Kimi 正常，GLM 数值问题已转独立修复卡
>
> 用户授权：直接实现并测试“一键启动 Quota Watch”。

## 目标

把当前需要两个 PowerShell 窗口的开发启动流程收敛成一个可双击入口：

```text
启动 Quota Watch.cmd
  → 检查 Python、Flutter 与目录
  → 把已有用户环境变量仅映射给本次后端子进程
  → 后台启动 FastAPI 并等待 /health
  → 用 backend + all_real 参数启动 Flutter Edge
  → Flutter 结束后只停止本启动器创建的后端
```

这张卡位于交付链的“本地运行与产品化体验”层，不修改额度解析、Provider 请求协议或 Flutter 页面。

## 当前问题

- Flutter Web 运行在浏览器中，网页本身不能启动本机 Python 进程。
- 手动启动容易漏掉环境变量映射、后端重启或 `all_real` 初始参数。
- 现有 `scripts/run_e2e.py` 是测试工具：启动固定端口、运行检查后立即退出，不适合作为日常入口。

## 允许范围

- 新增 `scripts/start_quota_watch.ps1`。
- 新增仓库根目录双击入口 `启动 Quota Watch.cmd`。
- 启动器可临时读取以下已有环境变量，但绝不打印其值：
  - Kimi：优先 `QUOTA_WATCH_KIMI_API_KEY`，回退 `KIMI_CODING_API_KEY`。
  - GLM：优先 `QUOTA_WATCH_GLM_API_KEY`，回退 `GLM_API_KEY`。
- 只把映射值传给新启动的 FastAPI 子进程，不修改用户级环境变量、不写 `.env`。
- 提供离线 `-ValidateOnly` 与 `-SmokeTest` 参数，供自动测试使用。
- 更新 README、学习日志与 AGENTS 当前状态。

## 非目标

- 不把后端改成 Windows 服务或开机启动项。
- 不打包安装程序，不发布 Web 公共后端。
- 不修改、打印、保存或提交任何 Key、额度值、账号资料或原始供应商响应。
- 自动测试不调用 Codex、Kimi 或 GLM 真实额度接口。
- 不强制结束已经占用端口的现有进程；已有 Quota Watch 后端只复用，不归启动器管理。

## 安全与生命周期设计

- 后端固定绑定 `127.0.0.1`，不监听局域网。
- 启动前验证端口：若是现有 Quota Watch 后端则复用；若是其他程序则安全失败。
- 新后端使用隐藏窗口；日志只写入系统临时目录，不记录 Key 或原始响应。
- Key 只在启动子进程前短暂进入启动器的进程环境，子进程创建后立即恢复原值。
- Kimi/GLM 只有在发现相应 Key 时才开启；Codex 日常模式默认开启。
- `-SmokeTest` 强制关闭全部真实 Provider，只查询 `normal` 离线场景。
- `finally` 只停止本脚本持有的后端 PID；复用的后端不会被停止。

## 完成条件

- [x] 双击入口能调用 PowerShell 启动器。
- [x] 启动器能验证依赖、端口与环境变量存在性，但不输出秘密。
- [x] 日常模式自动启动 FastAPI，等待健康后启动 Flutter Edge，并默认选择 `all_real`。
- [x] Kimi/GLM 的已有环境变量只临时映射给后端子进程。
- [x] 已有 Quota Watch 后端可安全复用；非 Quota Watch 端口占用会失败且不结束对方进程。
- [x] `-SmokeTest` 在独立端口完成“启动 → 健康 → 三家离线响应 → 停止”。
- [x] 自动测试覆盖 Validate、离线生命周期、端口冲突和双击入口连线。
- [x] 后端完整 pytest、Flutter analyze/test 与 Web build 通过。
- [x] Playwright 确认构建后的 Flutter Web 能打开并进入稳定渲染状态。
- [x] 秘密扫描、任务文件空白检查和 diff 审查通过。

## 验证记录

- 启动器专项测试：6 passed，覆盖 Validate、离线生命周期、已有后端复用、无关端口保护、
  CMD 连线和日常模式参数传递。
- 最新完整回归（含 GLM 漂移修复）：后端 431 passed；Flutter 45 passed；Dart format、Flutter analyze、Web Release build、
  Python compileall 与 pip check 均通过。
- Playwright 在独立静态服务器打开 Release 构建并等待稳定渲染；人工检查离线证据截图，中文字体、
  三卡布局和部分失败状态可读。
- 用户停止旧手动后端后，真实双击等价入口已启动新 FastAPI；`/health` 返回 `ok`，Dart/Flutter
  进程运行。未读取、打印或截图实际 Provider 额度。

## 学习点

- 为什么浏览器页面不能直接启动本机进程，但外部启动器可以。
- 为什么“自动启动”还必须明确谁创建、谁停止进程。
- 为什么 Key 可以安全地只传给子进程，而不写进项目配置文件。
- 为什么烟雾测试必须强制使用离线场景，不能因为测试启动器而消耗真实额度。

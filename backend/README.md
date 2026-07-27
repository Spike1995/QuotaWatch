# Quota Watch 本地后端

这个 FastAPI 服务只提供 Codex、Kimi、GLM 真实额度的本机归一化查询，不再向产品 UI 返回假场景。
Codex 通过官方本机 `codex app-server`；Kimi / GLM 使用项目专用环境变量，或由用户在 loopback
设置页写入 Windows Credential Manager 的 Key。后端不读取 CLI/worker/ZCode 私有配置，不返回
Key、原始 Provider 响应或账号资料。

## 一键启动

日常使用不需要手动开两个终端。在仓库根目录双击 `启动 Quota Watch.exe`，GUI 启动器会静默启动
本服务、等待 `/health`，然后打开 Windows 桌面组件；`.cmd` 保留为 Edge 开发入口。Provider
Adapter 仍支持 `QUOTA_WATCH_*` 项目变量；启动器可把已有的 `KIMI_CODING_API_KEY` 或
`GLM_API_KEY` 仅临时映射给新建后端子进程，不打印、不持久化，也不修改用户级变量。

如果 8000 端口已有本项目后端，启动器只复用而不接管；环境变量变化后应先停止旧进程再重新启动。
手动启动方式保留作排查备用。

## 安装与离线测试

```powershell
Set-Location D:\APPDEsign\backend
py -3.12 -m venv .venv
& .\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
& .\.venv\Scripts\python.exe -m pytest -c pytest.ini tests
```

## 启动本地后端

```powershell
Set-Location D:\APPDEsign\backend
& .\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

- 健康检查：`http://127.0.0.1:8000/health`
- 接口文档：`http://127.0.0.1:8000/docs`
- 综合额度：`http://127.0.0.1:8000/api/v1/quotas?scenario=all_real`
- 安全配置状态：`http://127.0.0.1:8000/api/v1/credential-profiles`

只支持 `codex_real`、`kimi_real`、`glm_real`、`all_real`。单家未启用时返回结构化 503；
`all_real` 始终返回稳定的三家列表，未启用项为 `unknown`。

## 设置页安全配置

- `GET/PUT/DELETE /api/v1/credential-profiles` 只接受 loopback 客户端。
- Kimi / GLM Key 写入 Windows Credential Manager，目标名为 `QuotaWatch/Kimi`、
  `QuotaWatch/GLM`。
- `%LOCALAPPDATA%\QuotaWatch\credential_profiles.json` 只保存非敏感标签与 Codex 手动备注，
  使用临时文件 + `os.replace` 原子更新。
- 响应模型没有 `apiKey` 字段；安全配置的 422 错误也不会回显被拒绝的输入。
- 环境变量优先于凭据管理器；设置页保存成功后无需重启后端即可查询。删除本机凭据后，如环境变量
  仍存在，Provider 仍保持启用。
- Codex 不接受手动 Token。设置页的 Codex “账户”只是本机显示标签；认证继续由官方 Codex 登录
  负责。

## 启动 Codex 真实额度

```powershell
Set-Location D:\APPDEsign\backend
$env:QUOTA_WATCH_CODEX_REAL = '1'
& .\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

查询地址：`http://127.0.0.1:8000/api/v1/quotas?scenario=codex_real`。

前提是本机已安装并登录 Codex；Codex GUI/CLI 不必保持打开。每次请求的流程是：

```text
FastAPI → 启动 codex app-server → JSONL initialize/initialized
        → account/rateLimits/read → 归一化 ProviderQuota → 关闭子进程
```

自动发现失败时，可在启动前用 `QUOTA_WATCH_CODEX_COMMAND` 指定 `codex.exe` 的绝对路径。
该变量不接受参数或 shell 命令串。

## 启动 Kimi 真实额度

首选方式：打开 Quota Watch 设置页，在“本机账户与密钥”中输入 Kimi Key。输入只短暂停留在
Flutter 控制器和 loopback 请求中，请求结束即清空，落盘由 Windows Credential Manager 完成。

环境变量方式仍保留给自动化或已有启动流程：

```powershell
Set-Location D:\APPDEsign\backend
$kimiSecureKey = Read-Host 'Kimi Code API Key' -AsSecureString
$env:QUOTA_WATCH_KIMI_API_KEY = [Net.NetworkCredential]::new('', $kimiSecureKey).Password
$env:QUOTA_WATCH_KIMI_REAL = '1'
Remove-Variable kimiSecureKey
& .\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

查询地址：`http://127.0.0.1:8000/api/v1/quotas?scenario=kimi_real`。生产代码固定请求官方
`https://api.kimi.com/coding/v1/usages`，不接受地址覆盖、不跟随重定向、不设置自定义 User-Agent。
停止后端后可清除 `QUOTA_WATCH_KIMI_API_KEY` 与 `QUOTA_WATCH_KIMI_REAL`。

## 综合实际额度

查询地址：`http://127.0.0.1:8000/api/v1/quotas?scenario=all_real`。

综合模式复用三家各自的启用状态，不另设总开关。Codex 仍使用启动时环境开关；Kimi / GLM 只要
存在有效项目环境变量或 Windows 安全凭据即可查询。设置页新增/删除安全凭据会在下一次请求立即
生效，不需要重启后端。

## GLM 默认关闭适配器

`glm_real` 使用项目专用变量 `QUOTA_WATCH_GLM_API_KEY` 和 `QUOTA_WATCH_GLM_REAL=1`，固定请求官方
插件所用的 HTTPS quota endpoint。代码与离线 HTTP 替身已验证；在用户另行确认风险并授权本机
实验后，第一次脱敏检查暴露了当前契约漂移：真实响应有三个窗口，而旧解析器只产生两个。修复后
脱敏复验得到 5 小时、每周、工具调用三个百分比窗口及重置字段；用户无数值方向对照进一步确认三项
`percentage` 都是已用比例，不能取反。检查未记录额度值、套餐、Key 或原始
响应。这不等于获得第三方公开监控许可。ZCode 仅作为用户人工核对界面；后端不读取其私有数据库、
缓存、Token、Cookie、日志或网络流量。

## Provider 模块

| 模块 | 职责 |
|---|---|
| `base.py` | `ProviderAdapter` 协议和统一异常 |
| `aggregator.py` | 并行查询、单家失败隔离、最后成功缓存和过期提示 |
| `codex_app_server.py` | 默认关闭的 Codex 官方本地 app-server 只读适配器 |
| `kimi_adapter.py` | 默认关闭、固定官方主机的 Kimi Code 真实只读适配器 |
| `kimi_parser.py` | Kimi 官方源码衍生契约的解析 |
| `glm_adapter.py` | 默认关闭、固定官方插件 quota endpoint 的 GLM 实验性只读适配器 |
| `glm_parser.py` | GLM 官方插件衍生契约的离线解析 |
| `credential_profiles.py` | Windows Credential Manager + 非敏感原子元数据 |

Codex/Kimi 真实 Adapter 已完成自动验证和脱敏结构读取；GLM Adapter 与 `all_real` 已完成离线
验证及一次用户授权的脱敏结构检查。自动测试只使用 HTTP 替身与 fixture。

## 安全边界

- 真实 Codex 默认关闭，只监听启动命令指定的 `127.0.0.1`。
- 只调用官方本地 `account/rateLimits/read`；不调用 `wham/usage` 等内部网页端点。
- 不读取、解析、打印或返回 `auth.json`、OAuth token、Cookie、账号资料或原始 JSON。
- 子进程使用参数数组和 `shell=False`，有超时及确定性清理。
- Flutter 不接触 Codex 登录状态。用户主动输入的 Kimi / GLM Key 只通过 loopback 请求短暂停留在
  内存中，请求完成即清空；不进偏好设置、日志、截图、测试或 Git。
- Kimi Adapter 从 `QUOTA_WATCH_KIMI_API_KEY` 或 Windows Credential Manager 读取；一键启动器可
  按用户授权把现有 `KIMI_CODING_API_KEY` 只复制到后端子进程，不读取客户端配置文件。
- Kimi 请求固定官方 HTTPS 主机、禁重定向、限制响应大小，错误正文不进入日志或前端。
- GLM Adapter 从 `QUOTA_WATCH_GLM_API_KEY` 或 Windows Credential Manager 读取；一键启动器可
  按用户授权把现有 `GLM_API_KEY` 只复制到后端子进程，不读取 ZCode 或 worker 配置文件。
- GLM 请求固定官方插件使用的 HTTPS 主机、禁重定向、8 秒超时和 1 MiB 上限；真实开关默认关闭。
- 所有自动化测试保持离线；真实检查必须单独显式开启并只报告脱敏结构结果。
- 安全配置 API 只允许 loopback；远程 Android 后端必须另行设计 TLS 与认证，不能直接开放写接口。

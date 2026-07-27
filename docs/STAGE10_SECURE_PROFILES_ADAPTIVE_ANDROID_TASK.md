# 阶段 10：安全配置、横竖布局与 Android 伴随端

> 日期：2026-07-25
> 状态：自动验证完成，等待用户 Windows / Android 可见验收

## 目标

在不回退现有 Windows 桌面组件、托盘、真实额度查询和一键启动能力的前提下，完成三个可独立验收的纵向切片：

1. 用户可以在 Quota Watch 设置页手动配置 Kimi / GLM Key；Key 仅进入本机后端和 Windows 凭据管理器，Flutter 不持久化、不回显。
2. 用户可以选择自动、竖向、横向三种磁贴布局；三家卡片共用一套克制的蓝灰玻璃底色，只用小面积品牌色帮助识别。
3. Codex 卡片可以显示“可重置次数 + 到期时间”；当前官方本机契约未提供这两个字段时，只接受并明确标注本机手动记录，不能伪装成官方返回。
4. 生成 Android 工程并让同一套 Flutter UI 可运行；Android 只连接用户指定的可信后端，不保存三方 Provider Key。

本卡位于完整交付链的“设置 UI → 安全配置 API → 动态 Provider 凭据解析 → 统一额度契约 → 响应式 UI → Windows / Android 构建验证”。

## 开始前上下文

- Windows 后端通过 `QUOTA_WATCH_*_REAL` 环境开关和项目专用环境变量查询真实 Provider。
- Codex 使用官方本机 app-server，不能读取或复制 `auth.json`。
- Kimi / GLM Key 目前只能在启动前设置环境变量，Flutter 设置页没有安全录入入口。
- Windows 桌面组件固定为 360×680，首页仅按宽度自动换列。
- 当前 Codex app-server JSON Schema 的 credits 只有 `hasCredits`、`unlimited`、`balance`；没有重置次数或其到期时间。
- 本机尚未安装 Android SDK，先生成工程、完成静态与 Widget 验证；APK 构建必须等 SDK 可用后才可标记通过。

## 允许范围

- `backend/app/`、`backend/tests/`
- `quota_watch/lib/`、`quota_watch/test/`
- `quota_watch/android/` 与 Flutter 工程清单
- 本任务卡、API 研究、学习日志和交接文档
- 为 Android 本地开发补充不含秘密的连接说明

## 非目标

- 不读取 ZCode、Codex、Kimi 或 GLM 客户端的私有存储、Cookie、流量或登录文件。
- 不把 Provider Key 写入 Flutter、SharedPreferences、日志、测试、截图或 Git。
- 不把本地 FastAPI 直接暴露为无鉴权的公网服务。
- 不声称手动填写的 Codex 重置次数来自官方接口。
- 不在本卡内实现账号密码登录、OAuth Token 导入或云同步。

## 切片 A（30–120 分钟）：本机安全配置

### 完成条件

- 后端提供只允许 loopback 调用的配置读写 API。
- Kimi / GLM Key 写入 Windows Credential Manager；API 响应只返回 `configured`、标签和来源，不返回 Key。
- 环境变量继续受支持；请求时动态解析，不要求重启后端。
- 设置页保存成功后立即清空 Key 输入框；删除配置可回退环境变量。
- 覆盖非 loopback 拒绝、换行/超长 Key 拒绝、响应不泄露、原子元数据写入和动态解析测试。

### 学习点

- UI 输入框不是安全存储；真正的边界在后端进程与 OS 凭据库。
- “配置成功”和“Provider 查询成功”是两个不同的可观察结果。

## 切片 B（30–120 分钟）：布局、配色与重置元数据

### 完成条件

- 设置页可选择自动、竖向、横向布局。
- 竖向为单列；横向为不压缩内容的水平卡片条；自动模式保持现有断点行为。
- Windows 桌面组件按所选布局调整窗口目标尺寸，切换或托盘恢复后不丢失。
- 卡片背景、边框、阴影和进度条使用统一语义色；品牌色仅用于 Logo / 小面积标识。
- Codex 额度契约支持独立可选的 `resetAllowance`（`count`、`expiresAt`、`source`），避免在官方 credits 缺失时伪造“已用完”；手动记录在 UI 和语义树中均有来源标识。
- 覆盖三种布局几何、credits 新字段解析/文案和窄屏无 overflow 测试。

### 学习点

- “响应式”负责自动适配，“布局偏好”负责用户选择，两者不能混为一谈。
- 可选契约字段必须从后端、解析器、模型、UI 和测试贯通。

## 切片 C（30–120 分钟）：Android 伴随端

### 完成条件

- Flutter 工程含 Android 平台目录和网络权限。
- Android 启动时跳过 Windows 窗口 / 托盘插件初始化。
- 移动端可以选择可信后端地址并查看三家额度；远程明文 HTTP 地址给出明确安全限制。
- Provider Key 配置入口只在 loopback 后端可用，移动端不会本地保存 Key。
- `flutter analyze`、全部 Widget / 单元测试通过；有 Android SDK 时再以 `flutter build apk --debug` 作为构建证据。

### 学习点

- Android 是同一产品的另一个客户端，不等于把桌面后端和凭据一起塞进 APK。
- “工程生成成功”“静态检查成功”“APK 构建成功”“真机连接成功”是四层不同证据。

## 回归与最终验收

```powershell
backend\.venv\Scripts\python.exe -m pytest -c backend\pytest.ini backend\tests
python scripts\run_e2e.py
E:\Move\flutter\bin\flutter.bat analyze
E:\Move\flutter\bin\flutter.bat test
E:\Move\flutter\bin\flutter.bat build windows --release
E:\Move\flutter\bin\flutter.bat build web --release
E:\Move\flutter\bin\flutter.bat build apk --debug
```

最后一条只有 Android SDK 配置完成后才可能通过；若本机工具链仍缺失，必须如实记录为外部前置条件，不能用其他测试替代。

## 完成证据（2026-07-25）

- Windows Credential Manager 临时条目写入/读取/删除 smoke 通过，临时条目已经删除。
- 后端完整测试：`426 passed`。覆盖 Key 不回显、畸形输入清洗、非 loopback 拒绝、环境变量优先、
  保存后动态启用、Codex Token 拒绝、手动重置来源、缓存不被污染和删除回退。
- `flutter analyze`：`No issues found!`；Flutter 全部 `62 tests` 通过。
- 暗/亮 Golden 重新生成并目视检查；Web Edge E2E 使用独立内存凭据库和临时端口通过，截图只含
  三家未配置状态，不含个人额度或 Key。
- Windows Release 与 Web Release 构建成功；最新版根目录启动器健康检查为 `ok`，重复双击后仍为
  1 个前端、1 个 launcher、1 个端口监听和两级 Python，共 4 个关联进程，无常驻终端宿主。
- Android command-line SDK/JDK/NDK 安装完成；`flutter build apk --debug` 前台命令成功。
  APK 校验：`applicationId=com.quotawatch.app`、`minSdk=24`、声明 `INTERNET`，包内
  Network Security Config 的 base 明文为关闭，仅 `127.0.0.1` / `localhost` 例外。
- 按 ABI 的 Release 体积证据：armeabi-v7a 15.4 MB、arm64-v8a 17.9 MB、x86_64 19.3 MB。
  当前模板仍使用 debug signing config，只用于本机验收，不是正式发布签名。
- `flutter doctor -v` 已识别 API 36、Build Tools 36.0.0 与 JDK 17；仍提示有额外 Android
  licenses 未接受，但 Debug/Release 构建均已成功。许可证接受属于用户选择，不由任务自动代签。
- Android 首次 Release 构建遇到一次 Maven TLS handshake 中断，Flutter 自动重试后成功；后续
  依赖已进入 Gradle 缓存。SDK XML v4/工具 v3 的兼容警告不影响本次 APK 产出，后续升级
  Flutter/Android Gradle Plugin 时再统一消除。

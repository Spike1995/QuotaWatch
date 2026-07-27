# Stage 10 交接：安全配置、横竖布局与 Android 伴随端

> 日期：2026-07-25  
> 状态：实现完成；最终构建与用户实机验收见本文末尾。

## 1. 交付结果

### 1.1 本机安全配置

- 设置页可以录入 Kimi / GLM Key。Flutter 只在输入控件和一次 loopback 请求中短暂持有明文，
  请求成功或失败后都会清空；响应契约没有 Key 字段。
- 后端只允许 loopback 访问 `GET/PUT/DELETE /api/v1/credential-profiles`，Kimi / GLM Key
  写入 Windows Credential Manager 的 `QuotaWatch/Kimi`、`QuotaWatch/GLM`。
- `%LOCALAPPDATA%\QuotaWatch\credential_profiles.json` 只保存非敏感标签和 Codex 手动备注，
  使用同目录临时文件 + `os.replace` 原子替换。
- 环境变量优先于凭据管理器；凭据管理器的值按请求动态解析，保存后无需重启后端。
- Codex 继续使用官方本机登录，设置页拒绝 Token。当前 Codex app-server credits 契约没有
  重置次数或活动到期字段，因此这里只允许保存并显示明确标记为“手动记录”的次数与到期时间。
- 手动重置备注通过复制 `ProviderQuota` 合并，不修改 Provider/聚合器持有的缓存对象；清除备注后
  不会从失败回退缓存中复活。

### 1.2 布局、配色与透明磁贴

- 设置页提供“自动适配 / 竖向 / 横向”三种布局：
  - 自动：随可用宽度使用 1～3 列；
  - 竖向：360×680 右侧单列；
  - 横向：1120×340 长横条，窄屏使用水平滚动而不压扁卡片。
- 切换布局后，Windows 桌面窗口立即调整尺寸；托盘恢复和显示模式切换会重放所选尺寸。
- 卡片统一使用蓝灰玻璃底、语义安全绿和亮/暗模式可读的告警色；Provider 品牌色只用于 Logo
  和小面积识别。桌面磁贴表面保持真实 alpha，区域外仍为透明桌面。
- 额度正文统一为“已用 X% + 进度条 + 重置时间”，不恢复“已用/剩余/上限”重复行。

### 1.3 Android 伴随端

- Flutter 工程新增 Android 平台，应用 ID/namespace 为 `com.quotawatch.app`，最低 API 由当前
  Flutter 模板管理；Manifest 声明 `INTERNET`。
- Android 启动时跳过 Windows 窗口、托盘和拖动行为；使用普通应用栏。
- 客户端地址策略只允许远程 HTTPS，HTTP 只允许 `localhost`、`::1` 和合法 `127/8` loopback。
  Android Network Security Config 的 base 明文策略为关闭，只给 `127.0.0.1` 与 `localhost`
  开例外。
- APK 不包含 Python 后端或 Provider Key。USB 真机开发使用
  `adb reverse tcp:8000 tcp:8000`；远程多用户使用前必须另做 TLS、认证、授权和密钥托管。
- 本机只安装 Android 命令行 SDK、JDK 17、API 36、Build Tools、Platform Tools 和 Flutter
  固定 NDK；没有安装 Android Studio 或模拟器。Gradle daemon 关闭，最大堆从模板 8 GiB 下调到
  4 GiB。

## 2. 数据流与安全边界

```text
Windows 设置页输入 Key
  → Flutter 内存中的 password TextField
  → HTTP PUT 127.0.0.1
  → FastAPI loopback 校验 + SecretStr
  → Windows Credential Manager
  → 下一次 Provider 查询动态解析

Android / Windows 查看额度
  → BackendQuotaRepository
  → 可信后端 /api/v1/quotas
  → Provider 归一化
  → ProviderQuota + 可选 resetAllowance
  → 半透明磁贴
```

严禁把 Key、Token、Cookie、`auth.json`、原始 Provider 响应或个人额度写入测试、日志、截图和
Git。Android 不承担凭据托管；当前 loopback 配置 API 不得监听到局域网或公网。

## 3. 轻量化结论

- Windows 日常运行仍为 4 个关联进程：GUI 监督启动器、Flutter、venv `pythonw` 引导和实际
  Python；没有常驻 PowerShell、`cmd` 或 `conhost`。
- 本轮最终真实启动 5 秒采样：总工作集约 232 MB、总私有内存约 179 MB、CPU 增量为采样
  精度内 0 ms；数值会随 Flutter 页面和
  Windows 内存回收波动，不把单次下降当作新的性能承诺。
- Windows Release 完整目录约 32 MB；Material/Cupertino 图标字体在 Web Release 中分别
  tree-shake 约 99%。
- 已把安装完成后不再需要的 JDK 与 Android command-line tools 两个压缩包移入回收站，释放约
  330 MB；已安装工具不受影响，删除仍可从回收站恢复。
- 没有关闭 Windows Defender、更新、索引、动画、电源策略或其他系统服务，也没有用强制工作集
  回收制造虚假的低内存数字。

## 4. 主要文件

- 后端安全存储：`backend/app/credential_profiles.py`
- 配置与额度 API：`backend/app/main.py`
- 统一契约：`backend/app/models.py`
- 设置页安全面板：`quota_watch/lib/presentation/widgets/credential_profiles_panel.dart`
- 地址策略：`quota_watch/lib/data/repositories/backend_endpoint_policy.dart`
- 布局与窗口尺寸：`quota_watch/lib/presentation/pages/home_page.dart`、
  `quota_watch/lib/app/desktop/desktop_controller_io.dart`
- 主题与卡片：`quota_watch/lib/app/theme/app_theme.dart`、
  `quota_watch/lib/presentation/widgets/quota_card.dart`
- Android：`quota_watch/android/`
- 研究与任务卡：`docs/API_RESEARCH.md`、
  `docs/STAGE10_SECURE_PROFILES_ADAPTIVE_ANDROID_TASK.md`

## 5. 自动验证

- `backend\.venv\Scripts\python.exe -m pytest ...`：**426 passed**。
- `flutter analyze`：**No issues found**；`flutter test`：**62 passed**。
- 暗/亮 Golden 已重新生成并目视检查；安全 Edge E2E 通过：
  `docs/evidence/2026-07-25-stage10-safe-all-real.png`。
- `flutter build windows --release`、`flutter build web --release`、前台
  `flutter build apk --debug` 均成功。
- Debug 通用 APK：
  `quota_watch/build/app/outputs/flutter-apk/app-debug.apk`，140.8 MB，
  SHA-256 `55065E263AFE06408CE10414E615D81BBA2608977A8476C08F527C73944F4529`。
  它包含三种 ABI 与调试符号，不代表最终安装体积。
- `flutter build apk --release --split-per-abi` 自动重试一次 Maven TLS 下载后成功：
  armeabi-v7a 15.4 MB、arm64-v8a 17.9 MB、x86_64 19.3 MB。当前 Gradle 模板以 debug key
  签名 release，只能本机验收，正式分发必须单独配置签名。
- APK 反查确认 `com.quotawatch.app`、minSdk 24、非 debuggable 的 arm64 Release、只含
  `INTERNET`（另有 AndroidX 动态接收器保护权限），并内置三种 ABI 各自正确的原生库。
- 最终根目录 EXE 实际重启：`/health=ok`、8000 端口 1 个监听、重复双击前后均为 4 个关联
  进程、前端/launcher 各 1 个、无 PowerShell/cmd/conhost。
- `flutter doctor -v` 已识别 Android API 36、Build Tools 36.0.0 和 JDK 17；仍有额外许可证
  未接受，但本轮 Debug/Release 均已构建。许可证接受保留给用户本人。
- 最终范围内密钥模式扫描无命中；没有读取或截图真实额度。

## 6. 用户验收（自动测试不能替代）

1. 从托盘进入“数据设置”，用自己的 Kimi 或 GLM Key 保存一次；确认输入框清空、状态变为
   “Windows 凭据管理器”，回到 `all_real` 后该卡片能刷新。不要把 Key 发给任何 AI。
2. 保存 Codex 手动重置次数与到期时间；确认卡片显示“手动记录”，清除后立即消失。
3. 分别切换竖向和横向；确认桌面窗口尺寸、托盘恢复、普通应用覆盖和 `Win+D` 行为都保持正确。
4. Android 真机开启 USB 调试，执行 `adb reverse` 后安装/运行 APK；确认三家卡片可查看，且
   Android 没有要求把 Provider Key 保存到手机。

当前不把“APK 构建成功”写成“真机已验收”；后者必须由用户在自己的设备上完成。

# Quota Watch — 前端项目

> AI Coding Plan 额度查询器 / Flutter 前端
> 当前阶段：**阶段 0（把已有阶段 1 UI 草案补齐脚手架并运行验证）**
> 当前数据策略：**阶段 0～5 只用 Mock、Fixture 和本地 FastAPI 假接口；真实额度 API 延后**
>
> 完整学习与工程路线见 [`../docs/VIBE_CODING_LEARNING_PLAN.md`](../docs/VIBE_CODING_LEARNING_PLAN.md)，
> 学习证据记录在 [`../docs/LEARNING_LOG.md`](../docs/LEARNING_LOG.md)。

---

## 🚀 安装 Flutter SDK 后的首次验证

```bash
cd D:\APPDEsign\quota_watch
flutter doctor -v        # 先确认工具链和目标平台
# 当前仓库缺少常见平台脚手架；保存基线后按目标平台执行 flutter create
flutter pub get          # 拉依赖（首次必跑）
flutter analyze          # 先发现编译/静态检查问题
flutter test             # 建立测试基线
flutter run -d chrome    # 在 Chrome 里跑起来
```

看到 `HomePage`（三家卡片列表） = 成功 🎉

如果 `flutter run` 找不到 Chrome，先 `flutter devices` 看看可用设备。

---

## 📁 项目结构（零基础必读）

```
quota_watch/
├── pubspec.yaml              ← 项目"清单"：依赖、资源声明
├── lib/
│   ├── main.dart             ← 入口（运行起点）
│   ├── app/
│   │   ├── theme/            ← 全局主题（颜色、字体）
│   │   │   └── app_theme.dart
│   │   └── router/           ← 路由（页面跳转）
│   │       └── app_router.dart
│   ├── data/                 ← 数据层（阶段 2 抽象 Repository，阶段 3 加 fixture）
│   │   ├── models/           ← 数据模型（前后端契约）
│   │   │   └── quota_models.dart
│   │   └── mock/             ← 模拟数据（阶段 1 用）
│   │       └── mock_data.dart
│   └── presentation/         ← 表现层（UI）
│       ├── pages/            ← 整页（首页、详情页）
│       │   ├── home_page.dart
│       │   └── detail_page.dart
│       └── widgets/          ← 可复用组件
│           ├── quota_card.dart
│           ├── quota_progress_bar.dart
│           └── summary_header.dart
```

### 这个结构叫"分层架构"，是工程界标准做法：

| 层 | 职责 | 改它会影响谁 |
|----|------|------------|
| **data** | 数据从哪来（假数据？API？） | 只影响数据来源，UI 不动 |
| **models** | 数据长什么样（字段定义） | 全局通用 |
| **presentation** | 用户看到什么（界面） | 只影响视觉 |
| **app** | 全局配置（主题、路由） | 全局风格 |

**为什么这样分？** 后续把 `MockQuotaRepository` 换成 Fixture Repository 或本地假后端 Repository 时，
UI 不需要了解数据究竟来自哪一层。真实服务商适配器更晚才加入。这就是分层的好处。

---

## 🎨 阶段 1 你能看到的 UI

**首页**（三家卡片列表）
- 顶部渐变总览条：显示跟踪了几个套餐
- 三张卡片：Codex / Kimi / GLM
- 每张卡片：logo + 套餐名 + 进度条（自动变绿/橙/红） + 重置倒计时
- GLM 卡片故意做成"接近耗尽"（38.5M/40M），触发橙色告警
- 下拉刷新（目前只刷新假数据）

**详情页**（点卡片进）
- 顶部品牌色大卡片：套餐名、订阅到期、更新时间
- 每个额度窗口一个 block：已用/剩余/上限 + 倒计时 + 备注

---

## 🧠 这阶段学到的 Dart / Flutter 知识点

打开任意一个 `.dart` 文件，文件开头都有注释解释重点。这里汇总：

1. **`enum`**（quota_models.dart）—— 枚举类型，比字符串安全（编译器查错）
2. **`class` + 命名参数 + `required`**（quota_models.dart）—— Dart 的构造函数语法
3. **`copyWith()` 模式** —— Flutter 改数据的标准做法（不可变）
4. **getter 派生属性**（`remaining`、`usedPercent`）—— 不用每次手算
5. **switch 表达式**（Dart 3 新语法）—— 比传统 switch 简洁
6. **`Scaffold` + `AppBar`** —— Material 页面骨架
7. **`ListView` + `RefreshIndicator`** —— 长列表 + 下拉刷新
8. **`InkWell` + `Card`** —— 可点击卡片（自带涟漪动画）
9. **`LinearProgressIndicator`** —— 进度条
10. **`Navigator.pushNamed`** —— 页面跳转

---

## 🔄 静态 UI → 真实数据的安全衔接

UI 继续只依赖 `ProviderQuota`，但正式产品不把 Kimi Key 写进 Flutter Web/移动端。推荐路径是：

```text
MockQuotaRepository
  → FixtureQuotaRepository（离线学习 JSON 和状态）
  → FastAPI /api/v1/quotas（本地假接口，不含 Key）
  → BackendQuotaRepository（Flutter 完成假数据端到端）
  → Codex 真实额度适配器（阶段 6）
  → Kimi / GLM 真实额度适配器（阶段 7）
```

阶段 3 先用自建 JSON fixture 学习数据与状态；阶段 4～5 用本地 FastAPI 假接口完成联调。
只有这个学习版验收通过后才接真实服务。这样 UI 仍无需知道第三方响应细节，也不会让鉴权问题干扰基础学习。

本地短期实验可以直连第三方 API，但不得提交、截图或部署真实 Key。

---

## 📝 已知 TODO（后面阶段处理）

- [ ] `app_router.dart` 用的是简化版手写路由，阶段 6 上线时换 `go_router` 包
- [ ] 当前缺少平台脚手架，需在保存现有文件后用 Flutter 工具补齐
- [ ] 尚未执行 `flutter analyze`，手写路由首先需要编译验证
- [ ] logo 是占位首字母，阶段 5 换真实 logo
- [ ] "设置页"还没建（阶段 5）
- [ ] 没有缓存（阶段 5 加 `shared_preferences`）
- [ ] 没有测试代码（阶段 1 建立模型与 Widget 测试基线）

# Stage 12 / 纯净生产运行环境任务卡

## 目标

在不改变 Flutter UI、Provider 行为和凭据边界的前提下，把 Python 开发环境与
生产运行环境分离。生产启动优先使用只含锁定运行依赖的
`backend/.venv-runtime`，开发测试继续使用 `backend/.venv`。

本卡位于瘦身路线的第一步：

`纯净发布环境 → 单家 Provider 迁入 Dart → 全部迁移 → 合并启动器`

## 当前证据

- Flutter Windows Release：约 32.08 MiB。
- `backend/.venv`：约 55.75 MiB。
- 开发环境包含 Pillow、pytest、Pygments 和 pip 等生产运行不需要的包。
- 启动脚本当前固定使用 `backend/.venv/Scripts/pythonw.exe`。

## 允许范围

- 增加锁定的生产依赖清单。
- 增加可重复创建和验证 `.venv-runtime` 的 PowerShell 脚本。
- 启动器优先选择 `.venv-runtime`，缺失时回退开发环境。
- 增加源码级安全守卫、运行验证和体积对比。
- 更新 `.gitignore` 与学习证据。

## 不做

- 不修改 Flutter 页面、布局、颜色或交互。
- 不迁移 Provider 业务逻辑；该工作从下一张任务卡开始。
- 不把 `.venv-runtime` 提交到 Git。
- 不把普通 Windows venv 宣称为可跨机器复制的完整安装包。
- 不读取、打印或复制任何 Provider Key。

## 完成条件

- 生产依赖全部锁定版本，且不包含 pytest、Pillow、Pygments 或 pip。
- 构建脚本只会重建精确的 `backend/.venv-runtime` 目录。
- 运行环境能导入 FastAPI、HTTPX、Uvicorn 和 Pydantic。
- 现有启动器在运行环境存在时优先使用它，在不存在时保持兼容回退。
- 后端全量测试、启动器专项测试和离线 Smoke Test 通过。
- 记录开发环境、纯净运行环境和完整运行链的体积差异。

## 学习点

- 开发依赖用于测试和构建；运行依赖才属于用户启动程序时需要的最小集合。
- “依赖更少”必须由独立环境启动和 Smoke Test 证明，不能只看
  `requirements.txt`。
- 本阶段减少磁盘占用，不会明显降低 Python 已启动后的内存；真正的内存瘦身
  需要后续把 Provider 迁入 Dart并移除 Python 进程。

# 字体资源说明

本目录存放 Quota Watch 随包使用的中文字体子集与许可证。

## 随包字体

| 文件 | 用途 |
|---|---|
| `NotoSansSC-QuotaWatchSubset.ttf` | 当前 UI 所需汉字的子集，发布包内置，保证离线中文显示 |
| `OFL-NotoSansSC.txt` | 字体许可证（SIL Open Font License 1.1） |

## 上游与许可证

- 上游字体：Noto Sans SC
  <https://github.com/google/fonts/tree/main/ofl/notosanssc>
- 许可证：SIL Open Font License 1.1，见 `OFL-NotoSansSC.txt`。

## 为什么只随包子集

Flutter Web 发布包默认只内置 Roboto，不含中文字形；依赖系统字体 fallback 在不同机器、
Edge 或离线环境下不可靠（实测中文显示为缺字方框）。因此把当前 UI 用到的唯一汉字从官方
Noto Sans SC 中抽取成一个小 TTF 随包发布，保证跨机器、离线一致。

**完整源字体（约 17 MB 的变量字体 `NotoSansSC-wght.ttf`）不入库**，只保存在本机临时目录。

## 何时需要重新生成子集

字体子集只包含生成时扫描到的字符。只要下列情况之一发生，就必须重新生成：

- 任何页面、组件、Fixture、后端响应中新增或修改了可见中文。
- 合并了包含新中文文字的分支。
- `quota_watch/lib/**`、`quota_watch/test/**`、`quota_watch/assets/fixtures/*.json`
  或 `backend/app/*.py` 中的可见文字发生变化。

## 重新生成命令

前置条件：本机临时目录下存在官方源字体 `NotoSansSC-wght.ttf`（约 17 MB，可从上游地址下载）。

```powershell
cd D:\APPDEsign
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File scripts\build_font_subset.ps1 `
  -SourceFont "C:\Users\wangz\AppData\Local\Temp\quota-watch-noto-source\NotoSansSC-wght.ttf"
```

脚本行为：

- 扫描 `quota_watch/lib/**`、`quota_watch/test/**`、`quota_watch/assets/fixtures/*.json`
  与 `backend/app/*.py`，提取唯一 Unicode 码点。
- 调用 Flutter 自带的 `font-subset.exe`（通过 stdin 输入码点）生成子集。
- 输出固定为 `NotoSansSC-QuotaWatchSubset.ttf`。
- 不修改、不复制、不提交完整源字体。

生成后需要重新执行 `flutter pub get`、Web 构建和端到端检查。

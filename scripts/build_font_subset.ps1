# ============================================================================
# build_font_subset.ps1 - 生成 Quota Watch 使用的 OFL 中文字体子集
# ----------------------------------------------------------------------------
# 为什么用随包子集：
#   Flutter Web 的 CanvasKit/HTML 发布版默认只随包自带 Roboto，不含中文字形。
#   发布到不同机器或 Edge 上时，系统字体 fallback 不可靠（实测方框缺字）。
#   因此把当前 UI 用到的唯一汉字从官方 Noto Sans SC 抽取成一个小 TTF 随包发布，
#   保证离线、跨机器显示一致。完整 17 MB 源字体不入库。
#
# font-subset.exe 的真实契约（已实测）：
#   font-subset.exe <output.ttf> <input.ttf>
#   Unicode 码点通过 stdin 输入，用空格分隔，并以换行结束。
#   不要把字符文本或码点作为第三个命令行参数。
# ============================================================================

[CmdletBinding()]
param(
    # 官方 Noto Sans SC 变量源字体（约 17 MB）。必填，脚本不得自行下载或假设位置。
    [Parameter(Mandatory = $true)]
    [string]$SourceFont,

    # Flutter 根目录，用于定位 font-subset.exe。默认使用本机安装位置。
    [string]$FlutterRoot = "E:\Move\flutter",

    # 仓库根目录。留空时由脚本主体依据 $PSScriptRoot 推导（param 块中 $PSScriptRoot 尚不可用）。
    [string]$RepoRoot = ""
)

# param 块执行后 $PSScriptRoot 才可用，这里补一个稳健默认值。
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

$ErrorActionPreference = "Stop"

# --- 1. 校验源字体 -----------------------------------------------------------
if (-not (Test-Path -LiteralPath $SourceFont -PathType Leaf)) {
    throw "Source font not found: $SourceFont`n下载上游：https://github.com/google/fonts/tree/main/ofl/notosanssc"
}
$sourceItem = Get-Item -LiteralPath $SourceFont
Write-Host "Source font : $($sourceItem.FullName) ($(($sourceItem.Length / 1MB).ToString('F1')) MB)"

# --- 2. 定位 font-subset.exe -------------------------------------------------
$fontSubset = Join-Path $FlutterRoot "bin\cache\artifacts\engine\windows-x64\font-subset.exe"
if (-not (Test-Path -LiteralPath $fontSubset -PathType Leaf)) {
    throw "font-subset.exe not found at: $fontSubset`n请确认 Flutter 根目录或先运行 'flutter precache --windows'。"
}
Write-Host "font-subset : $fontSubset"

# --- 3. 收集待扫描的 UTF-8 文本文件 ------------------------------------------
$scanRoots = @(
    "quota_watch\lib",
    "quota_watch\test",
    "quota_watch\assets\fixtures",
    "backend\app"
)
$fileFilters = @("*.dart", "*.json", "*.py")

$files = New-Object System.Collections.Generic.List[string]
foreach ($root in $scanRoots) {
    $absRoot = Join-Path $RepoRoot $root
    if (-not (Test-Path -LiteralPath $absRoot)) {
        Write-Warning "扫描目录不存在，跳过：$absRoot"
        continue
    }
    foreach ($filter in $fileFilters) {
        Get-ChildItem -LiteralPath $absRoot -Filter $filter -File -Recurse -ErrorAction SilentlyContinue |
            ForEach-Object { $files.Add($_.FullName) }
    }
}

if ($files.Count -eq 0) {
    throw "未扫描到任何源文件，无法生成子集。"
}
Write-Host ("Scanning    : {0} files" -f $files.Count)

# --- 4. 提取唯一 Unicode 码点 ------------------------------------------------
$codepoints = New-Object 'System.Collections.Generic.HashSet[int]'
foreach ($file in $files) {
    # ReadAllText 在 Windows 上默认按 UTF-8 解码（含 BOM 自动处理）。
    $text = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)
    foreach ($ch in $text.ToCharArray()) {
        [int]$cp = [int]$ch
        # 跳过控制字符；其余字符先收集，子集工具会报告源字体不支持的码点。
        if ($cp -lt 0x20 -or $cp -eq 0x7F) { continue }
        [void]$codepoints.Add($cp)
    }
}

if ($codepoints.Count -eq 0) {
    throw "未从源文件中提取到任何字符，子集为空。"
}

Write-Host ("Codepoints  : {0} unique" -f $codepoints.Count)

# --- 5. 运行 font-subset.exe -------------------------------------------------
$outputFont = Join-Path $RepoRoot "quota_watch\assets\fonts\NotoSansSC-QuotaWatchSubset.ttf"
$outputDir = Split-Path -Parent $outputFont
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# 始终先写同目录临时文件。只有完整成功后才原子替换正式字体，避免工具失败时
# 把上一版可用字体删除。Noto Sans SC 不包含少量源码注释符号（例如 ✕）；
# font-subset 会逐个报告它们，这里移除不支持的码点后重试。
$tempOutput = Join-Path $outputDir (".NotoSansSC-QuotaWatchSubset.{0}.tmp.ttf" -f $PID)
$backupOutput = Join-Path $outputDir (".NotoSansSC-QuotaWatchSubset.{0}.bak.ttf" -f $PID)
$unsupported = New-Object System.Collections.Generic.List[int]

function Invoke-FontSubset {
    param(
        [Parameter(Mandatory = $true)]
        [int[]]$Codepoints,
        [Parameter(Mandatory = $true)]
        [string]$TargetFont
    )

    # font-subset.exe 从 stdin 读十进制码点：output 在前，input 在后。
    $stdinLine = (($Codepoints | ForEach-Object { [string]$_ }) -join ' ') + "`n"
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $fontSubset
    $startInfo.Arguments = '"' + $TargetFont + '" "' + $SourceFont + '"'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $process.StandardInput.Write($stdinLine)
    $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    [pscustomobject]@{
        ExitCode = $process.ExitCode
        Output = (($stdout + "`n" + $stderr).Trim())
    }
}

try {
    Write-Host "Subsetting  -> $outputFont"
    while ($true) {
        Remove-Item -LiteralPath $tempOutput -Force -ErrorAction SilentlyContinue
        [int[]]$sorted = @($codepoints | Sort-Object)
        $result = Invoke-FontSubset -Codepoints $sorted -TargetFont $tempOutput
        if ($result.ExitCode -eq 0) {
            if (-not [string]::IsNullOrWhiteSpace($result.Output)) {
                Write-Host $result.Output
            }
            break
        }

        if ($result.Output -match "Codepoint\s+(\d+)\s+not found in font") {
            $missing = [int]$Matches[1]
            if (-not $codepoints.Remove($missing)) {
                throw "font-subset.exe 重复报告无法移除的码点 $missing。"
            }
            $unsupported.Add($missing)
            Write-Warning ("源字体不支持 U+{0:X4}，已跳过后重试。" -f $missing)
            continue
        }

        throw "font-subset.exe 退出码 $($result.ExitCode)：$($result.Output)"
    }

    if (-not (Test-Path -LiteralPath $tempOutput -PathType Leaf)) {
        throw "子集未生成：$tempOutput"
    }
    $tempItem = Get-Item -LiteralPath $tempOutput
    if ($tempItem.Length -eq 0) {
        throw "子集为空（0 字节）：$tempOutput"
    }

    if (Test-Path -LiteralPath $outputFont -PathType Leaf) {
        Remove-Item -LiteralPath $backupOutput -Force -ErrorAction SilentlyContinue
        [System.IO.File]::Replace($tempOutput, $outputFont, $backupOutput)
        Remove-Item -LiteralPath $backupOutput -Force -ErrorAction SilentlyContinue
    } else {
        [System.IO.File]::Move($tempOutput, $outputFont)
    }
} finally {
    Remove-Item -LiteralPath $tempOutput -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $backupOutput -Force -ErrorAction SilentlyContinue
}

$outItem = Get-Item -LiteralPath $outputFont
if ($unsupported.Count -gt 0) {
    Write-Host ("Skipped     : {0} unsupported codepoint(s)" -f $unsupported.Count)
}

Write-Host ("Done        : {0} ({1} bytes)" -f $outputFont, $outItem.Length)
Write-Host "源字体未修改、未复制进仓库。"

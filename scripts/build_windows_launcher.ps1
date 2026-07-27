[CmdletBinding()]
param(
    [string]$OutputPath = '',

    [switch]$TestBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDirectory
$sourcePath = Join-Path $scriptDirectory 'launcher\QuotaWatchLauncher.cs'
$iconPath = Join-Path $repoRoot 'quota_watch\assets\logos\quota_watch_icon.ico'
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repoRoot '启动 Quota Watch.exe'
}

$compilerCandidates = @(
    'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\Roslyn\csc.exe',
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)
$compiler = $compilerCandidates |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($compiler)) {
    throw 'C# compiler was not found. Install the Visual Studio C++ workload.'
}
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "Launcher source was not found: $sourcePath"
}
if (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) {
    throw "Launcher icon was not found: $iconPath"
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$compilerArguments = @(
    '/nologo',
    '/target:winexe',
    '/platform:anycpu',
    '/reference:System.Windows.Forms.dll',
    "/win32icon:$iconPath",
    "/out:$OutputPath"
)
if ($TestBuild) {
    $compilerArguments += '/define:QUOTA_WATCH_LAUNCHER_TEST'
}
$compilerArguments += $sourcePath

& $compiler @compilerArguments
if ($LASTEXITCODE -ne 0) {
    throw "Launcher compilation failed with exit code $LASTEXITCODE."
}

Write-Host "[Quota Watch] Built launcher: $OutputPath"

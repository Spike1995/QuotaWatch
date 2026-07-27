[CmdletBinding()]
param(
    [string]$BuilderPython = '',

    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDirectory
$backendRoot = Join-Path $repoRoot 'backend'
$runtimeVenv = Join-Path $backendRoot '.venv-runtime'
$runtimePython = Join-Path $runtimeVenv 'Scripts\python.exe'
$runtimePythonw = Join-Path $runtimeVenv 'Scripts\pythonw.exe'
$sitePackages = Join-Path $runtimeVenv 'Lib\site-packages'
$lockFile = Join-Path $backendRoot 'requirements-runtime.lock'
$developmentPython = Join-Path $backendRoot '.venv\Scripts\python.exe'

function Assert-ExactRuntimePath {
    $expected = [System.IO.Path]::GetFullPath(
        (Join-Path $backendRoot '.venv-runtime')
    ).TrimEnd('\')
    $actual = [System.IO.Path]::GetFullPath($runtimeVenv).TrimEnd('\')
    if (-not [string]::Equals(
        $actual,
        $expected,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to manage an unexpected runtime path: $actual"
    }
}

function Resolve-BuilderPython {
    if (-not [string]::IsNullOrWhiteSpace($BuilderPython)) {
        return $BuilderPython
    }
    if (Test-Path -LiteralPath $developmentPython -PathType Leaf) {
        return $developmentPython
    }
    return 'python'
}

function Assert-RuntimeEnvironment {
    if (-not (Test-Path -LiteralPath $runtimePython -PathType Leaf)) {
        throw "Runtime Python was not found: $runtimePython"
    }
    if (-not (Test-Path -LiteralPath $runtimePythonw -PathType Leaf)) {
        throw "Runtime pythonw was not found: $runtimePythonw"
    }

    $forbidden = @(
        'PIL',
        'pip',
        'pytest',
        '_pytest',
        'pygments'
    )
    foreach ($name in $forbidden) {
        $matches = Get-ChildItem `
            -LiteralPath $sitePackages `
            -Force `
            -ErrorAction Stop |
            Where-Object {
                $_.Name -eq $name -or
                $_.Name -like "$name-*.dist-info"
            }
        if ($matches) {
            throw "Development-only package leaked into runtime: $name"
        }
    }

    $env:PYTHONDONTWRITEBYTECODE = '1'
    & $runtimePython -c 'import fastapi, httpx, pydantic, uvicorn'
    if ($LASTEXITCODE -ne 0) {
        throw "Runtime import validation failed with exit code $LASTEXITCODE."
    }
    Write-Host '[Quota Watch] Runtime imports passed.'

    $bytes = (
        Get-ChildItem -LiteralPath $runtimeVenv -Recurse -File |
        Measure-Object -Property Length -Sum
    ).Sum
    Write-Host (
        '[Quota Watch] Runtime environment: {0:N2} MiB' -f
        ($bytes / 1MB)
    )
}

Assert-ExactRuntimePath
if (-not (Test-Path -LiteralPath $lockFile -PathType Leaf)) {
    throw "Runtime lock file was not found: $lockFile"
}

if ($ValidateOnly) {
    Assert-RuntimeEnvironment
    return
}

$builder = Resolve-BuilderPython
& $builder -c 'import sys; print(sys.version)'
if ($LASTEXITCODE -ne 0) {
    throw "Builder Python is unavailable: $builder"
}

if (Test-Path -LiteralPath $runtimeVenv) {
    $resolved = (Resolve-Path -LiteralPath $runtimeVenv).Path.TrimEnd('\')
    $expected = [System.IO.Path]::GetFullPath($runtimeVenv).TrimEnd('\')
    if (-not [string]::Equals(
        $resolved,
        $expected,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to remove an unexpected runtime path: $resolved"
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

& $builder -m venv --without-pip $runtimeVenv
if ($LASTEXITCODE -ne 0) {
    throw "Runtime venv creation failed with exit code $LASTEXITCODE."
}

& $builder -m pip install `
    --disable-pip-version-check `
    --no-compile `
    --no-deps `
    --requirement $lockFile `
    --target $sitePackages
if ($LASTEXITCODE -ne 0) {
    throw "Runtime dependency install failed with exit code $LASTEXITCODE."
}

$manifest = [ordered]@{
    python = (& $runtimePython -c 'import platform; print(platform.python_version())')
    lockSha256 = (Get-FileHash -LiteralPath $lockFile -Algorithm SHA256).Hash
    excludedDevelopmentPackages = @(
        'Pillow',
        'pytest',
        'Pygments',
        'pip'
    )
}
$manifest |
    ConvertTo-Json -Depth 3 |
    Set-Content `
        -LiteralPath (
            Join-Path $runtimeVenv 'quota-watch-runtime-manifest.json'
        ) `
        -Encoding utf8

Assert-RuntimeEnvironment

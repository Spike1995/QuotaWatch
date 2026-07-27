[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$BackendPort = 8000,

    [ValidateRange(5, 120)]
    [int]$StartupTimeoutSeconds = 30,

    [ValidateNotNullOrEmpty()]
    [string]$FlutterDevice = 'edge',

    [string]$FlutterCommand = '',

    [switch]$Desktop,

    [string]$DesktopExecutable = '',

    [switch]$ValidateOnly,

    [switch]$SmokeTest,

    [switch]$DisableGlm,

    [switch]$KeepBackend,

    # GUI launcher only: start the desktop runtime, write a PID-only handoff
    # record, and return without retaining PowerShell for the app lifetime.
    [switch]$BootstrapDesktop,

    [string]$RuntimeHandoffPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDirectory
$backendRoot = Join-Path $repoRoot 'backend'
$flutterRoot = Join-Path $repoRoot 'quota_watch'
$runtimeBackendPython = Join-Path (
    $backendRoot
) '.venv-runtime\Scripts\pythonw.exe'
$developmentBackendPython = Join-Path (
    $backendRoot
) '.venv\Scripts\pythonw.exe'
$backendPython = if (
    Test-Path -LiteralPath $runtimeBackendPython -PathType Leaf
) {
    $runtimeBackendPython
} else {
    $developmentBackendPython
}
$defaultFlutter = 'E:\Move\flutter\bin\flutter.bat'
$defaultDesktopExecutable = Join-Path (
    $flutterRoot
) 'build\windows\x64\runner\Release\quota_watch.exe'
$desktopUsesCompiledDefault = [string]::IsNullOrWhiteSpace($DesktopExecutable)
$ownedBackend = $null
$savedEnvironment = @{}
$runtimeHandoffComplete = $false

function Write-Stage {
    param([Parameter(Mandatory = $true)][string]$Message)

    Write-Host "[Quota Watch] $Message"
}

function Assert-LauncherDependencies {
    if (-not (Test-Path -LiteralPath $backendPython -PathType Leaf)) {
        throw (
            'Backend Python was not found. Build the runtime environment with ' +
            'scripts\build_runtime_venv.ps1 or create backend\.venv.'
        )
    }
    if (-not (Test-Path -LiteralPath $backendRoot -PathType Container)) {
        throw "Backend directory was not found: $backendRoot"
    }
    if (-not (Test-Path -LiteralPath $flutterRoot -PathType Container)) {
        throw "Flutter project directory was not found: $flutterRoot"
    }

    if ($Desktop) {
        if ([string]::IsNullOrWhiteSpace($script:DesktopExecutable)) {
            $script:DesktopExecutable = $defaultDesktopExecutable
        }
        if (-not $SmokeTest -and -not (
            Test-Path -LiteralPath $script:DesktopExecutable -PathType Leaf
        )) {
            throw (
                'Windows release executable was not found: ' +
                $script:DesktopExecutable +
                '. Run flutter build windows first.'
            )
        }
        return
    }

    if ([string]::IsNullOrWhiteSpace($script:FlutterCommand)) {
        $configuredFlutter = [Environment]::GetEnvironmentVariable(
            'QUOTA_WATCH_FLUTTER_COMMAND',
            'Process'
        )
        if ([string]::IsNullOrWhiteSpace($configuredFlutter)) {
            $configuredFlutter = [Environment]::GetEnvironmentVariable(
                'QUOTA_WATCH_FLUTTER_COMMAND',
                'User'
            )
        }
        $script:FlutterCommand = if (
            [string]::IsNullOrWhiteSpace($configuredFlutter)
        ) {
            $defaultFlutter
        } else {
            $configuredFlutter
        }
    }

    if (-not $SmokeTest -and -not (
        Test-Path -LiteralPath $script:FlutterCommand -PathType Leaf
    )) {
        throw "Flutter command was not found: $($script:FlutterCommand)"
    }
}

function Get-FirstEnvironmentValue {
    param([Parameter(Mandatory = $true)][string[]]$Names)

    foreach ($name in $Names) {
        foreach ($scope in @('Process', 'User', 'Machine')) {
            $value = [Environment]::GetEnvironmentVariable($name, $scope)
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                return @{
                    Name = $name
                    Value = $value
                }
            }
        }
    }
    return $null
}

function Set-TemporaryProcessEnvironment {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()][string]$Value
    )

    if (-not $savedEnvironment.ContainsKey($Name)) {
        $original = [Environment]::GetEnvironmentVariable($Name, 'Process')
        $savedEnvironment[$Name] = @{
            Present = $null -ne $original
            Value = $original
        }
    }
    [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
}

function Restore-ProcessEnvironment {
    foreach ($name in @($savedEnvironment.Keys)) {
        $original = $savedEnvironment[$name]
        $value = if ($original.Present) { $original.Value } else { $null }
        [Environment]::SetEnvironmentVariable($name, $value, 'Process')
    }
    $savedEnvironment.Clear()
}

function Test-TcpPort {
    param([Parameter(Mandatory = $true)][int]$Port)

    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $pending = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        if (-not $pending.AsyncWaitHandle.WaitOne(500)) {
            return $false
        }
        $client.EndConnect($pending)
        return $true
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Test-QuotaWatchBackend {
    param([Parameter(Mandatory = $true)][int]$Port)

    try {
        $health = Invoke-RestMethod `
            -Uri "http://127.0.0.1:$Port/health" `
            -TimeoutSec 2
        $schema = Invoke-RestMethod `
            -Uri "http://127.0.0.1:$Port/openapi.json" `
            -TimeoutSec 2
        return (
            $health.status -eq 'ok' -and
            $schema.info.title -eq 'Quota Watch Local Backend'
        )
    } catch {
        return $false
    }
}

function Set-BackendChildEnvironment {
    # Keep the generated runtime environment immutable and size-stable.
    Set-TemporaryProcessEnvironment `
        -Name 'PYTHONDONTWRITEBYTECODE' `
        -Value '1'

    if ($SmokeTest) {
        foreach ($name in @(
            'QUOTA_WATCH_CODEX_REAL',
            'QUOTA_WATCH_KIMI_REAL',
            'QUOTA_WATCH_KIMI_API_KEY',
            'QUOTA_WATCH_GLM_REAL',
            'QUOTA_WATCH_GLM_API_KEY'
        )) {
            Set-TemporaryProcessEnvironment -Name $name -Value $null
        }
        Write-Stage 'Smoke test forced every real provider off.'
        return
    }

    Set-TemporaryProcessEnvironment `
        -Name 'QUOTA_WATCH_CODEX_REAL' `
        -Value '1'

    $kimi = Get-FirstEnvironmentValue -Names @(
        'QUOTA_WATCH_KIMI_API_KEY',
        'KIMI_CODING_API_KEY'
    )
    if ($null -eq $kimi) {
        Set-TemporaryProcessEnvironment `
            -Name 'QUOTA_WATCH_KIMI_API_KEY' `
            -Value $null
        Set-TemporaryProcessEnvironment `
            -Name 'QUOTA_WATCH_KIMI_REAL' `
            -Value $null
        Write-Stage 'Kimi: no key found; it will remain disabled.'
    } else {
        Set-TemporaryProcessEnvironment `
            -Name 'QUOTA_WATCH_KIMI_API_KEY' `
            -Value $kimi.Value
        Set-TemporaryProcessEnvironment `
            -Name 'QUOTA_WATCH_KIMI_REAL' `
            -Value '1'
        Write-Stage "Kimi: mapped from $($kimi.Name) without printing the key."
        $kimi = $null
    }

    $glm = Get-FirstEnvironmentValue -Names @(
        'QUOTA_WATCH_GLM_API_KEY',
        'GLM_API_KEY'
    )
    if ($DisableGlm -or $null -eq $glm) {
        Set-TemporaryProcessEnvironment `
            -Name 'QUOTA_WATCH_GLM_API_KEY' `
            -Value $null
        Set-TemporaryProcessEnvironment `
            -Name 'QUOTA_WATCH_GLM_REAL' `
            -Value $null
        $reason = if ($DisableGlm) { 'disabled by option' } else { 'no key found' }
        Write-Stage "GLM: $reason; it will remain disabled."
    } else {
        Set-TemporaryProcessEnvironment `
            -Name 'QUOTA_WATCH_GLM_API_KEY' `
            -Value $glm.Value
        Set-TemporaryProcessEnvironment `
            -Name 'QUOTA_WATCH_GLM_REAL' `
            -Value '1'
        Write-Stage "GLM: mapped from $($glm.Name) without printing the key."
        $glm = $null
    }
}

function Start-OwnedBackend {
    param([Parameter(Mandatory = $true)][int]$Port)

    $logDirectory = Join-Path ([System.IO.Path]::GetTempPath()) (
        'quota-watch-launcher'
    )
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    $logId = "$Port-$PID-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))"
    $stdoutLog = Join-Path $logDirectory "$logId.stdout.log"
    $stderrLog = Join-Path $logDirectory "$logId.stderr.log"

    try {
        Set-BackendChildEnvironment
        $arguments = @(
            '-B',
            '-m',
            'uvicorn',
            'app.main:app',
            '--host',
            '127.0.0.1',
            '--port',
            $Port.ToString()
        )
        $process = Start-Process `
            -FilePath $backendPython `
            -ArgumentList $arguments `
            -WorkingDirectory $backendRoot `
            -WindowStyle Hidden `
            -RedirectStandardOutput $stdoutLog `
            -RedirectStandardError $stderrLog `
            -PassThru
    } finally {
        Restore-ProcessEnvironment
    }

    return @{
        Process = $process
        StdoutLog = $stdoutLog
        StderrLog = $stderrLog
    }
}

function Start-SafeDesktopProcess {
    # Provider credentials and backend-only feature gates must never enter the
    # Flutter process. Save, clear for child creation, then restore locally.
    foreach ($name in @(
        'QUOTA_WATCH_CODEX_REAL',
        'QUOTA_WATCH_KIMI_REAL',
        'QUOTA_WATCH_KIMI_API_KEY',
        'KIMI_CODING_API_KEY',
        'QUOTA_WATCH_GLM_REAL',
        'QUOTA_WATCH_GLM_API_KEY',
        'GLM_API_KEY'
    )) {
        Set-TemporaryProcessEnvironment -Name $name -Value $null
    }

    $logDirectory = Join-Path ([System.IO.Path]::GetTempPath()) (
        'quota-watch-launcher'
    )
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    $logId = "desktop-$PID-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))"
    $stdoutLog = Join-Path $logDirectory "$logId.stdout.log"
    $stderrLog = Join-Path $logDirectory "$logId.stderr.log"

    try {
        return Start-Process `
            -FilePath $script:DesktopExecutable `
            -WorkingDirectory (Split-Path -Parent $script:DesktopExecutable) `
            -RedirectStandardOutput $stdoutLog `
            -RedirectStandardError $stderrLog `
            -PassThru
    } finally {
        Restore-ProcessEnvironment
    }
}

function Wait-ForOwnedBackend {
    param(
        [Parameter(Mandatory = $true)]$Backend,
        [Parameter(Mandatory = $true)][int]$Port
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($StartupTimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $Backend.Process.Refresh()
        if ($Backend.Process.HasExited) {
            throw (
                'Backend failed to start. Diagnostic log: ' +
                $Backend.StderrLog
            )
        }
        if (Test-QuotaWatchBackend -Port $Port) {
            return
        }
        Start-Sleep -Milliseconds 250
    }
    throw "Backend did not become ready within $StartupTimeoutSeconds seconds."
}

function Stop-OwnedBackend {
    param([AllowNull()]$Backend)

    if ($null -eq $Backend -or $null -eq $Backend.Process) {
        return
    }
    $Backend.Process.Refresh()
    if ($Backend.Process.HasExited) {
        return
    }

    Write-Stage "Stopping owned backend PID $($Backend.Process.Id)..."
    Stop-Process -Id $Backend.Process.Id -ErrorAction SilentlyContinue
    if (-not $Backend.Process.WaitForExit(5000)) {
        Stop-Process `
            -Id $Backend.Process.Id `
            -Force `
            -ErrorAction SilentlyContinue
        [void]$Backend.Process.WaitForExit(5000)
    }
}

function Test-OfflineQuotaResponse {
    param([Parameter(Mandatory = $true)][int]$Port)

    # 阶段 9：离线假场景已删除。用 all_real 验证后端：即使三家真实开关
    # 全关，all_real 仍返回三家 _real_not_enabled 占位（codex/kimi/glm），
    # 满足按序返回三家的断言，且不发起真实 provider 请求，适合 smoke test。
    $payload = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/api/v1/quotas?scenario=all_real" -TimeoutSec 5
    $providers = @($payload | ForEach-Object { $_.provider })
    if (
        $providers.Count -ne 3 -or
        ($providers -join ',') -ne 'codex,kimi,glm'
    ) {
        throw 'Offline response did not return Codex, Kimi, and GLM in order.'
    }
}

try {
    Assert-LauncherDependencies

    $kimiAvailable = $null -ne (
        Get-FirstEnvironmentValue -Names @(
            'QUOTA_WATCH_KIMI_API_KEY',
            'KIMI_CODING_API_KEY'
        )
    )
    $glmAvailable = $null -ne (
        Get-FirstEnvironmentValue -Names @(
            'QUOTA_WATCH_GLM_API_KEY',
            'GLM_API_KEY'
        )
    )

    Write-Stage "Dependency check passed. Kimi key: $kimiAvailable; GLM key: $glmAvailable."

    if ($ValidateOnly) {
        if (Test-QuotaWatchBackend -Port $BackendPort) {
            Write-Stage "Port $BackendPort has a reusable Quota Watch backend."
        } elseif (Test-TcpPort -Port $BackendPort) {
            throw "Port $BackendPort is occupied by another program; it was not stopped."
        } else {
            Write-Stage "Port $BackendPort is available."
        }
        Write-Stage 'Launcher validation passed.'
        return
    }

    if ($SmokeTest -and (Test-TcpPort -Port $BackendPort)) {
        throw "Smoke-test port $BackendPort is occupied; choose another port."
    }
    if (
        $Desktop -and
        -not $SmokeTest -and
        $BackendPort -ne 8000 -and
        $desktopUsesCompiledDefault
    ) {
        throw (
            'The release desktop app is compiled for backend port 8000. ' +
            'Use the default port or rebuild the app for another URL.'
        )
    }

    $ownsBackend = $false
    if (Test-QuotaWatchBackend -Port $BackendPort) {
        Write-Stage (
            "Reusing the Quota Watch backend on port $BackendPort; " +
            'it will not be modified or stopped.'
        )
    } elseif (Test-TcpPort -Port $BackendPort) {
        throw "Port $BackendPort is occupied by another program; it was not stopped."
    } else {
        Write-Stage "Starting FastAPI in the background on 127.0.0.1:$BackendPort..."
        $ownedBackend = Start-OwnedBackend -Port $BackendPort
        $ownsBackend = $true
        Wait-ForOwnedBackend -Backend $ownedBackend -Port $BackendPort
        Write-Stage 'FastAPI health check passed.'
    }

    if ($SmokeTest) {
        Test-OfflineQuotaResponse -Port $BackendPort
        Write-Stage 'Offline smoke test passed: start, health, response, and cleanup.'
        return
    }

    if ($Desktop) {
        Write-Stage 'Starting the Windows desktop app in backend/all_real mode.'
        $desktopProcess = Start-SafeDesktopProcess

        if ($BootstrapDesktop) {
            $desktopExited = $desktopProcess.WaitForExit(1000)
            $desktopExitCode = if ($desktopExited) {
                $desktopProcess.Refresh()
                $reportedExitCode = $desktopProcess.ExitCode
                if ($null -ne $reportedExitCode) {
                    [int]$reportedExitCode
                } elseif (-not $desktopUsesCompiledDefault) {
                    # Start-Process can omit ExitCode for a completed custom
                    # test/developer executable. Production uses the compiled
                    # default and never masks an early exit.
                    0
                } else {
                    throw 'Windows desktop app exited before reporting a code.'
                }
            } else {
                0
            }
            if ($desktopExited -and $desktopExitCode -ne 0) {
                throw (
                    'Windows desktop app failed during startup with exit code ' +
                    $desktopExitCode +
                    '.'
                )
            }

            $backendPid = if ($ownsBackend) {
                $ownedBackend.Process.Id
            } else {
                0
            }
            $backendStartedUtcTicks = if ($ownsBackend) {
                $ownedBackend.Process.StartTime.ToUniversalTime().Ticks
            } else {
                0
            }
            $handoffFields = @(
                'QUOTA_WATCH_RUNTIME_HANDOFF',
                "backendOwned=$([int]$ownsBackend)",
                "backendPid=$backendPid",
                "backendStartedUtcTicks=$backendStartedUtcTicks",
                "desktopPid=$($desktopProcess.Id)",
                "desktopExited=$([int]$desktopExited)",
                "desktopExitCode=$desktopExitCode"
            )
            $handoffRecord = $handoffFields -join '|'
            if ([string]::IsNullOrWhiteSpace($RuntimeHandoffPath)) {
                Write-Output $handoffRecord
            } else {
                $handoffDirectory = Split-Path -Parent $RuntimeHandoffPath
                if (-not [string]::IsNullOrWhiteSpace($handoffDirectory)) {
                    New-Item `
                        -ItemType Directory `
                        -Path $handoffDirectory `
                        -Force | Out-Null
                }
                [System.IO.File]::WriteAllText(
                    $RuntimeHandoffPath,
                    $handoffRecord,
                    [System.Text.UTF8Encoding]::new($false)
                )
            }
            $runtimeHandoffComplete = $true
            return
        }

        [void]$desktopProcess.WaitForExit()
        $desktopProcess.Refresh()
        $desktopExitCode = if ($null -ne $desktopProcess.ExitCode) {
            [int]$desktopProcess.ExitCode
        } elseif (-not $desktopUsesCompiledDefault) {
            0
        } else {
            throw 'Windows desktop app exited without reporting a code.'
        }
        if ($desktopExitCode -ne 0) {
            throw (
                'Windows desktop app failed with exit code ' +
                $desktopExitCode +
                '.'
            )
        }
    } else {
        $backendUrl = "http://127.0.0.1:$BackendPort"
        $flutterArguments = @(
            'run',
            '-d',
            $FlutterDevice,
            '--dart-define=QUOTA_DATA_MODE=backend',
            '--dart-define=QUOTA_SCENARIO=all_real',
            "--dart-define=QUOTA_BACKEND_URL=$backendUrl"
        )

        Write-Stage 'Starting Flutter Edge in backend/all_real mode.'
        Push-Location $flutterRoot
        try {
            & $script:FlutterCommand @flutterArguments
            if ($LASTEXITCODE -ne 0) {
                throw "Flutter failed with exit code $LASTEXITCODE."
            }
        } finally {
            Pop-Location
        }
    }
} catch {
    if (
        $BootstrapDesktop -and
        -not [string]::IsNullOrWhiteSpace($RuntimeHandoffPath)
    ) {
        $bootstrapLog = "$RuntimeHandoffPath.error.log"
        try {
            [System.IO.File]::WriteAllText(
                $bootstrapLog,
                (
                    "Quota Watch bootstrap failed.`r`n" +
                    $_.Exception.GetType().Name +
                    ': ' +
                    $_.Exception.Message
                ),
                [System.Text.UTF8Encoding]::new($false)
            )
        } catch {
            # Preserve the original launcher error if diagnostic writing fails.
        }
    }
    Write-Error $_.Exception.Message
    exit 1
} finally {
    Restore-ProcessEnvironment
    if ($runtimeHandoffComplete) {
        Write-Stage 'Desktop runtime handed off to the GUI launcher.'
    } elseif (-not $KeepBackend) {
        Stop-OwnedBackend -Backend $ownedBackend
    } elseif ($null -ne $ownedBackend) {
        Write-Stage "Keeping backend PID $($ownedBackend.Process.Id) as requested."
    }
}

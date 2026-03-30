param(
    [switch]$BootMode,
    [string]$RepoRoot = "C:\netspeakms-supabase",
    [string]$TunnelName = "netspeak-prod",
    [string]$CloudflaredPath = "C:\Program Files (x86)\cloudflared\cloudflared.exe",
    [string]$CloudflaredConfig = "C:\Users\netsp\.cloudflared\config.yml",
    [string]$DockerDesktopPath = "C:\Program Files\Docker\Docker\Docker Desktop.exe",
    [string]$DbHotfixSqlPath = "C:\netspeakms-supabase\ops\sql\20260306_announcement_hotfix.sql"
)

$ErrorActionPreference = "Stop"

$EXIT_OK = 0
$EXIT_TUNNEL_FAIL = 11
$EXIT_DOCKER_FAIL = 21
$EXIT_INFRA_FAIL = 31
$EXIT_APP_FAIL = 32
$EXIT_ROUTE_FAIL = 41

$logDir = Join-Path $RepoRoot "ops\logs"
$logFile = Join-Path $logDir "boot-start.log"
$lockFile = Join-Path $RepoRoot "ops\logs\boot-start.lock"
$script:startupLockOwned = $false

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $line = "{0} [{1}] {2}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Write-Host $line
    Add-Content -Path $script:logFile -Value $line
}

function Exit-WithCode {
    param([int]$Code, [string]$Message)
    if ($Message) {
        Write-Log -Message $Message -Level "ERROR"
    }
    Write-Log -Message ("Exiting with code {0}" -f $Code) -Level "INFO"
    Release-StartupLock
    exit $Code
}

function Ensure-LogPath {
    if (-not (Test-Path $script:logDir)) {
        New-Item -Path $script:logDir -ItemType Directory -Force | Out-Null
    }
}

function Release-StartupLock {
    if ($script:startupLockOwned -and (Test-Path $script:lockFile)) {
        Remove-Item -Path $script:lockFile -Force -ErrorAction SilentlyContinue
    }
    $script:startupLockOwned = $false
}

function Acquire-StartupLock {
    if (Test-Path $script:lockFile) {
        $existingPidRaw = (Get-Content -Path $script:lockFile -ErrorAction SilentlyContinue | Select-Object -First 1)
        $existingPid = 0
        [void][int]::TryParse(($existingPidRaw | Out-String).Trim(), [ref]$existingPid)

        if ($existingPid -gt 0) {
            $existingProc = Get-Process -Id $existingPid -ErrorAction SilentlyContinue
            if ($existingProc) {
                Exit-WithCode -Code $EXIT_INFRA_FAIL -Message "Another startup run is already in progress (PID $existingPid). Wait for it to finish before starting again."
            }
        }

        Remove-Item -Path $script:lockFile -Force -ErrorAction SilentlyContinue
    }

    Set-Content -Path $script:lockFile -Value $PID -Encoding ascii
    $script:startupLockOwned = $true
}

function Initialize-DockerCliConfig {
    $dockerConfigPath = Join-Path $RepoRoot "ops\.docker-config"
    if (-not (Test-Path $dockerConfigPath)) {
        New-Item -Path $dockerConfigPath -ItemType Directory -Force | Out-Null
    }

    $env:DOCKER_CONFIG = $dockerConfigPath
    Write-Log "Using Docker CLI config path '$dockerConfigPath'."
}

function Start-CloudflaredIfNeeded {
    Write-Log "Checking cloudflared state."

    $service = Get-Service -Name "cloudflared" -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq "Running") {
        Write-Log "Cloudflared Windows service is already running."
        return
    }

    if ($service -and $service.Status -ne "Running") {
        Write-Log "Cloudflared service exists but is '$($service.Status)'. Skipping service start to keep boot script as tunnel owner."
    }

    $runningProc = Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue
    if ($runningProc) {
        Write-Log "Cloudflared process already running (PID(s): $($runningProc.Id -join ', '))."
        return
    }

    if (-not (Test-Path $CloudflaredPath)) {
        Exit-WithCode -Code $EXIT_TUNNEL_FAIL -Message "cloudflared executable not found at '$CloudflaredPath'."
    }
    if (-not (Test-Path $CloudflaredConfig)) {
        Exit-WithCode -Code $EXIT_TUNNEL_FAIL -Message "cloudflared config not found at '$CloudflaredConfig'."
    }

    Write-Log "Starting cloudflared process fallback."
    Start-Process -FilePath $CloudflaredPath -ArgumentList "tunnel --config `"$CloudflaredConfig`" run $TunnelName" -WindowStyle Hidden
    Start-Sleep -Seconds 3

    $runningProc = Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue
    if (-not $runningProc) {
        Exit-WithCode -Code $EXIT_TUNNEL_FAIL -Message "cloudflared failed to start."
    }

    Write-Log "Cloudflared process started (PID(s): $($runningProc.Id -join ', '))."
}

function Assert-CloudflaredConfigSafe {
    if (-not (Test-Path $CloudflaredConfig)) {
        Exit-WithCode -Code $EXIT_TUNNEL_FAIL -Message "cloudflared config not found at '$CloudflaredConfig'."
    }

    $configRaw = Get-Content -Path $CloudflaredConfig -Raw
    if ($configRaw -match "service:\s*http://localhost:80") {
        Exit-WithCode -Code $EXIT_TUNNEL_FAIL -Message "Unsafe cloudflared origin detected ('localhost:80'). Use '127.0.0.1:80' to avoid IPv6 loopback origin refusal."
    }

    Write-Log "Cloudflared config validation passed (no localhost:80 origin)."
}

function Test-DockerDaemonReady {
    cmd /c "docker info >nul 2>&1"
    return ($LASTEXITCODE -eq 0)
}

function Wait-ForDocker {
    Write-Log "Checking Docker daemon readiness."

    $dockerReady = $false
    if (Test-DockerDaemonReady) {
        Write-Log "Docker daemon already ready."
        return
    }

    $dockerService = Get-Service -Name "com.docker.service" -ErrorAction SilentlyContinue
    if ($dockerService) {
        if ($dockerService.Status -ne "Running") {
            Write-Log "Docker Desktop service is '$($dockerService.Status)'. Attempting to start com.docker.service."
            try {
                Start-Service -Name "com.docker.service" -ErrorAction Stop
                Start-Sleep -Seconds 2
                $dockerService.Refresh()
                Write-Log "Docker Desktop service status after start attempt: $($dockerService.Status)."
            } catch {
                Write-Log "Failed to start com.docker.service: $($_.Exception.Message)" "WARN"
            }
        } else {
            Write-Log "Docker Desktop service is already running."
        }
    } else {
        Write-Log "Docker Desktop service not found. Falling back to Docker Desktop app launch." "WARN"
    }

    if (Test-DockerDaemonReady) {
        Write-Log "Docker daemon became ready after service start attempt."
        return
    }

    if (Test-Path $DockerDesktopPath) {
        Write-Log "Docker not ready. Starting Docker Desktop in background."
        Start-Process -FilePath $DockerDesktopPath -WindowStyle Hidden
    } else {
        Write-Log "Docker Desktop path not found at '$DockerDesktopPath'." "WARN"
    }

    $deadline = (Get-Date).AddMinutes(10)
    $waitSeconds = 2
    while ((Get-Date) -lt $deadline) {
        if (Test-DockerDaemonReady) {
            $dockerReady = $true
            break
        }
        Write-Log "Docker still unavailable. Retrying in $waitSeconds second(s)."
        Start-Sleep -Seconds $waitSeconds
        $waitSeconds = [Math]::Min($waitSeconds * 2, 30)
    }

    if (-not $dockerReady) {
        Exit-WithCode -Code $EXIT_DOCKER_FAIL -Message "Docker daemon unavailable after 10 minutes."
    }

    Write-Log "Docker daemon is ready."
}

function Wait-ForContainerHealthy {
    param(
        [string]$ContainerName,
        [int]$TimeoutSeconds = 300,
        [switch]$AutoRestartOnce,
        [int]$RestartAfterUnhealthySeconds = 120
    )

    Write-Log "Waiting for container '$ContainerName' to report healthy state."
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $unhealthySince = $null
    $hasRestarted = $false

    while ((Get-Date) -lt $deadline) {
        $healthStatus = (& docker inspect -f "{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}" $ContainerName 2>$null).Trim()
        if ($LASTEXITCODE -eq 0) {
            if ($healthStatus -eq "healthy" -or $healthStatus -eq "none") {
                Write-Log "Container '$ContainerName' ready (health=$healthStatus)."
                return
            }

            $runStatus = (& docker inspect -f "{{.State.Status}}" $ContainerName 2>$null).Trim()

            if ($healthStatus -eq "unhealthy") {
                if (-not $unhealthySince) {
                    $unhealthySince = Get-Date
                }

                $unhealthySeconds = ((Get-Date) - $unhealthySince).TotalSeconds
                if ($AutoRestartOnce -and -not $hasRestarted -and $unhealthySeconds -ge $RestartAfterUnhealthySeconds) {
                    Write-Log "Container '$ContainerName' has been unhealthy for $([int]$unhealthySeconds) second(s). Restarting once for self-recovery."
                    docker restart $ContainerName | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        $hasRestarted = $true
                        $unhealthySince = $null
                        Start-Sleep -Seconds 5
                        continue
                    }

                    Write-Log "Restart attempt for '$ContainerName' failed. Continuing to wait for readiness." "WARN"
                }
            } else {
                $unhealthySince = $null
            }

            Write-Log "Container '$ContainerName' not ready yet (state=$runStatus, health=$healthStatus). Retrying in 5 second(s)."
        } else {
            Write-Log "Container '$ContainerName' not found yet. Retrying in 5 second(s)."
        }

        Start-Sleep -Seconds 5
    }

    Exit-WithCode -Code $EXIT_INFRA_FAIL -Message "Container '$ContainerName' did not become ready within $TimeoutSeconds seconds."
}

function Invoke-TrackedDbHotfix {
    if (-not (Test-Path $DbHotfixSqlPath)) {
        Exit-WithCode -Code $EXIT_INFRA_FAIL -Message "Tracked DB hotfix SQL not found at '$DbHotfixSqlPath'."
    }

    Write-Log "Applying tracked DB hotfix from '$DbHotfixSqlPath'."
    $sqlContent = Get-Content -Path $DbHotfixSqlPath -Raw

    $sqlContent | docker exec -i -u postgres supabase-db sh -lc 'export PGPASSWORD="$POSTGRES_PASSWORD"; export PGOPTIONS="-c client_min_messages=warning"; psql -v ON_ERROR_STOP=1 -U supabase_admin -d postgres' | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Tracked DB hotfix applied as supabase_admin."
        return
    }

    Write-Log "supabase_admin execution failed. Retrying tracked DB hotfix as postgres." "WARN"
    $sqlContent | docker exec -i -u postgres supabase-db sh -lc 'export PGOPTIONS="-c client_min_messages=warning"; psql -v ON_ERROR_STOP=1 -U postgres -d postgres' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Exit-WithCode -Code $EXIT_INFRA_FAIL -Message "Failed to apply tracked DB hotfix SQL."
    }

    Write-Log "Tracked DB hotfix applied as postgres."
}

function Invoke-ComposeUp {
    param(
        [string]$WorkingDirectory,
        [string]$Command,
        [int]$FailureCode,
        [string]$FailureMessage
    )

    Push-Location $WorkingDirectory
    try {
        Write-Log "Running: $Command (cwd: $WorkingDirectory)"
        cmd /c $Command
        if ($LASTEXITCODE -ne 0) {
            Exit-WithCode -Code $FailureCode -Message $FailureMessage
        }
    } finally {
        Pop-Location
    }
}

function Test-LocalRoutes {
    Write-Log "Validating local host-based routes through NPM."

    $appStatus = Wait-ForExpectedHttpStatus `
        -Name "app.netspeak.com.ph" `
        -HostHeader "app.netspeak.com.ph" `
        -ExpectedStatuses @("200") `
        -TimeoutSeconds 180
    if ($appStatus -ne "200") {
        Exit-WithCode -Code $EXIT_ROUTE_FAIL -Message "App route check failed. Expected 200, got $appStatus."
    }

    $apiStatus = Wait-ForExpectedHttpStatus `
        -Name "api.netspeak.com.ph" `
        -HostHeader "api.netspeak.com.ph" `
        -ExpectedStatuses @("200", "401", "403") `
        -TimeoutSeconds 180
    if (@("200", "401", "403") -notcontains $apiStatus) {
        Exit-WithCode -Code $EXIT_ROUTE_FAIL -Message "API route check failed. Expected 200/401/403, got $apiStatus."
    }

    Write-Log "Route checks passed (app=$appStatus, api=$apiStatus)."
}

function Wait-ForExpectedHttpStatus {
    param(
        [string]$Name,
        [string]$HostHeader,
        [string[]]$ExpectedStatuses,
        [int]$TimeoutSeconds = 120
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastStatus = "000"

    while ((Get-Date) -lt $deadline) {
        $lastStatus = (curl.exe -s -o NUL -w "%{http_code}" -H "Host: $HostHeader" http://127.0.0.1).Trim()
        if ($ExpectedStatuses -contains $lastStatus) {
            return $lastStatus
        }

        Write-Log "Route '$Name' not ready yet (status=$lastStatus). Retrying in 5 second(s)."
        Start-Sleep -Seconds 5
    }

    return $lastStatus
}

Ensure-LogPath
Acquire-StartupLock
Initialize-DockerCliConfig
Write-Log "=================================================="
Write-Log ("Boot orchestrator started. Mode: {0}" -f ($(if ($BootMode) { "boot" } else { "manual" })))

Wait-ForDocker

$supabaseComposeWorkingDirectory = Join-Path $RepoRoot "supabase-project"
$supabaseComposeCommand = "docker compose -f docker-compose.yml -f ../docker-compose.npm.yml"

Write-Log "Starting base Supabase services before the full dependency graph."
Invoke-ComposeUp `
    -WorkingDirectory $supabaseComposeWorkingDirectory `
    -Command "$supabaseComposeCommand up -d vector" `
    -FailureCode $EXIT_INFRA_FAIL `
    -FailureMessage "Failed to start Supabase vector service."

Wait-ForContainerHealthy -ContainerName "supabase-vector" -TimeoutSeconds 60

Invoke-ComposeUp `
    -WorkingDirectory $supabaseComposeWorkingDirectory `
    -Command "$supabaseComposeCommand up -d --no-deps db" `
    -FailureCode $EXIT_INFRA_FAIL `
    -FailureMessage "Failed to start Supabase database container."

Wait-ForContainerHealthy -ContainerName "supabase-db" -TimeoutSeconds 600 -AutoRestartOnce -RestartAfterUnhealthySeconds 120

Invoke-TrackedDbHotfix

Invoke-ComposeUp `
    -WorkingDirectory $supabaseComposeWorkingDirectory `
    -Command "$supabaseComposeCommand up -d --no-recreate" `
    -FailureCode $EXIT_INFRA_FAIL `
    -FailureMessage "Failed to start remaining Supabase + NPM services."

Invoke-ComposeUp `
    -WorkingDirectory $RepoRoot `
    -Command "docker compose -f docker-compose.app.yml up -d" `
    -FailureCode $EXIT_APP_FAIL `
    -FailureMessage "Failed to start app compose stack."

Test-LocalRoutes
Assert-CloudflaredConfigSafe
Write-Log "Local routes are ready. Starting cloudflared last to avoid origin race conditions."
Start-CloudflaredIfNeeded

Write-Log "Startup completed successfully."
Write-Log "=================================================="
Release-StartupLock
exit $EXIT_OK

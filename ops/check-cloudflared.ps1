param(
    [string]$TunnelName = "netspeak-prod",
    [string]$CloudflaredPath = "C:\Program Files (x86)\cloudflared\cloudflared.exe"
)

$ErrorActionPreference = "Stop"
$failures = @()

function Add-Failure {
    param([string]$Message)
    $script:failures += $Message
    Write-Host "[FAIL] $Message" -ForegroundColor Red
}

function Add-Pass {
    param([string]$Message)
    Write-Host "[OK]   $Message" -ForegroundColor Green
}

Write-Host "Checking Cloudflare Tunnel health..." -ForegroundColor Cyan
Write-Host "Tunnel: $TunnelName"

if (-not (Test-Path $CloudflaredPath)) {
    Add-Failure "cloudflared executable not found at '$CloudflaredPath'."
} else {
    Add-Pass "cloudflared executable found."
}

$cloudflaredProc = Get-Process cloudflared -ErrorAction SilentlyContinue
if (-not $cloudflaredProc) {
    Add-Failure "No running cloudflared process detected."
} else {
    Add-Pass "cloudflared process is running (PID(s): $($cloudflaredProc.Id -join ', '))."
}

if (Test-Path $CloudflaredPath) {
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $tunnelInfoRaw = & $CloudflaredPath tunnel info $TunnelName 2>&1
    $tunnelExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorAction
    $tunnelInfo = ($tunnelInfoRaw | Out-String)

    if ($tunnelExitCode -ne 0) {
        Add-Failure "Unable to read tunnel info for '$TunnelName'. Output: $tunnelInfo"
    } else {
        Add-Pass "Tunnel info command succeeded."
        $connectorLine = $tunnelInfo | Where-Object { $_ -match "CONNECTOR ID" } | Select-Object -First 1
        if (-not $connectorLine) {
            Add-Failure "No connector information found in tunnel info output."
        } else {
            Add-Pass "Connector metadata found."
        }
    }
}

$appStatus = (curl.exe -s -o NUL -w "%{http_code}" -H "Host: app.netspeak.com.ph" http://127.0.0.1)
if ($appStatus -ne "200") {
    Add-Failure "Local NPM route for app.netspeak.com.ph returned HTTP $appStatus (expected 200)."
} else {
    Add-Pass "Local app route check returned HTTP 200."
}

$apiStatus = (curl.exe -s -o NUL -w "%{http_code}" -H "Host: api.netspeak.com.ph" http://127.0.0.1)
if (@("200", "401", "403") -notcontains $apiStatus) {
    Add-Failure "Local NPM route for api.netspeak.com.ph returned HTTP $apiStatus (expected 200/401/403)."
} else {
    Add-Pass "Local api route check returned HTTP $apiStatus."
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "Cloudflare Tunnel health check finished with errors." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Cloudflare Tunnel health check passed." -ForegroundColor Green
exit 0

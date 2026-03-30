param(
    [string[]]$Urls = @(
        "https://app.netspeak.com.ph/",
        "https://api.netspeak.com.ph/health"
    ),
    [string]$LogFile = ".\ops\uptime-log.csv"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path (Split-Path -Parent $LogFile))) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $LogFile) -Force | Out-Null
}

if (-not (Test-Path $LogFile)) {
    "timestamp,url,http_code,total_time_s,success" | Out-File -FilePath $LogFile -Encoding ascii
}

Write-Host "Checking public endpoints..." -ForegroundColor Cyan

$timestamp = (Get-Date).ToString("s")
$hasFailure = $false

foreach ($url in $Urls) {
    $result = curl.exe -s -o NUL -w "%{http_code},%{time_total}" --max-time 20 $url
    $parts = $result -split ","
    $code = $parts[0]
    $elapsed = $parts[1]

    $isSuccess = $false
    if ($code -match "^[0-9]{3}$") {
        $codeInt = [int]$code
        $isSuccess = ($codeInt -ge 200 -and $codeInt -lt 500)
    }

    if (-not $isSuccess) {
        $hasFailure = $true
        Write-Host "[FAIL] $url -> HTTP $code ($elapsed s)" -ForegroundColor Red
    } else {
        Write-Host "[OK]   $url -> HTTP $code ($elapsed s)" -ForegroundColor Green
    }

    "$timestamp,$url,$code,$elapsed,$isSuccess" | Out-File -FilePath $LogFile -Append -Encoding ascii
}

if ($hasFailure) {
    Write-Host "Public endpoint check completed with failures." -ForegroundColor Red
    exit 1
}

Write-Host "Public endpoint check passed." -ForegroundColor Green
exit 0

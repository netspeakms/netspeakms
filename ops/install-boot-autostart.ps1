param(
    [string]$TaskName = "NetspeakBootStart",
    [string]$TaskUser = "NETSPEAK\netsp",
    [string]$RepoRoot = "C:\netspeakms-supabase",
    [string]$TaskPassword,
    [switch]$UseS4U
)

$ErrorActionPreference = "Stop"

$bootScript = Join-Path $RepoRoot "ops\boot-start.ps1"
if (-not (Test-Path $bootScript)) {
    throw "Boot script not found at '$bootScript'."
}

Write-Host "Installing startup task '$TaskName' for user '$TaskUser'..."
if ($UseS4U) {
    Write-Host "Using S4U logon type (no password prompt)."
} else {
    if ([string]::IsNullOrWhiteSpace($TaskPassword)) {
        Write-Host "You will be prompted for the account password to run when user is not logged on."
        $credential = Get-Credential -UserName $TaskUser -Message "Enter password for scheduled task account"
        $password = $credential.GetNetworkCredential().Password
    } else {
        $password = $TaskPassword
    }

    if ([string]::IsNullOrWhiteSpace($password)) {
        throw "Password is required for scheduled task logon type 'Password'."
    }
}

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$bootScript`" -BootMode"

$trigger = New-ScheduledTaskTrigger -AtStartup
$trigger.Delay = "PT1M"

$settings = New-ScheduledTaskSettingsSet `
    -RestartCount 10 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 2) `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries

$logonType = if ($UseS4U) { "S4U" } else { "Password" }

$principal = New-ScheduledTaskPrincipal `
    -UserId $TaskUser `
    -LogonType $logonType `
    -RunLevel Highest

$task = New-ScheduledTask `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal

if ($UseS4U) {
    Register-ScheduledTask `
        -TaskName $TaskName `
        -InputObject $task `
        -Force | Out-Null
} else {
    Register-ScheduledTask `
        -TaskName $TaskName `
        -InputObject $task `
        -User $TaskUser `
        -Password $password `
        -Force | Out-Null
}

$createdTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
if (-not $createdTask) {
    throw "Scheduled task '$TaskName' was not found after registration."
}
if ($createdTask.Principal.RunLevel -ne "Highest") {
    throw "Scheduled task '$TaskName' does not have Highest run level."
}
if ($createdTask.Principal.UserId -ne $TaskUser) {
    throw "Scheduled task '$TaskName' is registered for '$($createdTask.Principal.UserId)', expected '$TaskUser'."
}
if ($createdTask.Principal.LogonType -ne $logonType) {
    throw "Scheduled task '$TaskName' logon type is '$($createdTask.Principal.LogonType)', expected '$logonType'."
}

$startupTrigger = $createdTask.Triggers | Where-Object { $_.CimClass.CimClassName -eq "MSFT_TaskBootTrigger" } | Select-Object -First 1
if (-not $startupTrigger) {
    throw "Scheduled task '$TaskName' is missing startup trigger."
}

if ($startupTrigger.Delay -ne "PT1M") {
    throw "Scheduled task '$TaskName' startup delay is '$($startupTrigger.Delay)', expected 'PT1M'."
}

if ($createdTask.Settings.MultipleInstances -ne "IgnoreNew") {
    throw "Scheduled task '$TaskName' multiple-instance policy is '$($createdTask.Settings.MultipleInstances)', expected 'IgnoreNew'."
}

Write-Host ""
Write-Host "Task installed successfully."
Write-Host "Task Name: $TaskName"
Write-Host "Run As:    $TaskUser"
Write-Host "Trigger:   At startup (delay 60s)"
Write-Host "Logon:     $logonType"
Write-Host "Retry:     Every 1 minute, up to 10 times"
Write-Host "Instances: Ignore new if already running"

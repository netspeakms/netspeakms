# Cloudflare Tunnel + Boot Autostart Runbook

## Scope
This runbook covers no-login startup for the Netspeak physical server, including:

- Cloudflare Tunnel availability
- Docker stack startup at boot
- Tracked DB hotfix enforcement for dashboard/login stability
- Validation after reboot or office relocation

Ingress path:

`Cloudflare Edge -> cloudflared tunnel -> Nginx Proxy Manager (localhost:80) -> app/api upstreams`

## Current Tunnel
- Tunnel name: `netspeak-prod`
- Tunnel ID: `9ba3ff61-ae57-48e4-922f-c008755f9d5f`
- Config: `C:\Users\netsp\.cloudflared\config.yml`
- Credentials: `C:\Users\netsp\.cloudflared\9ba3ff61-ae57-48e4-922f-c008755f9d5f.json`

## Startup Modes
### Manual mode (operator button)
```bat
start-netspeak.bat
```

### Boot mode (non-interactive)
```bat
start-netspeak.bat --boot
```

Boot mode uses the PowerShell orchestrator:

`C:\netspeakms-supabase\ops\boot-start.ps1`

Boot orchestration order:

1. Start/verify `cloudflared` (service first, process fallback).
2. Wait for Docker daemon (`docker info`) and try `com.docker.service` before launching Docker Desktop.
3. Start Supabase + NPM compose.
4. Wait for `supabase-db` to become healthy.
5. Apply tracked SQL hotfix: `ops\sql\20260306_announcement_hotfix.sql`.
6. Start app compose.
7. Validate local host-header routes via NPM.

## Deterministic Exit Codes
- `0` success
- `11` cloudflared failure
- `21` Docker unavailable after timeout
- `31` Supabase/NPM compose startup failure
- `32` App compose startup failure
- `41` local route validation failure

Boot log file:

`C:\netspeakms-supabase\ops\logs\boot-start.log`

## Scheduled Task (No-Login Startup)
Install:

```powershell
powershell -ExecutionPolicy Bypass -File .\ops\install-boot-autostart.ps1
```

Optional non-interactive install (password passed explicitly):

```powershell
powershell -ExecutionPolicy Bypass -File .\ops\install-boot-autostart.ps1 -TaskPassword "<PASSWORD>"
```

Remove:

```powershell
powershell -ExecutionPolicy Bypass -File .\ops\uninstall-boot-autostart.ps1
```

Task contract:

- Task name: `NetspeakBootStart`
- Trigger: At startup, delay 60 seconds
- Account: `NETSPEAK\netsp`
- Run level: Highest
- Logon: Whether user is logged on or not
- Retry: every 1 minute, up to 10 attempts
- Multiple instances: Ignore new if task is already running

Verification:

```powershell
Get-ScheduledTask -TaskName NetspeakBootStart | Format-List TaskName,State
```

## Health Checks
```powershell
# Tunnel + local route checks
powershell -ExecutionPolicy Bypass -File .\ops\check-cloudflared.ps1

# Public endpoint checks
powershell -ExecutionPolicy Bypass -File .\ops\monitor-public-endpoints.ps1
```

## Post-Reboot Validation
After reboot (without logging in), verify:

1. `cloudflared` process exists.
2. Docker daemon responds.
3. Containers are running (`nginx-proxy-manager`, app, Supabase services).
4. External URL returns:
   - `https://app.netspeak.com.ph` (expected `200`)
   - `https://api.netspeak.com.ph` (expected `200/401/403` depending auth)

Power-state behavior:

- If the physical server is powered off, the public app/API will be unavailable until power is restored and boot startup finishes.

## Failure Handling
1. Tunnel down:
- Check `boot-start.log` for exit code `11`.
- Validate config/credentials path and restart with `start-netspeak.bat --boot`.

2. Docker not ready:
- Check for exit code `21`.
- Confirm Docker Desktop path: `C:\Program Files\Docker\Docker\Docker Desktop.exe`.

3. Compose failure:
- Exit code `31` or `32`.
- Re-run compose commands manually from repo root and inspect container logs.
- For DB schema mismatch symptoms (e.g., dashboard maintenance due missing `Announcement` columns), run:

```powershell
Get-Content .\ops\sql\20260306_announcement_hotfix.sql -Raw | `
docker exec -i -u postgres supabase-db sh -lc 'export PGPASSWORD="$POSTGRES_PASSWORD"; export PGOPTIONS="-c client_min_messages=warning"; psql -v ON_ERROR_STOP=1 -U supabase_admin -d postgres'
```

4. Route failure:
- Exit code `41`.
- Confirm NPM host routing:
  - `Host: app.netspeak.com.ph -> app upstream`
  - `Host: api.netspeak.com.ph -> Kong/API upstream`

## Move-to-New-Office Checklist
1. Connect server to new network with internet access.
2. Power on server and wait for boot task startup window.
3. Run health checks:
   - `.\ops\check-cloudflared.ps1`
   - `.\ops\monitor-public-endpoints.ps1`
4. Validate external access from mobile data.
5. No DNS changes are required when using the same tunnel credentials.

## Security Notes
- Router port forwarding for 80/443 is not required with Cloudflare Tunnel.
- Keep tunnel credentials private.
- Restrict local admin access and protect scheduled task account credentials.

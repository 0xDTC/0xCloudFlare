# ============================================================
# Cloudflare Auto IP Manager
# Auto-detects IPv4/IPv6, syncs with Cloudflare allowlist,
# removes stale IPs after configurable days of inactivity.
#
# Network-aware: detects gateway + SSID + profile to skip
# updates when still on the same network. Self-installs as
# a Windows Task Scheduler job (hourly + network-change event).
#
# Usage:
#   .\CF-AutoIP-Manager.ps1                  # Manual run
#   .\CF-AutoIP-Manager.ps1 -Install         # Install scheduled tasks (requires Admin)
#   .\CF-AutoIP-Manager.ps1 -Uninstall       # Remove scheduled tasks  (requires Admin)
#   .\CF-AutoIP-Manager.ps1 -Status          # Show current state
#   .\CF-AutoIP-Manager.ps1 -ForceUpdate     # Bypass network check
#   .\CF-AutoIP-Manager.ps1 -DryRun          # Preview changes
#
# IPs without "seen:" in comment are PROTECTED (never auto-removed).
# ============================================================

param(
    [int]$StaleDays = 3,
    [switch]$DryRun,
    [switch]$Silent,
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Status,
    [switch]$ForceUpdate
)

$CF_EMAIL    = "YOUR_CLOUDFLARE_EMAIL"
$CF_API_KEY  = "YOUR_CLOUDFLARE_GLOBAL_API_KEY"
$ACCOUNT_ID  = "YOUR_CLOUDFLARE_ACCOUNT_ID"
$LIST_ID     = "YOUR_CLOUDFLARE_LIST_ID"

$headers = @{
    "X-Auth-Email" = $CF_EMAIL
    "X-Auth-Key"   = $CF_API_KEY
    "Content-Type"  = "application/json"
}

$baseUrl   = "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/rules/lists/$LIST_ID"
$today     = (Get-Date).ToString("yyyy-MM-dd")
$stateDir  = Join-Path $env:APPDATA "CF-AutoIP-Manager"
$stateFile = Join-Path $stateDir "state.json"
$logFile   = Join-Path $stateDir "cf-autoip.log"
$taskName  = "CF-AutoIP-Manager"

# ============================================================
# LOGGING
# ============================================================

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry  = "[$timestamp] $Message"

    if (-not (Test-Path $stateDir)) {
        New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    }

    Add-Content -Path $logFile -Value $logEntry -ErrorAction SilentlyContinue
    if (-not $Silent) {
        Write-Host "  $Message" -ForegroundColor $Color
    }
}

# ============================================================
# NETWORK FINGERPRINTING
# ============================================================

function Get-NetworkFingerprint {
    $gateway     = ""
    $ssid        = ""
    $profileName = ""

    # Default gateway
    try {
        $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Sort-Object -Property RouteMetric |
            Select-Object -First 1
        if ($route) { $gateway = $route.NextHop }
    } catch {}

    # Wi-Fi SSID
    try {
        $wlanOutput = netsh wlan show interfaces 2>$null
        if ($wlanOutput) {
            $ssidLine = $wlanOutput | Select-String '^\s+SSID\s+:\s+(.+)$'
            if ($ssidLine) {
                $ssid = $ssidLine.Matches[0].Groups[1].Value.Trim()
            }
        }
    } catch {}

    # Network profile name
    try {
        $prof = Get-NetConnectionProfile -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($prof) { $profileName = $prof.Name }
    } catch {}

    # SHA-256 hash of the three values
    $raw    = "$gateway|$ssid|$profileName"
    $sha    = [System.Security.Cryptography.SHA256]::Create()
    $bytes  = [System.Text.Encoding]::UTF8.GetBytes($raw)
    $hash   = [System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', ''

    return @{
        Hash        = $hash
        Gateway     = $gateway
        SSID        = $ssid
        ProfileName = $profileName
    }
}

# ============================================================
# STATE FILE
# ============================================================

function Read-State {
    if (Test-Path $stateFile) {
        try {
            return Get-Content $stateFile -Raw | ConvertFrom-Json
        } catch {
            Write-Log "Could not read state file, starting fresh" "Yellow"
        }
    }
    return $null
}

function Save-State {
    param(
        [string]$NetworkHash,
        [string]$Gateway,
        [string]$SSID,
        [string]$ProfileName,
        [string]$PublicIP,
        [string]$PreviousLastUpdate = $null,
        [bool]$CloudflareUpdated = $false
    )

    if (-not (Test-Path $stateDir)) {
        New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    }

    $now = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")

    $state = @{
        networkHash = $NetworkHash
        gateway     = $Gateway
        ssid        = $SSID
        profileName = $ProfileName
        publicIP    = $PublicIP
        lastCheck   = $now
        lastUpdate  = if ($CloudflareUpdated) { $now } elseif ($PreviousLastUpdate) { $PreviousLastUpdate } else { $null }
    }

    $state | ConvertTo-Json | Set-Content $stateFile -Force
}

# ============================================================
# IP DETECTION  (IPv4 preferred, IPv6 fallback)
# ============================================================

function Get-CurrentIPs {
    $ips = @{}

    $ipv4Sources = @(
        @{ Name = "api.ipify.org";         Uri = "https://api.ipify.org?format=json"; Type = "json"; Field = "ip" },
        @{ Name = "ipv4.icanhazip.com";    Uri = "https://ipv4.icanhazip.com";        Type = "text" },
        @{ Name = "ifconfig.io";           Uri = "https://ifconfig.io/ip";             Type = "text" },
        @{ Name = "checkip.amazonaws.com";  Uri = "https://checkip.amazonaws.com";    Type = "text" },
        @{ Name = "ifconfig.me";           Uri = "https://ifconfig.me/ip";             Type = "text" }
    )

    foreach ($source in $ipv4Sources) {
        try {
            if ($source.Type -eq "json") {
                $result    = Invoke-RestMethod -Uri $source.Uri -TimeoutSec 8
                $candidate = $result.($source.Field).Trim()
            } else {
                $candidate = (Invoke-RestMethod -Uri $source.Uri -TimeoutSec 8).Trim()
            }
            if ($candidate -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
                $ips["v4"] = $candidate
                Write-Log "IPv4 detected via $($source.Name): $candidate" "Green"
                break
            }
        } catch {
            Write-Log "IPv4 source $($source.Name) failed: $($_.Exception.Message)" "DarkGray"
        }
    }

    # Only try IPv6 if no IPv4 was found
    if (-not $ips.ContainsKey("v4")) {
        Write-Log "No IPv4 found from any source, falling back to IPv6..." "Yellow"
        $ipv6Sources = @(
            @{ Name = "api6.ipify.org";     Uri = "https://api6.ipify.org";     Type = "text" },
            @{ Name = "ipv6.icanhazip.com"; Uri = "https://ipv6.icanhazip.com"; Type = "text" },
            @{ Name = "ifconfig.io";        Uri = "https://ifconfig.io/ip";      Type = "text" },
            @{ Name = "ifconfig.me";        Uri = "https://ifconfig.me/ip";      Type = "text" },
            @{ Name = "ipinfo.io";          Uri = "https://ipinfo.io/ip";        Type = "text" }
        )

        foreach ($source in $ipv6Sources) {
            try {
                $candidate = (Invoke-RestMethod -Uri $source.Uri -TimeoutSec 8).Trim()
                if ($candidate -match ':') {
                    $ips["v6"] = $candidate
                    Write-Log "IPv6 detected via $($source.Name): $candidate" "Green"
                    break
                }
            } catch {
                Write-Log "IPv6 source $($source.Name) failed: $($_.Exception.Message)" "DarkGray"
            }
        }
    }

    return $ips
}

# ============================================================
# CLOUDFLARE API HELPERS
# ============================================================

function Get-CloudflareList {
    try {
        $response = Invoke-RestMethod -Uri "$baseUrl/items" -Headers $headers -Method Get
        return $response.result
    } catch {
        Write-Log "ERROR: Failed to fetch Cloudflare list - $($_.Exception.Message)" "Red"
        return @()
    }
}

function Add-CloudflareIP {
    param([string]$IP, [string]$Comment)
    if ($DryRun) {
        Write-Log "[DRY RUN] Would add: $IP ($Comment)" "Cyan"
        return $true
    }
    try {
        $body = @(@{ ip = $IP; comment = $Comment }) | ConvertTo-Json -AsArray
        $response = Invoke-RestMethod -Uri "$baseUrl/items" -Headers $headers -Method Post -Body $body
        return $response.success
    } catch {
        Write-Log "ERROR adding $IP : $($_.Exception.Message)" "Red"
        return $false
    }
}

function Remove-CloudflareIP {
    param([string]$ItemID, [string]$IP)
    if ($DryRun) {
        Write-Log "[DRY RUN] Would remove: $IP (ID: $ItemID)" "Cyan"
        return $true
    }
    try {
        $body = @{ items = @(@{ id = $ItemID }) } | ConvertTo-Json -Depth 3
        $response = Invoke-RestMethod -Uri "$baseUrl/items" -Headers $headers -Method Delete -Body $body
        return $response.success
    } catch {
        Write-Log "ERROR removing $IP : $($_.Exception.Message)" "Red"
        return $false
    }
}

function Parse-SeenDate {
    param([string]$Comment)
    if ($Comment -match 'seen:(\d{4}-\d{2}-\d{2})') {
        try {
            return [datetime]::ParseExact($matches[1], "yyyy-MM-dd", $null)
        } catch {
            return $null
        }
    }
    return $null
}

# ============================================================
# TASK SCHEDULER  (-Install / -Uninstall)
# ============================================================

function Install-ScheduledTasks {
    $scriptPath = $PSCommandPath
    if (-not $scriptPath) {
        Write-Host "  ERROR: Cannot determine script path. Run the script from a file." -ForegroundColor Red
        return
    }

    $isAdmin = ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Host "  ERROR: -Install requires Administrator privileges." -ForegroundColor Red
        Write-Host "  Right-click PowerShell > 'Run as administrator' and try again." -ForegroundColor Yellow
        return
    }

    # Clean up any previous tasks
    Unregister-ScheduledTask -TaskName $taskName                  -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName "$taskName-NetworkChange"  -Confirm:$false -ErrorAction SilentlyContinue

    $action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" -Silent"

    # --- Hourly trigger ---
    $hourlyTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Hours 1)

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RunOnlyIfNetworkAvailable `
        -MultipleInstances IgnoreNew

    Register-ScheduledTask `
        -TaskName    $taskName `
        -Action      $action `
        -Trigger     $hourlyTrigger `
        -Settings    $settings `
        -Description "Cloudflare Auto IP Manager - Hourly check" `
        -RunLevel    Highest | Out-Null

    Write-Host "  Installed hourly task: $taskName" -ForegroundColor Green

    # --- Network-change event trigger (Event ID 10000) ---
    $eventSubscription = '<QueryList><Query Id="0" Path="Microsoft-Windows-NetworkProfile/Operational"><Select Path="Microsoft-Windows-NetworkProfile/Operational">*[System[EventID=10000]]</Select></Query></QueryList>'

    $taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>$([System.Security.SecurityElement]::Escape($eventSubscription))</Subscription>
      <Delay>PT30S</Delay>
    </EventTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>true</RunOnlyIfNetworkAvailable>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-ExecutionPolicy Bypass -WindowStyle Hidden -File &quot;$scriptPath&quot; -Silent</Arguments>
    </Exec>
  </Actions>
</Task>
"@

    $tempXml = Join-Path $env:TEMP "cf-autoip-network-task.xml"
    try {
        $taskXml | Out-File -FilePath $tempXml -Encoding Unicode -Force
        $schtasksOutput = schtasks.exe /Create /TN "$taskName-NetworkChange" /XML "$tempXml" /F 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Installed network-change task: $taskName-NetworkChange" -ForegroundColor Green
        } else {
            Write-Host "  WARNING: Could not create network event trigger." -ForegroundColor Yellow
            Write-Host "  $schtasksOutput" -ForegroundColor DarkGray
            Write-Host "  The hourly task is still active." -ForegroundColor Yellow
        }
    } finally {
        Remove-Item $tempXml -Force -ErrorAction SilentlyContinue
    }

    # Ensure state directory exists
    if (-not (Test-Path $stateDir)) {
        New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    }

    Write-Host ""
    Write-Host "  Installation complete!" -ForegroundColor Green
    Write-Host "    Hourly check  : every 1 hour"           -ForegroundColor Cyan
    Write-Host "    Network change : triggers on connect (30 s delay)" -ForegroundColor Cyan
    Write-Host "    State dir      : $stateDir"              -ForegroundColor Cyan
    Write-Host "    Log file       : $logFile"               -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Run with -Status to verify." -ForegroundColor DarkGray
}

function Uninstall-ScheduledTasks {
    $isAdmin = ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Host "  ERROR: -Uninstall requires Administrator privileges." -ForegroundColor Red
        return
    }

    $removed = $false

    foreach ($name in @($taskName, "$taskName-NetworkChange")) {
        try {
            Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction Stop
            Write-Host "  Removed task: $name" -ForegroundColor Green
            $removed = $true
        } catch {
            Write-Host "  Task '$name' not found or already removed." -ForegroundColor Yellow
        }
    }

    if ($removed) {
        Write-Host ""
        $cleanState = Read-Host "  Also remove state directory ($stateDir)? (y/n)"
        if ($cleanState -eq 'y') {
            Remove-Item $stateDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "  State directory removed." -ForegroundColor Green
        }
    }

    Write-Host "  Uninstall complete." -ForegroundColor Green
}

# ============================================================
# STATUS DISPLAY  (-Status)
# ============================================================

function Show-Status {
    Write-Host ""
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host "  Cloudflare Auto IP Manager - Status"         -ForegroundColor Cyan
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host ""

    # Current network
    $fp = Get-NetworkFingerprint
    Write-Host "  Current Network:" -ForegroundColor White
    Write-Host "    Gateway : $($fp.Gateway)"                                                          -ForegroundColor DarkGray
    Write-Host "    SSID    : $(if ($fp.SSID) { $fp.SSID } else { '(wired / none)' })"                -ForegroundColor DarkGray
    Write-Host "    Profile : $($fp.ProfileName)"                                                      -ForegroundColor DarkGray
    Write-Host "    Hash    : $($fp.Hash.Substring(0,16))..."                                          -ForegroundColor DarkGray
    Write-Host ""

    # Saved state
    $state = Read-State
    if ($state) {
        $hashMatch = $state.networkHash -eq $fp.Hash
        Write-Host "  Saved State:" -ForegroundColor White
        Write-Host "    Public IP   : $($state.publicIP)"                                              -ForegroundColor DarkGray
        Write-Host "    Gateway     : $($state.gateway)"                                               -ForegroundColor DarkGray
        Write-Host "    SSID        : $(if ($state.ssid) { $state.ssid } else { '(wired / none)' })"   -ForegroundColor DarkGray
        Write-Host "    Last check  : $($state.lastCheck)"                                             -ForegroundColor DarkGray
        Write-Host "    Last update : $(if ($state.lastUpdate) { $state.lastUpdate } else { 'never' })"-ForegroundColor DarkGray
        Write-Host "    Network     : $(if ($hashMatch) { 'SAME  (no update needed)' } else { 'CHANGED  (update pending)' })" `
            -ForegroundColor $(if ($hashMatch) { 'Green' } else { 'Yellow' })
    } else {
        Write-Host "  No saved state (first run pending)." -ForegroundColor Yellow
    }
    Write-Host ""

    # Scheduled tasks
    Write-Host "  Scheduled Tasks:" -ForegroundColor White
    foreach ($name in @($taskName, "$taskName-NetworkChange")) {
        try {
            $task = Get-ScheduledTask -TaskName $name -ErrorAction Stop
            $color = if ($task.State -eq 'Ready') { 'Green' } else { 'Yellow' }
            Write-Host "    $name : $($task.State)" -ForegroundColor $color
        } catch {
            Write-Host "    $name : NOT INSTALLED" -ForegroundColor Red
        }
    }
    Write-Host ""
}

# ============================================================
# DISPATCH: -Install / -Uninstall / -Status
# ============================================================

if ($Install)   { Install-ScheduledTasks;   exit }
if ($Uninstall) { Uninstall-ScheduledTasks; exit }
if ($Status)    { Show-Status;              exit }

# ============================================================
# MAIN  — normal run (manual, hourly, or network-event)
# ============================================================

if (-not $Silent) {
    Write-Host ""
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host "  Cloudflare Auto IP Manager"                   -ForegroundColor Cyan
    Write-Host "  Stale threshold: $StaleDays days"             -ForegroundColor DarkCyan
    if ($DryRun)      { Write-Host "  MODE: DRY RUN (no changes)"  -ForegroundColor Yellow }
    if ($ForceUpdate) { Write-Host "  MODE: FORCE UPDATE"          -ForegroundColor Yellow }
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host ""
}

Write-Log "--- Run started ---"

# Step 1: Network fingerprint check
$fingerprint = Get-NetworkFingerprint
Write-Log "Network fingerprint: gw=$($fingerprint.Gateway)  ssid=$($fingerprint.SSID)  profile=$($fingerprint.ProfileName)" "DarkGray"

$prevState       = Read-State
$previousUpdate  = if ($prevState -and $prevState.lastUpdate) { $prevState.lastUpdate } else { $null }
$networkChanged  = $true

if (-not $ForceUpdate -and $prevState -and $prevState.networkHash -eq $fingerprint.Hash) {
    $networkChanged = $false
    Write-Log "Same network as last check - skipping Cloudflare update" "Green"

    # Still save the check timestamp
    Save-State `
        -NetworkHash       $fingerprint.Hash `
        -Gateway           $fingerprint.Gateway `
        -SSID              $fingerprint.SSID `
        -ProfileName       $fingerprint.ProfileName `
        -PublicIP           $(if ($prevState.publicIP) { $prevState.publicIP } else { "" }) `
        -PreviousLastUpdate $previousUpdate

    Write-Log "--- Run complete (no change) ---"
    exit 0
}

if ($ForceUpdate) {
    Write-Log "Force-update requested, bypassing network check" "Yellow"
} else {
    Write-Log "Network change detected - proceeding with IP update" "Yellow"
}

# Step 2: Detect current public IP
Write-Log "Detecting current IP (IPv4 preferred)..." "Cyan"
$currentIPs = Get-CurrentIPs

if ($currentIPs.Count -eq 0) {
    Write-Log "FATAL: Could not detect any IP address. Aborting." "Red"
    exit 1
}

foreach ($key in $currentIPs.Keys) {
    Write-Log "Detected $key : $($currentIPs[$key])" "Green"
}

# Step 3: Fetch Cloudflare list
Write-Log "Fetching Cloudflare allowlist..." "Cyan"
$cfList = Get-CloudflareList

if (-not $Silent) {
    Write-Host ""
    Write-Host "  Current allowlist:" -ForegroundColor White
    foreach ($item in $cfList) {
        $comment = if ($item.comment) { $item.comment } else { "no comment" }
        Write-Host "    $($item.ip) - $comment" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# Step 4: Build lookup of existing IPs
$existingIPs = @{}
foreach ($item in $cfList) {
    $existingIPs[$item.ip] = $item
}

# Step 5: Add / Update current IPs
$cloudflareUpdated = $false

foreach ($key in $currentIPs.Keys) {
    $ip       = $currentIPs[$key]
    $label    = if ($key -eq "v4") { "IPv4" } else { "IPv6" }
    $newComment = "Auto $label | seen:$today"

    if ($existingIPs.ContainsKey($ip)) {
        $existing = $existingIPs[$ip]
        $seenDate = Parse-SeenDate $existing.comment

        if ($seenDate -and $seenDate.ToString("yyyy-MM-dd") -eq $today) {
            Write-Log "$label $ip already up to date (seen today)" "DarkGray"
        } else {
            Write-Log "Updating $label $ip (refreshing seen date)" "Yellow"
            if (Remove-CloudflareIP -ItemID $existing.id -IP $ip) {
                Start-Sleep -Seconds 1
                if (Add-CloudflareIP -IP $ip -Comment $newComment) {
                    Write-Log "Updated $label $ip - seen:$today" "Green"
                    $cloudflareUpdated = $true
                }
            }
        }
    } else {
        Write-Log "New $label detected: $ip - adding to allowlist" "Green"
        if (Add-CloudflareIP -IP $ip -Comment $newComment) {
            Write-Log "Added $ip to allowlist" "Green"
            $cloudflareUpdated = $true
        }
    }
}

# Step 6: Clean up stale IPs
Write-Log "Checking for stale IPs (>$StaleDays days)..." "Cyan"
$cutoffDate = (Get-Date).AddDays(-$StaleDays)

foreach ($item in $cfList) {
    $ip      = $item.ip
    $comment = $item.comment

    # Skip current IPs (just updated)
    if ($currentIPs.Values -contains $ip) { continue }

    # Skip PROTECTED IPs (no "seen:" in comment = manually added)
    $seenDate = Parse-SeenDate $comment
    if (-not $seenDate) {
        Write-Log "Protected: $ip ($comment) - no auto-removal" "DarkGray"
        continue
    }

    if ($seenDate -lt $cutoffDate) {
        $daysOld = ((Get-Date) - $seenDate).Days
        Write-Log "STALE: $ip (last seen ${daysOld}d ago) - removing" "Red"
        if (Remove-CloudflareIP -ItemID $item.id -IP $ip) {
            Write-Log "Removed stale IP: $ip" "Red"
            $cloudflareUpdated = $true
        }
    } else {
        $daysOld = ((Get-Date) - $seenDate).Days
        Write-Log "OK: $ip (last seen ${daysOld}d ago, threshold: ${StaleDays}d)" "DarkGray"
    }
}

# Step 7: Save state
$primaryIP = if ($currentIPs.ContainsKey("v4")) { $currentIPs["v4"] } else { $currentIPs["v6"] }

Save-State `
    -NetworkHash        $fingerprint.Hash `
    -Gateway            $fingerprint.Gateway `
    -SSID               $fingerprint.SSID `
    -ProfileName        $fingerprint.ProfileName `
    -PublicIP            $primaryIP `
    -PreviousLastUpdate  $previousUpdate `
    -CloudflareUpdated   $cloudflareUpdated

# Step 8: Show final state
if (-not $Silent) {
    Write-Host ""
    Write-Log "Fetching final list..." "Cyan"
    Start-Sleep -Seconds 2
    $finalList = Get-CloudflareList
    Write-Host ""
    Write-Host "  Final allowlist:" -ForegroundColor Green
    Write-Host "  ------------------------------------" -ForegroundColor DarkGray
    foreach ($item in $finalList) {
        $comment = if ($item.comment) { $item.comment } else { "no comment" }
        Write-Host "    $($item.ip)" -ForegroundColor White -NoNewline
        Write-Host " - $comment" -ForegroundColor DarkGray
    }
    Write-Host "  ------------------------------------" -ForegroundColor DarkGray
    Write-Host "  Total: $($finalList.Count) IPs" -ForegroundColor Cyan
    Write-Host ""
}

Write-Log "--- Run complete ---"

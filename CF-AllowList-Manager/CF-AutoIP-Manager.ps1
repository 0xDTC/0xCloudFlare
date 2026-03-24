# ============================================================
# Cloudflare Auto IP Manager
# Auto-detects IPv4/IPv6, syncs with Cloudflare allowlist,
# removes stale IPs after 10 days of inactivity.
#
# Run manually or schedule via Task Scheduler.
# IPs without "seen:" in comment are PROTECTED (never auto-removed).
# ============================================================

param(
    [int]$StaleDays = 10,
    [switch]$DryRun,
    [switch]$Silent
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

$baseUrl = "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/rules/lists/$LIST_ID"
$today   = (Get-Date).ToString("yyyy-MM-dd")
$logFile = Join-Path $PSScriptRoot "cf-autoip.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    Add-Content -Path $logFile -Value $logEntry -ErrorAction SilentlyContinue
    if (-not $Silent) {
        Write-Host "  $Message" -ForegroundColor $Color
    }
}

function Get-CurrentIPs {
    $ips = @{}

    # Get IPv4
    try {
        $ipv4 = (Invoke-RestMethod -Uri "https://ifconfig.io/ip" -TimeoutSec 10).Trim()
        if ($ipv4 -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
            $ips["v4"] = $ipv4
        }
    } catch {
        Write-Log "Could not detect IPv4: $($_.Exception.Message)" "Yellow"
    }

    # Get IPv6
    try {
        # Force IPv6 connection
        $ipv6 = (Invoke-RestMethod -Uri "https://ifconfig.io/ip" -TimeoutSec 10 -ConnectionUri "https://[2606:4700:4700::1111]/cdn-cgi/trace").Trim()
        # Fallback: try v6 specific endpoint
        if ($ipv6 -notmatch ':') {
            $ipv6 = (Invoke-RestMethod -Uri "https://v6.ifconfig.io/ip" -TimeoutSec 10).Trim()
        }
        if ($ipv6 -match ':') {
            $ips["v6"] = $ipv6
        }
    } catch {
        # Try alternate IPv6 detection
        try {
            $ipv6 = (Invoke-RestMethod -Uri "https://api64.ipify.org" -TimeoutSec 10).Trim()
            if ($ipv6 -match ':') {
                $ips["v6"] = $ipv6
            }
        } catch {
            Write-Log "Could not detect IPv6 (may not be available)" "Yellow"
        }
    }

    return $ips
}

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
# MAIN
# ============================================================

if (-not $Silent) {
    Write-Host ""
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host "  Cloudflare Auto IP Manager" -ForegroundColor Cyan
    Write-Host "  Stale threshold: $StaleDays days" -ForegroundColor DarkCyan
    if ($DryRun) { Write-Host "  MODE: DRY RUN (no changes)" -ForegroundColor Yellow }
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host ""
}

Write-Log "--- Run started ---"

# Step 1: Detect current IPs
Write-Log "Detecting current IPs from ifconfig.io..." "Cyan"
$currentIPs = Get-CurrentIPs

if ($currentIPs.Count -eq 0) {
    Write-Log "FATAL: Could not detect any IP address. Aborting." "Red"
    exit 1
}

foreach ($key in $currentIPs.Keys) {
    Write-Log "Detected $key : $($currentIPs[$key])" "Green"
}

# Step 2: Get current Cloudflare list
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

# Step 3: Build lookup of existing IPs
$existingIPs = @{}
foreach ($item in $cfList) {
    $existingIPs[$item.ip] = $item
}

# Step 4: Add/Update current IPs
foreach ($key in $currentIPs.Keys) {
    $ip = $currentIPs[$key]
    $label = if ($key -eq "v4") { "IPv4" } else { "IPv6" }
    $newComment = "Carlos - Auto $label | seen:$today"

    if ($existingIPs.ContainsKey($ip)) {
        $existing = $existingIPs[$ip]
        $seenDate = Parse-SeenDate $existing.comment

        if ($seenDate -and $seenDate.ToString("yyyy-MM-dd") -eq $today) {
            Write-Log "$label $ip already up to date (seen today)" "DarkGray"
        } else {
            # Update: remove old entry, add with new timestamp
            Write-Log "Updating $label $ip (refreshing seen date)" "Yellow"
            if (Remove-CloudflareIP -ItemID $existing.id -IP $ip) {
                Start-Sleep -Seconds 1
                if (Add-CloudflareIP -IP $ip -Comment $newComment) {
                    Write-Log "Updated $label $ip - seen:$today" "Green"
                }
            }
        }
    } else {
        # New IP - add it
        Write-Log "New $label detected: $ip - adding to allowlist" "Green"
        if (Add-CloudflareIP -IP $ip -Comment $newComment) {
            Write-Log "Added $ip to allowlist" "Green"
        }
    }
}

# Step 5: Clean up stale IPs
Write-Log "Checking for stale IPs (>$StaleDays days)..." "Cyan"
$cutoffDate = (Get-Date).AddDays(-$StaleDays)

foreach ($item in $cfList) {
    $ip = $item.ip
    $comment = $item.comment

    # Skip current IPs (just updated)
    if ($currentIPs.Values -contains $ip) { continue }

    # Skip PROTECTED IPs (no "seen:" in comment = manually added)
    $seenDate = Parse-SeenDate $comment
    if (-not $seenDate) {
        Write-Log "Protected: $ip ($comment) - no auto-removal" "DarkGray"
        continue
    }

    # Check if stale
    if ($seenDate -lt $cutoffDate) {
        $daysOld = ((Get-Date) - $seenDate).Days
        Write-Log "STALE: $ip (last seen ${daysOld}d ago) - removing" "Red"
        if (Remove-CloudflareIP -ItemID $item.id -IP $ip) {
            Write-Log "Removed stale IP: $ip" "Red"
        }
    } else {
        $daysOld = ((Get-Date) - $seenDate).Days
        Write-Log "OK: $ip (last seen ${daysOld}d ago, threshold: ${StaleDays}d)" "DarkGray"
    }
}

# Step 6: Show final state
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
Write-Log ""

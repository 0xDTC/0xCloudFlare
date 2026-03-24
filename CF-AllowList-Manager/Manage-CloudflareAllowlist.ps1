# ============================================================
# Cloudflare IP Allowlist Manager
# Manages the allowed_admin_ips list for WordPress WAF rules
# ============================================================

$CF_EMAIL = "YOUR_CLOUDFLARE_EMAIL"
$CF_API_KEY = "YOUR_CLOUDFLARE_GLOBAL_API_KEY"
$ACCOUNT_ID = "YOUR_CLOUDFLARE_ACCOUNT_ID"
$LIST_ID = "YOUR_CLOUDFLARE_LIST_ID"

$headers = @{
    "X-Auth-Email"  = $CF_EMAIL
    "X-Auth-Key"    = $CF_API_KEY
    "Content-Type"  = "application/json"
}

$baseUrl = "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/rules/lists/$LIST_ID"

function Show-Banner {
    Clear-Host
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  Cloudflare IP Allowlist Manager" -ForegroundColor Cyan
    Write-Host "  List: allowed_admin_ips" -ForegroundColor DarkCyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
}

function Get-AllowedIPs {
    try {
        $response = Invoke-RestMethod -Uri "$baseUrl/items" -Headers $headers -Method Get
        return $response.result
    } catch {
        Write-Host "  ERROR: Failed to fetch IP list - $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

function Show-IPList {
    $ips = Get-AllowedIPs
    if ($ips.Count -eq 0) {
        Write-Host "  No IPs in the allowlist." -ForegroundColor Yellow
        return
    }

    Write-Host "  Current Allowed IPs:" -ForegroundColor Green
    Write-Host "  ------------------------------------" -ForegroundColor DarkGray
    $i = 1
    foreach ($item in $ips) {
        $comment = if ($item.comment) { $item.comment } else { "no comment" }
        Write-Host "  [$i] $($item.ip)" -ForegroundColor White -NoNewline
        Write-Host " - $comment" -ForegroundColor DarkGray
        $i++
    }
    Write-Host "  ------------------------------------" -ForegroundColor DarkGray
    Write-Host "  Total: $($ips.Count) IPs" -ForegroundColor DarkCyan
    Write-Host ""
}

function Add-IP {
    $ip = Read-Host "  Enter IP address to add (or 'auto' for your current IP)"

    if ($ip -eq "auto") {
        try {
            $ip = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 5).Trim()
            Write-Host "  Your current IP: $ip" -ForegroundColor Cyan
        } catch {
            Write-Host "  ERROR: Could not detect your IP" -ForegroundColor Red
            return
        }
    }

    # Validate IP format (basic check)
    if ($ip -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$' -and $ip -notmatch ':') {
        Write-Host "  ERROR: Invalid IP format" -ForegroundColor Red
        return
    }

    $comment = Read-Host "  Enter a comment (e.g. 'Carlos - Home', 'Carlos - Office')"
    if ([string]::IsNullOrWhiteSpace($comment)) { $comment = "Added $(Get-Date -Format 'yyyy-MM-dd HH:mm')" }

    $body = @(
        @{
            ip      = $ip
            comment = $comment
        }
    ) | ConvertTo-Json -AsArray

    try {
        $response = Invoke-RestMethod -Uri "$baseUrl/items" -Headers $headers -Method Post -Body $body
        if ($response.success) {
            Write-Host "  Added $ip successfully!" -ForegroundColor Green
        } else {
            Write-Host "  ERROR: $($response.errors | ConvertTo-Json)" -ForegroundColor Red
        }
    } catch {
        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Remove-IP {
    $ips = Get-AllowedIPs
    if ($ips.Count -eq 0) {
        Write-Host "  No IPs to remove." -ForegroundColor Yellow
        return
    }

    Show-IPList

    $selection = Read-Host "  Enter the number(s) to remove (comma-separated, e.g. '1,3')"
    $indices = $selection -split ',' | ForEach-Object { $_.Trim() }

    $itemsToRemove = @()
    foreach ($idx in $indices) {
        $num = [int]$idx
        if ($num -ge 1 -and $num -le $ips.Count) {
            $item = $ips[$num - 1]
            $itemsToRemove += @{ id = $item.id }
            Write-Host "  Will remove: $($item.ip) ($($item.comment))" -ForegroundColor Yellow
        } else {
            Write-Host "  Skipping invalid number: $idx" -ForegroundColor Red
        }
    }

    if ($itemsToRemove.Count -eq 0) {
        Write-Host "  Nothing to remove." -ForegroundColor Yellow
        return
    }

    $confirm = Read-Host "  Confirm removal of $($itemsToRemove.Count) IP(s)? (y/n)"
    if ($confirm -ne 'y') {
        Write-Host "  Cancelled." -ForegroundColor Yellow
        return
    }

    $body = @{ items = $itemsToRemove } | ConvertTo-Json -Depth 3

    try {
        $response = Invoke-RestMethod -Uri "$baseUrl/items" -Headers $headers -Method Delete -Body $body
        if ($response.success) {
            Write-Host "  Removed $($itemsToRemove.Count) IP(s) successfully!" -ForegroundColor Green
        } else {
            Write-Host "  ERROR: $($response.errors | ConvertTo-Json)" -ForegroundColor Red
        }
    } catch {
        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Main menu loop
while ($true) {
    Show-Banner
    Show-IPList

    Write-Host "  Options:" -ForegroundColor White
    Write-Host "  [1] Add an IP" -ForegroundColor Green
    Write-Host "  [2] Remove an IP" -ForegroundColor Red
    Write-Host "  [3] Refresh list" -ForegroundColor Cyan
    Write-Host "  [4] Add my current IP (auto-detect)" -ForegroundColor Green
    Write-Host "  [0] Exit" -ForegroundColor DarkGray
    Write-Host ""

    $choice = Read-Host "  Choose an option"

    switch ($choice) {
        "1" { Add-IP }
        "2" { Remove-IP }
        "3" { } # Just refreshes on next loop
        "4" {
            try {
                $myip = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 5).Trim()
                $comment = "Carlos - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
                $body = @(@{ ip = $myip; comment = $comment }) | ConvertTo-Json -AsArray
                $response = Invoke-RestMethod -Uri "$baseUrl/items" -Headers $headers -Method Post -Body $body
                if ($response.success) {
                    Write-Host "  Added $myip successfully!" -ForegroundColor Green
                }
            } catch {
                Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        "0" {
            Write-Host "  Goodbye!" -ForegroundColor Cyan
            exit
        }
        default { Write-Host "  Invalid option." -ForegroundColor Red }
    }

    Write-Host ""
    Write-Host "  Press Enter to continue..." -ForegroundColor DarkGray
    Read-Host
}

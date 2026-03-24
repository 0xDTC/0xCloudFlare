<a href="https://www.buymeacoffee.com/0xDTC"><img src="https://img.buymeacoffee.com/button-api/?text=Buy me a knowledge&emoji=📖&slug=0xDTC&button_colour=FF5F5F&font_colour=ffffff&font_family=Comic&outline_colour=000000&coffee_colour=FFDD00" /></a>

# CF-AllowList-Manager
PowerShell scripts to manage Cloudflare IP allowlists used by WAF custom rules. Designed for restricting access to sensitive paths (e.g. admin panels, config files) to only authorized IPs.

---

## Table of Contents
- [Features](#features)
- [Scripts Overview](#scripts-overview)
- [Prerequisites](#prerequisites)
- [Configuration](#configuration)
- [Usage](#usage)
  - [Interactive Menu](#interactive-menu)
  - [Auto IP Updater](#auto-ip-updater)
- [WAF Rules](#waf-rules)
- [Scheduling](#scheduling)
- [Troubleshooting](#troubleshooting)

---

## Features

- Interactive menu to view, add, and remove IPs from a Cloudflare IP list
- Auto-detect IPv4 and IPv6 via ifconfig.io
- Auto-remove stale IPs after a configurable number of days
- Protected IPs (manually added) are never auto-removed
- Silent mode with file logging for scheduled tasks
- Dry-run mode to preview changes without applying them

---

## Scripts Overview

### `Manage-CloudflareAllowlist.ps1`
Interactive menu for managing the Cloudflare IP allowlist. View current IPs, add new ones manually or auto-detect, and remove old ones with confirmation.

### `CF-AutoIP-Manager.ps1`
Automated script that detects the current machine's public IPv4/IPv6, syncs them with the Cloudflare allowlist, and removes IPs that haven't been seen for a configurable number of days (default: 10).

---

## Prerequisites

- Windows 10/11 with PowerShell 5.1+
- Cloudflare account with:
  - A **Cloudflare IP List** (kind: `ip`)
  - **WAF Custom Rules** referencing the list
  - **Global API Key** and account email

---

## Configuration

Edit the variables at the top of each script:

```powershell
$CF_EMAIL    = "YOUR_CLOUDFLARE_EMAIL"
$CF_API_KEY  = "YOUR_CLOUDFLARE_GLOBAL_API_KEY"
$ACCOUNT_ID  = "YOUR_CLOUDFLARE_ACCOUNT_ID"
$LIST_ID     = "YOUR_CLOUDFLARE_LIST_ID"
```

**How to find these values:**
| Variable | Where to find it |
|----------|-----------------|
| `CF_EMAIL` | The email you login to Cloudflare with |
| `CF_API_KEY` | Cloudflare Dashboard > My Profile > API Tokens > Global API Key |
| `ACCOUNT_ID` | Cloudflare Dashboard > any domain > Overview > right sidebar under "API" |
| `LIST_ID` | Create a list via API or Dashboard (Manage Account > Configurations > Lists) |

### Create the IP List (one-time setup)
```bash
curl -X POST "https://api.cloudflare.com/client/v4/accounts/YOUR_ACCOUNT_ID/rules/lists" \
  -H "X-Auth-Email: admin@example.com" \
  -H "X-Auth-Key: your_global_api_key" \
  -H "Content-Type: application/json" \
  -d '{"name":"allowed_admin_ips","description":"IPs allowed to access admin and sensitive files","kind":"ip"}'
```

Copy the returned `id` — that's your `LIST_ID`.

---

## Usage

If you get an execution policy error, run this once:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Interactive Menu

```powershell
.\Manage-CloudflareAllowlist.ps1
```

**Example Output:**
```
============================================
  Cloudflare IP Allowlist Manager
  List: allowed_admin_ips
============================================

  Current Allowed IPs:
  ------------------------------------
  [1] 203.0.113.45 - Admin - Home
  [2] 198.51.100.10 - Web Server - DO NOT REMOVE
  [3] 2001:db8::1 - Admin - Office IPv6
  ------------------------------------
  Total: 3 IPs

  Options:
  [1] Add an IP
  [2] Remove an IP
  [3] Refresh list
  [4] Add my current IP (auto-detect)
  [0] Exit
```

| Option | Action |
|--------|--------|
| 1 | Enter an IP manually, or type `auto` to detect your current IP |
| 2 | Select IPs by number to remove (e.g. `1,3`) with confirmation |
| 3 | Refresh the list |
| 4 | One-click: detect your public IP and add it |
| 0 | Exit |

---

### Auto IP Updater

**Basic run** — detect IPs, sync list, clean stale entries:
```powershell
.\CF-AutoIP-Manager.ps1
```

**Dry run** — preview what would happen without making changes:
```powershell
.\CF-AutoIP-Manager.ps1 -DryRun
```

**Custom stale threshold** (e.g. 5 days instead of 10):
```powershell
.\CF-AutoIP-Manager.ps1 -StaleDays 5
```

**Silent mode** (for scheduled tasks, logs to `cf-autoip.log`):
```powershell
.\CF-AutoIP-Manager.ps1 -Silent
```

**Example Output:**
```
  ============================================
  Cloudflare Auto IP Manager
  Stale threshold: 10 days
  ============================================

  Detecting current IPs from ifconfig.io...
  Detected v4 : 203.0.113.45
  Detected v6 : 2001:db8::1

  Current allowlist:
    198.51.100.10 - Web Server - DO NOT REMOVE
    203.0.113.45 - Admin - Auto IPv4 | seen:2026-03-20
    192.0.2.99 - Admin - Auto IPv4 | seen:2026-03-10

  Updating IPv4 203.0.113.45 (refreshing seen date)
  New IPv6 detected: 2001:db8::1 - adding to allowlist

  Checking for stale IPs (>10 days)...
  Protected: 198.51.100.10 (Web Server) - no auto-removal
  OK: 203.0.113.45 (last seen 0d ago, threshold: 10d)
  STALE: 192.0.2.99 (last seen 14d ago) - removing

  Final allowlist:
  ------------------------------------
    198.51.100.10 - Web Server - DO NOT REMOVE
    203.0.113.45 - Admin - Auto IPv4 | seen:2026-03-24
    2001:db8::1 - Admin - Auto IPv6 | seen:2026-03-24
  ------------------------------------
  Total: 3 IPs
```

### How Stale Detection Works

| Comment Format | Behavior |
|----------------|----------|
| `Admin - Auto IPv4 \| seen:2026-03-24` | Auto-managed. Removed if not seen for N+ days. |
| `Web Server - DO NOT REMOVE` | Protected. Never auto-removed (no `seen:` tag). |
| `Admin - Home` | Protected. Manually added IPs are never auto-removed. |

The script uses the `seen:YYYY-MM-DD` tag in the Cloudflare list item comment to track when an IP was last active. IPs without this tag are always protected.

---

## WAF Rules

These scripts are designed to work with Cloudflare WAF custom rules that reference the IP list. Example rules:

| # | Rule | Action | Allowlist Bypass |
|---|------|--------|:---:|
| 1 | Block sensitive files (config, xmlrpc, debug logs) + admin panel | Block | Yes |
| 2 | Block PHP execution in upload/cache directories | Block | No |
| 3 | Block malicious query strings (SQLi, XSS, LFI) | Block | No |
| 4 | Challenge login page POST requests | Managed Challenge | Yes |

**Deploy rules to a zone:**
```bash
curl -X POST "https://api.cloudflare.com/client/v4/zones/YOUR_ZONE_ID/rulesets" \
  -H "X-Auth-Email: admin@example.com" \
  -H "X-Auth-Key: your_global_api_key" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Security Rules",
    "kind": "zone",
    "phase": "http_request_firewall_custom",
    "rules": [
      {
        "action": "block",
        "expression": "((http.request.uri.path contains \"/wp-config\") or (http.request.uri.path eq \"/xmlrpc.php\") or (http.request.uri.path contains \"/debug.log\") or (http.request.uri.path contains \"/wp-admin/\" and not http.request.uri.path contains \"/wp-admin/admin-ajax.php\" and not http.request.uri.path contains \"/wp-admin/css/\" and not http.request.uri.path contains \"/wp-admin/js/\")) and not ip.src in $allowed_admin_ips",
        "description": "Block sensitive files + admin panel (allowlist bypass)"
      },
      {
        "action": "block",
        "expression": "(http.request.uri.path contains \"/wp-content/uploads/\" and http.request.uri.path contains \".php\") or (http.request.uri.path contains \"/wp-content/cache/\" and http.request.uri.path contains \".php\")",
        "description": "Block PHP execution in uploads/cache"
      },
      {
        "action": "block",
        "expression": "(http.request.uri.query contains \"eval(\") or (http.request.uri.query contains \"base64_decode\") or (http.request.uri.query contains \"<script\") or (http.request.uri.query contains \"../../../\") or (http.request.uri.query contains \"UNION+SELECT\")",
        "description": "Block malicious query strings"
      },
      {
        "action": "managed_challenge",
        "expression": "(http.request.uri.path contains \"/wp-login.php\" and http.request.method eq \"POST\") and not ip.src in $allowed_admin_ips",
        "description": "Challenge login POST (allowlist bypass)"
      }
    ]
  }'
```

---

## Scheduling

To run the auto-updater daily at 8 AM:

```powershell
# Run as Administrator
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument "-ExecutionPolicy Bypass -File `"C:\Scripts\CF-AutoIP-Manager.ps1`" -Silent"
$trigger = New-ScheduledTaskTrigger -Daily -At "8:00AM"
Register-ScheduledTask -Action $action -Trigger $trigger `
  -TaskName "Cloudflare IP Updater" `
  -Description "Auto-update Cloudflare allowlist with current IP"
```

To remove the scheduled task:
```powershell
Unregister-ScheduledTask -TaskName "Cloudflare IP Updater" -Confirm:$false
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Execution policy" error | Run: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser` |
| Can't access admin panel | Your IP changed. Run the menu script and add your new IP. |
| Auto-detect shows wrong IP | VPN/proxy active. Use the menu script to add the correct IP manually. |
| "Invalid access token" error | Check `CF_EMAIL` and `CF_API_KEY` are correct. Global API Key, not API Token. |
| Locked out, can't run script | Login to Cloudflare dashboard > Account > Configurations > Lists > add your IP manually. |
| A plugin/feature stopped working | The server IP may need to be in the allowlist. Add it as a protected entry (no `seen:` tag). |

---

## Disclaimer
**CF-AllowList-Manager** is intended for educational and authorized use only. Ensure you have the necessary permissions to access and manage the Cloudflare account and resources. The authors are not responsible for any misuse of these scripts.

---

## Contact
For any questions or feedback, feel free to open an [issue](https://github.com/0xDTC/0xCloudFlare/issues) or contact the repository owner.

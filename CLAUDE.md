# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Collection of scripts automating Cloudflare API interactions: zone data extraction (Bash) and IP allowlist management (PowerShell). All scripts target the Cloudflare API v4 (`https://api.cloudflare.com/client/v4/`).

## Architecture

Two independent modules with different languages and auth methods:

**CF-Zone-Tools/** - Bash scripts for read-only zone data extraction
- Auth: Bearer token via `API_KEY` variable
- Dependencies: `curl`, `jq`
- Output: Markdown files (`Global_ZoneLockDown_Records.md`, `Global_DNS_records.md`)
- Pagination: loops through zones using `per_page` / page count math
- Temp file: writes zone IDs to `SuckZoneID.txt` during execution

**CF-AllowList-Manager/** - PowerShell scripts for managing Cloudflare IP lists used by WAF custom rules
- Auth: email + Global API Key via `X-Auth-Email` / `X-Auth-Key` headers
- Dependencies: PowerShell 5.1+ (built-in `Invoke-RestMethod`)
- Two scripts:
  - `Manage-CloudflareAllowlist.ps1` - interactive menu (view/add/remove IPs)
  - `CF-AutoIP-Manager.ps1` - automated IP sync with stale cleanup (params: `-StaleDays`, `-DryRun`, `-Silent`)

## Key Design Decisions

- **Stale IP tracking**: CF-AutoIP-Manager embeds `seen:YYYY-MM-DD` in Cloudflare list item comments. IPs with this tag are auto-removable; IPs without it (manually added) are "protected" and never auto-removed.
- **IP update strategy**: To "update" an existing IP's seen date, the script removes then re-adds the entry (Cloudflare list items are immutable; no PATCH for comments).
- **IPv4 priority**: Auto-detection tries 5 IPv4 sources first; only falls back to IPv6 if all IPv4 sources fail.
- **Credentials are placeholder constants** at the top of each script (not env vars in the PowerShell scripts, unlike the Bash scripts which reference hardcoded vars too). Never commit real credentials.

## Running Scripts

```bash
# Zone Tools (Linux/macOS)
cd CF-Zone-Tools
chmod +x *.sh
# Edit API_KEY and ACCOUNT_ID at the top of the script, then:
./Download_DNS_Entries_Of_All_Assets.sh

# AllowList Manager (Windows PowerShell)
cd CF-AllowList-Manager
# Edit $CF_EMAIL, $CF_API_KEY, $ACCOUNT_ID, $LIST_ID at the top, then:
.\Manage-CloudflareAllowlist.ps1           # Interactive
.\CF-AutoIP-Manager.ps1                    # Auto mode
.\CF-AutoIP-Manager.ps1 -DryRun            # Preview only
.\CF-AutoIP-Manager.ps1 -StaleDays 7       # Custom threshold
.\CF-AutoIP-Manager.ps1 -Silent            # Logs to cf-autoip.log
```

## Note

`Download_Rule_set_of_OWASP.sh` is marked "Under Construction" and uses a different auth method (email + API key) than the other Bash scripts (Bearer token).

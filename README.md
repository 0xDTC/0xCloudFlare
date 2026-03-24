[![Buy Me a Knowledge](https://img.shields.io/badge/Buy_Me_a_Knowledge-📖-FF5F5F?style=for-the-badge&logo=buy-me-a-coffee&logoColor=white)](https://www.buymeacoffee.com/0xDTC)

# 0xCloudFlare
A collection of scripts to automate Cloudflare API interactions — zone management, DNS auditing, WAF configuration, and IP allowlist management.

---

## Directory Structure

```
0xCloudFlare/
├── README.md
├── CF-Zone-Tools/              Bash scripts for zone data extraction
│   ├── README.md
│   ├── Download_All_The_Zone_Lockdown_IPs.sh
│   ├── Download_DNS_Entries_Of_All_Assets.sh
│   └── Download_Rule_set_of_OWASP.sh
└── CF-AllowList-Manager/       PowerShell scripts for IP allowlist management
    ├── README.md
    ├── Manage-CloudflareAllowlist.ps1
    └── CF-AutoIP-Manager.ps1
```

---

## Modules

### [CF-Zone-Tools](./CF-Zone-Tools/)
Bash scripts for extracting zone lockdown IPs, DNS entries, and OWASP rule sets from the Cloudflare API.

**Platform:** Linux / macOS
**Dependencies:** `curl`, `jq`

### [CF-AllowList-Manager](./CF-AllowList-Manager/)
PowerShell scripts for managing Cloudflare IP allowlists used by WAF custom rules. Includes an interactive menu for manual management and an auto-detect script that syncs your current IP and cleans stale entries.

**Platform:** Windows (PowerShell 5.1+)
**Dependencies:** None (uses built-in `Invoke-RestMethod`)

---

## Quick Start

**Zone Tools (Bash):**
```bash
cd CF-Zone-Tools
export CLOUDFLARE_API_TOKEN=your_token
export CLOUDFLARE_ACCOUNT_ID=your_account_id
./Download_DNS_Entries_Of_All_Assets.sh
```

**AllowList Manager (PowerShell):**
```powershell
cd CF-AllowList-Manager
# Edit credentials in the script first
.\Manage-CloudflareAllowlist.ps1          # Interactive menu
.\CF-AutoIP-Manager.ps1                   # Auto-detect + stale cleanup
.\CF-AutoIP-Manager.ps1 -DryRun           # Preview without changes
```

See each module's README for detailed documentation.

---

## Disclaimer
**0xCloudFlare** is intended for educational and authorized use only. Ensure you have the necessary permissions to access and manage the Cloudflare account and resources. The authors are not responsible for any misuse of these scripts.

---

## Contact
For any questions or feedback, feel free to open an [issue](https://github.com/0xDTC/0xCloudFlare/issues) or contact the repository owner.

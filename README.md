<a href="https://www.buymeacoffee.com/0xDTC"><img src="https://img.buymeacoffee.com/button-api/?text=Buy me a knowledge&emoji=📖&slug=0xDTC&button_colour=FF5F5F&font_colour=ffffff&font_family=Comic&outline_colour=000000&coffee_colour=FFDD00" /></a>

# 0xCloudFlare
**0xCloudFlare** is a collection of shell scripts designed to automate interactions with Cloudflare's API, facilitating tasks such as downloading zone lockdown IPs, retrieving DNS entries, and obtaining OWASP rule sets.
---

## Table of Contents
- [Features](#features)
- [Scripts Overview](#scripts-overview)
- [Installation](#installation)
- [Usage](#usage)
  - [Download All Zone Lockdown IPs](#download-all-zone-lockdown-ips)
  - [Download DNS Entries of All Assets](#download-dns-entries-of-all-assets)
  - [Download OWASP Rule Set](#download-owasp-rule-set)
- [Environment Variables](#environment-variables)
- [Contributing](#contributing)

---

## Features

- Retrieve all IP addresses associated with zone lockdowns.
- Fetch DNS entries for all assets within a Cloudflare account.
- Download the OWASP rule set for web application firewall configurations.

---

## Scripts Overview

### 1. `Download_All_The_Zone_Lockdown_IPs.sh`
- **Purpose**: Retrieves all IP addresses associated with zone lockdowns in your Cloudflare account.
- **Usage**: Helps in auditing and managing IP restrictions applied to your zones.

### 2. `Download_DNS_Entries_Of_All_Assets.sh`
- **Purpose**: Fetches DNS entries for all assets (domains) managed under your Cloudflare account.
- **Usage**: Useful for inventory management and DNS record auditing.

### 3. `Download_Rule_set_of_OWASP.sh`
- **Purpose**: Downloads the OWASP rule set configured in your Cloudflare account.
- **Usage**: Assists in reviewing and managing web application firewall (WAF) rules based on OWASP standards.

---

## Installation

1. **Clone the repository**:
   ```bash
   git clone https://github.com/0xDTC/0xCloudFlare.git
   cd 0xCloudFlare
   ```

2. **Ensure the scripts have execute permissions**:
   ```bash
   chmod +x Download_All_The_Zone_Lockdown_IPs.sh
   chmod +x Download_DNS_Entries_Of_All_Assets.sh
   chmod +x Download_Rule_set_of_OWASP.sh
   ```

3. **Install dependencies**:
   Ensure you have `curl` and `jq` installed:
   - **For Debian/Ubuntu**:
     ```bash
     sudo apt-get install curl jq
     ```
   - **For CentOS/RHEL**:
     ```bash
     sudo yum install curl jq
     ```
   - **For macOS**:
     ```bash
     brew install curl jq
     ```
---

## Usage

### Environment Variables

Before using the scripts, export the necessary environment variables for Cloudflare API access:

```bash
export CLOUDFLARE_API_TOKEN=your_api_token
export CLOUDFLARE_ACCOUNT_ID=your_account_id
```

### Download All Zone Lockdown IPs

Use `Download_All_The_Zone_Lockdown_IPs.sh` to retrieve all IP addresses associated with zone lockdowns.

```bash
./Download_All_The_Zone_Lockdown_IPs.sh
```

**Output**: A list of IP addresses in JSON format associated with your zone lockdowns.

### Download DNS Entries of All Assets

Use `Download_DNS_Entries_Of_All_Assets.sh` to fetch DNS entries for all assets.

```bash
./Download_DNS_Entries_Of_All_Assets.sh
```

**Output**: A JSON-formatted list of DNS entries for all your domains.

### Download OWASP Rule Set

Use `Download_Rule_set_of_OWASP.sh` to download the OWASP rule set.

```bash
./Download_Rule_set_of_OWASP.sh
```

**Output**: The OWASP rule set in JSON format as configured in your Cloudflare account.

---

## Contributing

Contributions are welcome! Follow these steps to contribute:
1. **Fork the repository.**
2. **Create a feature branch**:
   ```bash
   git checkout -b feature/your-feature
   ```
3. **Commit your changes**:
   ```bash
   git commit -m "Add your feature"
   ```
4. **Push to your branch**:
   ```bash
   git push origin feature/your-feature
   ```
5. **Create a pull request.**
---
## Disclaimer
**0xCloudFlare** is intended for educational and authorized use only. Ensure you have the necessary permissions to access and manage the Cloudflare account and resources. The authors are not responsible for any misuse of these scripts.

---

## Contact
For any questions or feedback, feel free to open an [issue](https://github.com/0xDTC/0xCloudFlare/issues) or contact the repository owner.

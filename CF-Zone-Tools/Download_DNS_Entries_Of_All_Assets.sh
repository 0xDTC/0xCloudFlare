#!/bin/bash

# Set your Cloudflare API key
API_KEY="<add your api key>"

# Set other parameters as needed (e.g., account.id, order, etc.)
ACCOUNT_ID="<add your account id>"
ORDER="124"
PER_PAGE=124

# Get the total number of zones
TOTAL_ZONES=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/count" -H "Authorization: Bearer $API_KEY" | jq -r '.result')

# Calculate the number of pages
PAGES=$((TOTAL_ZONES / PER_PAGE + 1))

# Create a Markdown file to store DNS records
echo -e "Type|Name|Content|Proxied Status\n---|---|---|---" > Global_DNS_records.md

# Loop through each page
for ((PAGE=1; PAGE<=$PAGES; PAGE++)); do
  echo "Fetching zones - Page $PAGE"
  # Make the request for the current page and retrieve zone IDs
  curl -s -X GET "https://api.cloudflare.com/client/v4/zones?page=$PAGE&per_page=$PER_PAGE&order=$ORDER" -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json" -d "{\"account.id\":\"$ACCOUNT_ID\"}" | jq -r '.result[].id' > SuckZoneID.txt

  # Loop through each zone ID and fetch DNS records
  while IFS= read -r ZONE_ID; do
    echo "Fetching DNS records for zone $ZONE_ID"
    curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?page=1&per_page=600" -H "Authorization: Bearer $API_KEY" | jq -r --argjson page "$PAGE" '.result[] | "\(.type)|\(.name)|\(.content)|\(.proxied)"' >> Global_DNS_records.md
  done < SuckZoneID.txt
done
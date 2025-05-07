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

# Create a Markdown file to store Zone Lockdown records
echo -e "|Created On|Description|ID|Modified On|Paused|Targets|Values|URLs|\n---|---|---|---|---|---|---|---" > Global_ZoneLockDown_Records.md

# Loop through each page
for ((PAGE=1; PAGE<=$PAGES; PAGE++)); do
  echo "Fetching zones - Page $PAGE"
  # Make the request for the current page and retrieve zone IDs
  curl -s -X GET "https://api.cloudflare.com/client/v4/zones?page=$PAGE&per_page=$PER_PAGE&order=$ORDER" -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json" -d "{\"account.id\":\"$ACCOUNT_ID\"}" | jq -r '.result[].id' > SuckZoneID.txt

  # Loop through each zone ID and fetch Zone Lockdown records
  while IFS= read -r ZONE_ID; do
    echo "Fetching Zone records $ZONE_ID"
    # Fetch Zone Lockdown records for the current zone ID
    ZONE_LOCKDOWNS=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/firewall/lockdowns?page=1&per_page=100" -H "Authorization: Bearer $API_KEY")
    
    # Check if there are Zone Lockdown records
    if [ "$(echo "$ZONE_LOCKDOWNS" | jq -r '.result')" != "null" ]; then
      # Iterate over Zone Lockdown records and append to the markdown file
      echo "$ZONE_LOCKDOWNS" | jq -r '.result[] | "| \(.created_on) | \(.description) | \(.id) | \(.modified_on) | \(.paused) | \(.configurations | map("\(.target): \(.value)") | join(", ")) | \(.urls | join(", ")) |"' >> Global_ZoneLockDown_Records.md
    fi
  done < SuckZoneID.txt
done
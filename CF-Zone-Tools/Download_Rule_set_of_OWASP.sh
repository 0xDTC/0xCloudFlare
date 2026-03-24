#!/bin/bash

# Cloudflare API credentials
api_key='YOUR_API_KEY'
api_email='YOUR_API_EMAIL'
zone_id='YOUR_ZONE_ID'

# Cloudflare API endpoint for managed rules
endpoint="https://api.cloudflare.com/client/v4/zones/${zone_id}/firewall/rules"
  
# Request headers  
headers=("X-Auth-Email: ${api_email}" "X-Auth-Key: ${api_key}" "Content-Type: application/json")
  
# Request parameters
params=("page=1" # You may need to paginate through the results if you have many rules    "per_page=50"  # Adjust the number of rules per page as needed)
  
# Make the request to Cloudflare API
response=$(curl -s -H "${headers[@]}" "${endpoint}?$(IFS=\&; echo "${params[*]}")")
  
# Check if the request was successful (HTTP status code 200)
if [["$(jq -r '.success' <<< "$response")" == "true" ]]; then
# Extract and print the OWASP managed rules
    jq -c '.result.rules[] | select(.description | contains("OWASP")) | {id, description}' <<< "$response"
else
# Print an error message if the request was not successful
    echo "Error: $(jq -r '.errors[0].code' <<< "$response"), $(jq -r '.errors[0].message' <<< "$response")"
fi

>Under Construction<
#!/bin/bash
# Akash Network Provider Auditor Signature Status
#
# This script retrieves provider information from the Akash Network and the Akash Console API,
# and displays the auditor signature status, uptime, available resources, and total summary.
#
# Usage: ./akash_provider_audit_status.sh
#
# Requirements:
# - Akash CLI installed and configured with the appropriate network (mainnet or testnet)
# - curl command-line tool
# - jq command-line JSON processor
# - bc basic calculator

# Define the list of providers with their wallet addresses and names
providers=(
  "akash1kkjkd0pv0c7r53luacjj6aeaaalerjjnh7z9kv,bigtractorcompute.com"
)

# Define the auditor address
auditor="akash1365yvmc4s7awdyj3n2sav7xfx76adc6dnmlx63"

# Function to format memory and storage values
format_value() {
  local value=$1
  local unit="GB"

  if (( $(echo "$value >= 1000" | bc -l) )); then
    value=$(echo "scale=2; $value / 1024" | bc)
    unit="TB"
  else
    value=$(printf "%.0f" $value)
  fi

  echo "${value}${unit}"
}

# Print the header
echo "Akash Network Provider Auditor Signature Status"
echo "-----------------------------------------------"
printf "%-20s %-45s %-10s %-20s %-10s %-15s %-15s %-10s\n" "Provider" "Wallet Address" "Status" "Uptime" "CPU" "Memory" "Storage" "GPU"
printf "%-20s %-45s %-10s %-20s %-10s %-15s %-15s %-10s\n" "--------" "--------------" "------" "------" "---" "------" "-------" "---"

# Initialize total variables
total_signed=0
total_uptime=0
total_cpu=0
total_memory=0
total_storage=0
total_gpus=0

# Loop through each provider
for provider in "${providers[@]}"
do
  # Extract the wallet address and provider name
  wallet_address=$(echo "$provider" | cut -d',' -f1)
  provider_name=$(echo "$provider" | cut -d',' -f2)

  # Get the auditor signature status
  attributes=$(akash query audit get "$wallet_address" "$auditor" --node=https://akash-rpc.publicnode.com:443 2>/dev/null)
  status=$([ -n "$attributes" ] && echo "Signed" || echo "Not Signed")

  # Get the provider information from the CloudMOS API
  provider_info=$(curl -s "https://console-api.akash.network/v1/providers/$wallet_address")
  
  if [ -z "$provider_info" ]; then
    echo "Debug: Failed to fetch provider information for $wallet_address"
    uptime="-"
    cpu="-"
    memory="-"
    storage="-"
    gpus="-"
  else
    uptime=$(echo "$provider_info" | jq -r '.uptime30d')
    cpu=$(echo "$provider_info" | jq -r '.availableStats.cpu / 1000')
    memory=$(echo "$provider_info" | jq -r '.availableStats.memory | tonumber | . / (1024 * 1024 * 1024)')
    storage=$(echo "$provider_info" | jq -r '.availableStats.storage | tonumber | . / (1024 * 1024 * 1024)')
    gpus=$(echo "$provider_info" | jq -r '.availableStats.gpu')
    
    memory_formatted=$(format_value $memory)
    storage_formatted=$(format_value $storage)
    
    # Update total variables
    if [ "$status" = "Signed" ]; then
      ((total_signed++))
    fi
    
    total_uptime=$(echo "$total_uptime + $uptime" | bc)
    total_cpu=$(echo "$total_cpu + $cpu" | bc)
    total_memory=$(echo "$total_memory + $memory" | bc)
    total_storage=$(echo "$total_storage + $storage" | bc)
    total_gpus=$(echo "$total_gpus + $gpus" | bc)
  fi

  # Print the provider information
  printf "%-20s %-45s %-10s %-20s %-10s %-15s %-15s %-10s\n" "$provider_name" "$wallet_address" "$status" "$uptime" "$cpu" "$memory_formatted" "$storage_formatted" "$gpus"
done

# Calculate total and average values
total_providers=${#providers[@]}
avg_uptime=$(echo "scale=2; $total_uptime / $total_providers" | bc)
total_memory_formatted=$(format_value $total_memory)
total_storage_formatted=$(format_value $total_storage)

# Print the total summary
printf "%-20s %-45s %-10s %-20s %-10s %-15s %-15s %-10s\n" "--------" "--------------" "------" "------" "-----------" "------" "-------" "----"
printf "%-20s %-45s %-10s %-20.2f %-10.2f %-15s %-15s %-10s\n" "Total" "$total_providers Providers" "$total_signed/$total_providers Signed" "$avg_uptime" "$total_cpu" "$total_memory_formatted" "$total_storage_formatted" "$total_gpus"

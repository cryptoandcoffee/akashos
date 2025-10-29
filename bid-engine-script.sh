#!/bin/bash

# Fetch AKT to USD rate
usd_per_akt=$(curl -s "https://akashedge.com/price" | jq -r '.price')
if [ -z "$usd_per_akt" ] || [ "$usd_per_akt" == "0" ]; then
    exit 1
fi


# Function to calculate total resource costs in USD
calculate_total_cost_usd() {
    local data=$1

    # Extract resource quantities
    local cpu=$(jq -r '(map(.cpu * .count) | add) / 1000' <<<"$data")
    local memory=$(jq -r '(map(.memory * .count) | add) / pow(1024; 3)' <<<"$data")
    local ephemeral_storage=$(jq -r '[.[] | (.storage[] | select(.class == "ephemeral").size // 0) * .count] | add / pow(1024; 3)' <<<"$data")
    local hdd_storage=$(jq -r '[.[] | (.storage[] | select(.class == "beta1").size // 0) * .count] | add / pow(1024; 3)' <<<"$data")
    local ssd_storage=$(jq -r '[.[] | (.storage[] | select(.class == "beta2").size // 0) * .count] | add / pow(1024; 3)' <<<"$data")
    local nvme_storage=$(jq -r '[.[] | (.storage[] | select(.class == "beta3").size // 0) * .count] | add / pow(1024; 3)' <<<"$data")
    local endpoints=$(jq -r '(map(.endpoint_quantity // 0 * .count) | add)' <<<"$data")
    local ips=$(jq -r '(map(.ip_lease_quantity // 0 * .count) | add)' <<<"$data")
    local gpu_units=$(jq -r '[.[] | (.gpu.units // 0) * .count] | add' <<<"$data")
    local gpu_model=$(jq -r '.[0].gpu.attributes.vendor.nvidia.model' <<<"$data")

    # Define target prices for different resources
    TARGET_CPU="5.00"
    TARGET_MEMORY="0.75"
    TARGET_EPHEMERAL_STORAGE="0.25"
    TARGET_HDD_STORAGE="0.1667"
    TARGET_SSD_STORAGE="0.3333"
    TARGET_NVME_STORAGE="0.50"
    TARGET_ENDPOINT="0.01"
    TARGET_IP="2.00"
    TARGET_GPU_UNIT="0"

    # Total cost in USD
    total_cost_usd_target=$(bc -l <<<"($cpu * $TARGET_CPU) + ($memory * $TARGET_MEMORY) + ($ephemeral_storage * $TARGET_EPHEMERAL_STORAGE) + ($hdd_storage * $TARGET_HDD_STORAGE) + ($ssd_storage * $TARGET_SSD_STORAGE) + ($nvme_storage * $TARGET_NVME_STORAGE) + ($endpoints * $TARGET_ENDPOINT) + ($ips * $TARGET_IP) + ($gpu_units * $TARGET_GPU_UNIT)")
}

# Fetch AKT to USD rate
fetch_akt_to_usd

# Read JSON input
data_in=$(jq .)

# Calculate total cost in USD
calculate_total_cost_usd "$(jq -r '.resources' <<<"$data_in")"

TARGET_MIN_USD=$(awk "BEGIN {print (($TARGET_MEMORY + $TARGET_EPHEMERAL_STORAGE + $TARGET_CPU))}")       #Dynamically calculate - removed /1.25
TARGET_MIN_UAKT=$(awk "BEGIN {print (($TARGET_MIN_USD * 1000000) / ($usd_per_akt * 425940.524781341))}") #Converts the MIN_USD to uakt

total_cost_akt_target=$(awk "BEGIN {print ($total_cost_usd_target/$usd_per_akt)}")
total_cost_uakt_target=$(awk "BEGIN {print ($total_cost_akt_target*1000000)}")
cost_per_block=$(awk "BEGIN {print ($total_cost_uakt_target/425940.524781341)}")

if (($(echo "$cost_per_block < $TARGET_MIN_UAKT" | bc -l))); then
    cost_per_block=$TARGET_MIN_UAKT
fi

printf "%.4f\n" "$cost_per_block"

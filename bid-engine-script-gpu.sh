#!/bin/bash

# Function to fetch the AKT to USD exchange rate
fetch_akt_to_usd() {
usd_per_akt=$(curl -s "https://akashedge.com/price" | jq -r '.price')
if [ -z "$usd_per_akt" ] || [ "$usd_per_akt" == "0" ]; then
    exit 1
fi
}

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

    # Define an associative array for GPU TFLOPS
    declare -A GPU_TFLOPS

    GPU_TFLOPS=(
        ["750Ti"]="1.3"
        ["950"]="1.6"
        ["1050"]="1.8"
        ["1050Ti"]="2.1"
        ["960"]="2.3"
        ["970"]="3.9"
        ["980"]="5.6"
        ["980Ti"]="6.1"
        ["1060"]="4"
        ["1070"]="6.5"
        ["1070Ti"]="8"
        ["1080"]="9"
        ["1080Ti"]="11.3"
        ["1650"]="2.9"
        ["1650Ti"]="3"
        ["1660"]="5"
        ["1660Ti"]="5.5"
        ["1660S"]="5.7"
        ["2060"]="6.5"
        ["2060S"]="7.2"
        ["2070"]="7.9"
        ["2070S"]="9.1"
        ["2080"]="10"
        ["2080S"]="11.1"
        ["2080Ti"]="13.4"
        ["3060"]="13"
        ["3060Ti"]="16.2"
        ["3070"]="20"
        ["3070Ti"]="22"
        ["3080"]="30"
        ["3080Ti"]="34"
        ["3090"]="36"
        ["4060"]="15.11"
        ["4060Ti"]="22.06"
        ["4070"]="29.15"
        ["4070Ti"]="40.09"
        ["4080"]="48.75"
        ["4080Ti"]="67.58"
        ["4090"]="82.58"
        ["K20"]="3.52"
        ["K40"]="4.29"
        ["K80"]="8.74"
        ["M4"]="2.2"
        ["M40"]="6.8"
        ["M60"]="10"
        ["M2090"]="1.33"
        ["P4"]="5.5"
        ["P40"]="12"
        ["P100"]="9.3"
        ["T4"]="8.1"
        ["V100"]="14"
        ["V100S"]="16.4"
        ["A100"]="19.5"
        ["A10"]="31.4"
        ["A30"]="28.8"
        ["A40"]="37.4"
    )

    # Base price $USD and TFLOPS for the reference model (1080Ti in this example)
    BASE_PRICE="50"
    BASE_TFLOPS=${GPU_TFLOPS["1080Ti"]}

    # Case-insensitive lookup in associative array
    TFLOPS=""
    for key in "${!GPU_TFLOPS[@]}"; do
        normalized_key=$(echo "$key" | tr -d '[:space:]')
        if [[ ${normalized_key,,} == "${gpu_model,,}" ]]; then
            TFLOPS=${GPU_TFLOPS[$key]}
            break
        fi
    done

    # If no match, use the most expensive card as default
    if [ -z "$TFLOPS" ]; then
        TFLOPS=${GPU_TFLOPS["4090"]}
    fi

    TARGET_GPU_UNIT=$(echo "$BASE_PRICE * ($TFLOPS / $BASE_TFLOPS)" | bc)

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

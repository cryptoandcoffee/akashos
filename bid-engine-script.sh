#!/bin/bash
data_in=$(jq .)
cpu_total=$(echo "$data_in" | jq 'map(.cpu * .count) | add')
memory_gb=$(echo "$data_in" | jq -r '(map(.memory * .count) | add) / pow(1024; 3)')
hd_gb=$(echo "$data_in" | jq -r '([.[].storage[] | select(.class == "ephemeral").size // 0] | add) / pow(1024; 3)')
cpu_total_threads=$(echo $cpu_total | awk '{print $1/1000}')
usd_per_akt=$(curl -s -X GET "https://api.coingecko.com/api/v3/coins/akash-network/tickers" -H  "accept: application/json" | jq '.tickers[] | select(.market.name == "Osmosis").converted_last.usd' | head -n1)

#Price in USD per month
CPU_PRICE=1.00
MEMORY_PRICE=0.75
DISK_PRICE=0.25

#Normal Deployment
total_cost_usd_target=$(bc -l <<<"(($cpu_total_threads * $CPU_PRICE) + ($memory_gb * $MEMORY_PRICE) + ($hd_gb * $DISK_PRICE))")

total_cost_akt_target=$(bc -l <<<"(${total_cost_usd_target}/$usd_per_akt)")
total_cost_uakt_target=$(bc -l <<<"(${total_cost_akt_target}*1000000)")
cost_per_block=$(bc -l <<<"(${total_cost_uakt_target}/425940.524781341)")
total_cost_uakt=$(echo "$cost_per_block" | jq 'def ceil: if . | floor == . then . else . + 1.0 | floor end; .|ceil')

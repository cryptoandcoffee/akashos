#!/bin/bash
. /home/akash/variables

# Define an associative array mapping hostnames to IP addresses
declare -A hosts=(
    ["akash-node1"]="$LOCAL_IP"
    # Add more hosts here
)

# Loop over each host
for host in "${!hosts[@]}"; do
    ip=${hosts[$host]}

    echo "Processing $host with IP $ip"

    # SSH into the machine and save GPU names into a variable
    ssh akash@$ip "sudo bash -c ' \
        GPU_IDS=\$(nvidia-smi --query-gpu=index --format=csv,noheader,nounits | awk '\''{ print \$1 }'\'' ); \
        for GPU_ID in \$GPU_IDS; do \
            nvidia-smi -i \$GPU_ID --query-gpu=name --format=csv,noheader,nounits; \
        done \
    '" > "${host}_GPUs"

function apt(){
    ssh akash@$ip "sudo bash -c ' \
        apt-get update ; apt-get dist-upgrade -yqq
    '"
}
apt

function gpu-power(){
    # SSH into the machine, download the scripts and enable the service
    ssh akash@$ip "sudo bash -c ' \
        curl -sSL https://raw.githubusercontent.com/88plug/akash-provider-tools/main/gpu-power.sh -o /home/akash/gpu-power.sh && \
        chmod +x /home/akash/gpu-power.sh && \
        curl -sSL https://raw.githubusercontent.com/88plug/akash-provider-tools/main/gpu-power.service -o /etc/systemd/system/gpu-power.service && \
        systemctl daemon-reload && \
        systemctl enable gpu-power.service && \
        systemctl start gpu-power.service \
    '"
}
gpu-power

done

echo "-----------------"

total_gpus=0

# Print GPU names for each host
for host in $(printf "%s\n" "${!hosts[@]}" | sort -V); do
    echo -n "$host : "
    gpus=$(paste -s -d ',' "${host}_GPUs")
    # Corrected line: remove the extra space between "NVIDIA" and "GeForce"
    #gpus="${gpus// NVIDIA,/NVIDIA}"
    echo "$gpus"
    # Count the GPUs for this host by counting the number of comma-separated items
    gpu_count=$(echo "$gpus" | tr -cd ',' | wc -c)

    # Increment the total count
    total_gpus=$((total_gpus + gpu_count + 1))
done

echo "Total GPUs: $total_gpus"

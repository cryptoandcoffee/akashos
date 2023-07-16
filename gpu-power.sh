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

    ssh akash@$ip "sudo bash -c ' \
        apt-get update ; apt-get dist-upgrade -yqq
    '"

    # SSH into the machine, download the scripts and enable the service
    ssh akash@$ip "sudo bash -c ' \
        curl -sSL https://raw.githubusercontent.com/88plug/akash-provider-tools/main/gpu-power.sh -o /home/akash/gpu-power.sh && \
        chmod +x /home/akash/gpu-power.sh && \
        curl -sSL https://raw.githubusercontent.com/88plug/akash-provider-tools/main/gpu-power.service -o /etc/systemd/system/gpu-power.service && \
        systemctl daemon-reload && \
        systemctl enable gpu-power.service && \
        systemctl start gpu-power.service \
    '"
done

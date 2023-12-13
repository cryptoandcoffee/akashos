#!/bin/bash

#Control plane
AKASH_NODE1_IP=192.168.1.134

# Node definitions
declare -A nodes
nodes=(
  ["bdl-computer-rs4"]="192.168.1.207"
  ["bdl-computer-rs3"]="192.168.1.162"
)


# Password
password="akash"

# Your public key file
public_key_file="$HOME/.ssh/id_rsa.pub"
public_key=$(cat "$public_key_file")

# SSH Options
ssh_options="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Copy SSH keys and display hostname
for hostname in "${!nodes[@]}"; do
  ip=${nodes[$hostname]}
  echo "Processing $hostname ($ip)..."

  # Check if the key already exists
  exists=$(sshpass -p "$password" ssh $ssh_options "akash@$ip" "grep -F '$public_key' ~/.ssh/authorized_keys" 2>/dev/null)

  # If the key does not exist, copy it
  if [ -z "$exists" ]; then
    echo "Adding new key to $hostname ($ip)..."
    sshpass -p "$password" ssh-copy-id $ssh_options "akash@$ip" 2>/dev/null
  else
    echo "Key already exists on $hostname ($ip). Skipping..."
  fi

  function join-agent(){
    k3sup join --user akash --ip $ip --server-ip $AKASH_NODE1_IP --server-user akash
  }
  join-agent

done

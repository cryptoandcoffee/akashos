#!/bin/bash
#To be run on a single k3s node - to get the base Akash provider software installed.
mkdir -p  /home/akash/logs/installer
echo "Install logs are available in /home/akash/logs/installer if anything breaks"

# Utility function to read user input with a default value
function read_input() {
    local prompt="$1"
    local default="$2"
    local input

    read -p "$prompt" input
    echo "${input:-$default}"
}

# Utility function to confirm user input
function confirm_input() {
    local prompt="$1"
    local input

    while true; do
        read -p "$prompt (y/n): " input
        case "$input" in
            y|Y) return 0 ;;
            n|N) return 1 ;;
            *) echo "Invalid entry. Please enter 'y' or 'n'." ;;
        esac
    done
}

# Utility function to set a variable based on user input and confirmation
function set_variable() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"

    while true; do
        local value=$(read_input "$prompt" "$default")
        if confirm_input "Are you sure the value is correct? ($value)"; then
            eval "$var_name='$value'"
            break
        fi
    done
}

function gpu_check() {
    if lspci | grep -q NVIDIA; then
        if confirm_input "NVIDIA GPU Detected: Would you like to enable it on this host? (default: y)"; then
            GPU_=true
        else
            GPU_=false
        fi
    fi
}

function node_selection() {
    if confirm_input "Is this setup for the first node/machine in the cluster? (default: y)"; then
        CLIENT_NODE_=false
        echo "Initial setup for akash-node1 selected."
    else
        CLIENT_NODE_=true
        echo "Client node setup selected."
    fi
}

function client_node_questions() {
    if [[ $CLIENT_NODE_ == true ]]; then
        # Set hostname
        set_variable "Enter the hostname to use for this additional node" "akash-node2" "CLIENT_HOSTNAME_"
        #joining_server_node
    fi
}

function joining_server_node() {
    if confirm_input "Do you want to attempt to automatically join the client node to the server node?"; then
        # Set IP address of akash-node1
        set_variable "What is the IP address of akash-node1?" "" "AKASH_NODE_1_IP"
        
        # Set node type (control plane or agent)
        while true; do
            local node_type=$(read_input "Should this node be a control plane or an agent? (c/a)" "")
            if confirm_input "Are you sure? ($node_type)"; then
                case "$node_type" in
                    c|C) NODE_TYPE="control_plane"; break ;;
                    a|A) NODE_TYPE="agent"; break ;;
                    *) echo "Invalid entry. Please enter 'c' for control plane or 'a' for agent." ;;
                esac
            fi
        done
    else
        echo "Continuing without automatically joining the client node to the server node."
    fi
}

function first_node_questions() {
    if [[ $CLIENT_NODE_ == false ]]; then
        # Akash wallet
        if confirm_input "Do you have an Akash wallet with at least 50 AKT and the mnemonic phrase available? (default: n)"; then
            NEW_WALLET_=false
        else
            NEW_WALLET_=true
            echo "New wallet required during setup."
        fi

        # Import key if the user has one
        if [[ $NEW_WALLET_ == false ]]; then
            set_variable "Enter the mnemonic phrase to import your provider wallet (e.g., KING SKI GOAT...)" "" "mnemonic_"
        fi

        # Set domain name
        set_variable "Enter the domain name to use for your provider" "example.com" "DOMAIN_"

        # Verified provider
        if confirm_input "Do you want to become a verified provider and share this information publicly?"; then
            set_variable "Enter your email address (this will be public)" "" "PROVIDER_EMAIL_"
            set_variable "Enter your website URL (this will be public)" "" "PROVIDER_WEBSITE_"

            echo "Please confirm the following details will be shared publicly:"
            echo "Email: $PROVIDER_EMAIL_"
            echo "Website: $PROVIDER_WEBSITE_"
            if confirm_input "Are you sure you want to proceed?"; then
                VERIFIED_PROVIDER_=true
            else
                VERIFIED_PROVIDER_=false
            fi
        else
            VERIFIED_PROVIDER_=false
        fi
    fi
}

function user_input() {
    # Toggle the following functions as needed by commenting/uncommenting them
    node_selection
    gpu_check
    client_node_questions
    first_node_questions
}

echo "Just a few questions..."
user_input



clear
echo ""
echo "Sit back and relax - this could take a few minutes or up to an hour depending on your hardware, connection, and choices." 
echo ""

#Store securely for user
KEY_SECRET_=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32};echo;)



function depends(){
export DEBIAN_FRONTEND=noninteractive
apt-get -o Acquire::ForceIPv4=true update
DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -yqq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
snap install kubectl --classic ; snap install helm --classic
#Disable sleep
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
#Disable IPv6
sed -i -e 's/GRUB_CMDLINE_LINUX_DEFAULT="maybe-ubiquity"/GRUB_CMDLINE_LINUX_DEFAULT="ipv6.disable=1 maybe-ubiquity"/' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
#Fast reboots
sed -i -e 's/#DefaultTimeoutStopSec=90s/DefaultTimeoutStopSec=5s/' /etc/systemd/system.conf
systemctl daemon-reload
}
echo "☸️ Updating Ubuntu"
depends &>> /home/akash/logs/installer/depends.log

function gpu(){
if lspci | grep -q NVIDIA; then
echo "Install NVIDIA"
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get -o Acquire::ForceIPv4=true update
/bin/bash -c "$(curl -sL https://git.io/vokNn)"
apt-fast install -y nvidia-driver-550 nvidia-utils-550 nvidia-cuda-toolkit nvidia-container-toolkit nvidia-container-runtime
fi
}

if [[ $GPU_ == "true" ]]; then
echo "☸️ Installing GPU : Patience is a virtue."
gpu &>> /home/akash/logs/installer/gpu.log
else
echo "☸️ Skipping GPU"
fi

if [[ $CLIENT_NODE_ == "false" ]]; then

function k3sup_install(){
curl -LS https://get.k3sup.dev | sh
#OLD WAY
#LOCAL_IP=$(ip -4 addr show | grep enp* | grep -oP 'inet \K[\d.]+')
#New way compatible with VPS
LOCAL_IP=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1)
echo 'akash ALL=(ALL) NOPASSWD:ALL' | tee -a /etc/sudoers
apt-get install -y sshpass
sudo -u akash sshpass -p 'akash' ssh-copy-id -i /home/akash/.ssh/id_rsa.pub -o StrictHostKeyChecking=no akash@$LOCAL_IP
sudo -u akash sshpass -p 'akash' ssh-copy-id -i /home/akash/.ssh/id_rsa.pub -o StrictHostKeyChecking=no akash@127.0.0.1
sudo -u akash k3sup install --cluster --user akash --ip $LOCAL_IP --k3s-extra-args "--disable servicelb --disable traefik --disable metrics-server --disable-network-policy --flannel-backend=none"
##Add additional server nodes with:
#k3sup join --server --server-ip 192.168.1.199 --server-user akash --user akash --ip 192.168.1.132 --k3s-extra-args "--disable servicelb --disable traefik --disable metrics-server --disable-network-policy --flannel-backend=none"

chmod 600 /etc/rancher/k3s/k3s.yaml
mkdir -p /home/akash/.kube
# Not all apps use the new default of "config"
cp /etc/rancher/k3s/k3s.yaml /home/akash/.kube/config
cp /etc/rancher/k3s/k3s.yaml /home/akash/.kube/kubeconfig
chown akash:akash /etc/rancher/k3s/k3s.yaml
echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> /home/akash/.bashrc
echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> /etc/profile
source /home/akash/.bashrc
# Breaking if we do not wait!
echo "Waiting 15 seconds for k3s to settle..."
grep nvidia /var/lib/rancher/k3s/agent/etc/containerd/config.toml
sleep 15
} 
echo "☸️ Installing k3sup"
k3sup_install &>> /home/akash/logs/installer/k3sup.log

function k3s_install(){
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--flannel-backend=none --disable=traefik --disable servicelb --disable metrics-server --disable-network-policy" sh -s -
chmod 600 /etc/rancher/k3s/k3s.yaml
mkdir -p /home/akash/.kube
# Not all apps use the new default of "config"
cp /etc/rancher/k3s/k3s.yaml /home/akash/.kube/config
cp /etc/rancher/k3s/k3s.yaml /home/akash/.kube/kubeconfig
chown akash:akash /etc/rancher/k3s/k3s.yaml
echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> /home/akash/.bashrc
echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> /etc/profile
source /home/akash/.bashrc
# Breaking if we do not wait!
echo "Waiting 15 seconds for k3s to settle..."
grep nvidia /var/lib/rancher/k3s/agent/etc/containerd/config.toml
sleep 15
} 
# echo "☸️ Installing k3s"
# k3s_install &>> /home/akash/logs/installer/k3s.log

chown -R akash:akash /home/akash/.kube/

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

function chisel_install(){
curl https://i.jpillora.com/chisel! | bash
wget https://raw.githubusercontent.com/cryptoandcoffee/akashos/main/chisel.py
chown akash:akash chisel.py
}
echo "Installing Chisel"
chisel_install &>> /home/akash/logs/installer/chisel.log


function cilium_install(){

#Get Cilium CLI
wget https://github.com/cilium/cilium-cli/releases/latest/download/cilium-linux-amd64.tar.gz
chmod +x cilium-linux-amd64.tar.gz
tar xzvf cilium-linux-amd64.tar.gz 
chmod +x cilium
chown akash:akash cilium
mv cilium /usr/local/bin/
rm -f cilium-linux-amd64.tar.gz
#Cilium Helm Charts
helm repo add cilium https://helm.cilium.io/
helm repo update
helm install cilium cilium/cilium --wait \
   --namespace kube-system \
   --set global.bandwidthManager=true \
   --set kubeProxyReplacement=true \
   --set operator.replicas=1
}
echo "🕸️ Installing cilium"
cilium_install &>> /home/akash/logs/installer/cilium.log

#echo "Sleep 90 seconds for Cilium then checking Cilium and Cluster are up..."
#sleep 90

#cilium status

# Check the exit status of the 'cilium status' command
#if [ $? -ne 0 ]; then
#    echo "Error: Cilium status check failed"
#    exit 1
#fi

kubectl get pods -A -o wide

# Check the exit status of the 'kubectl get pods -A -o wide' command
if [ $? -ne 0 ]; then
    echo "Error: kubectl get pods command failed"
    exit 1
fi

function install_akash(){
#Install Akash and setup wallet
curl -sSfL https://raw.githubusercontent.com/akash-network/node/master/install.sh | sh
cp bin/akash /usr/local/bin
rm -rf bin/
curl -sfL https://raw.githubusercontent.com/akash-network/provider/main/install.sh | bash
cp bin/provider-services /usr/local/bin
rm -rf bin/
echo "Akash Node     : $(akash version)"
echo "Akash Provider : $(provider-services version)"
}
echo "🚀 Installing Akash"
install_akash &>> /home/akash/logs/installer/akash.log


function setup_wallet(){
if [[ $NEW_WALLET_ == "true" ]]; then
printf "$KEY_SECRET_\n$KEY_SECRET_\n" | akash keys add default
printf "$KEY_SECRET_\n$KEY_SECRET_\n" | akash keys export default > key.pem
qrencode -t ASCIIi $(echo $KEY_SECRET_ | akash keys list | grep address | cut -d ':' -f2 | cut -c 2-) > wallet_qr_code.txt
clear
cat wallet_qr_code.txt
ACCOUNT_ADDRESS_=$(echo $KEY_SECRET_ | akash keys list | grep address | cut -d ':' -f2 | cut -c 2-)
echo "Your new wallet has been created succesfully!"
echo "The QR code will be available in : /home/akash/wallet_qr_code.txt.  You can use it to send AKT directly to this wallet."
echo "Your wallet address is : $ACCOUNT_ADDRESS_"
echo "Find all your configuration details in /home/akash/variables file."
else
echo -e "$mnemonic_\n$KEY_SECRET_\n$KEY_SECRET_" | akash keys add default --recover
echo -e "$KEY_SECRET_\n$KEY_SECRET_" | akash keys export default > key.pem
ACCOUNT_ADDRESS_=$(echo $KEY_SECRET_ | akash keys list | grep address | cut -d ':' -f2 | cut -c 2-)
qrencode -t ASCIIi $(echo $KEY_SECRET_ | akash keys list | grep address | cut -d ':' -f2 | cut -c 2-) > wallet_qr_code.txt
fi
}
echo "💰 Creating wallet"
setup_wallet &>> /home/akash/logs/installer/wallet.log

if [[ $NEW_WALLET_ == "true" ]]; then
MNEMONIC=$(awk '/forget your password./{getline; getline; print}' /home/akash/logs/installer/wallet.log)
else
MNEMONIC=$mnemonic_
unset mnemonic_
fi

function check_wallet(){
ACCOUNT_ADDRESS_=$(echo $KEY_SECRET_ | akash keys list | grep address | cut -d ':' -f2 | cut -c 2-)
BALANCE=$(akash query bank balances --node https://akash-rpc.global.ssl.fastly.net:443 $ACCOUNT_ADDRESS_)
MIN_BALANCE=50

if (( $(echo "$BALANCE < 50" | bc -l) )); then
  echo "Balance is less than 50 AKT - you should send more coin to continue."
  echo "Found a balance of $BALANCE on the wallet $ACCOUNT_ADDRESS_"
else
  echo "Found a balance of $BALANCE on the wallet $ACCOUNT_ADDRESS_"
fi
sleep 5
}
#check_wallet 

echo "DOMAIN=$DOMAIN_" > variables
echo "ACCOUNT_ADDRESS=$ACCOUNT_ADDRESS_" >> variables
echo "KEY_SECRET=$KEY_SECRET_" >> variables
echo "CHAIN_ID=akashnet-2" >> variables
echo "HOST=akash" >> variables
echo "REGION=$REGION_" >> variables
echo "CPU=$CPU_" >> variables
echo "UPLOAD=$UPLOAD_" >> variables
echo "DOWNLOAD=$DOWNLOAD_" >> variables
echo "PROVIDER_EMAIL=$PROVIDER_EMAIL_" >> variables
echo "PROVIDER_WEBSITE=$PROVIDER_WEBSITE_" >> variables
echo "VERIFIED_PROVIDER=$VERIFIED_PROVIDER_" >> variables
echo "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> variables
echo "CPU_PRICE=" >> variables
echo "MEMORY_PRICE=" >> variables
echo "DISK_PRICE=" >> variables
echo "MNEMONIC=\"$MNEMONIC\"" >> variables
echo 'NODE="http://akash-node-1:26657"' >> variables
 

function provider_install(){
echo "Installing Akash provider and bid-engine"

if [[ $GPU_ == "true" ]]; then
echo "Found GPU, using testnet config!"
wget -q https://raw.githubusercontent.com/cryptoandcoffee/akashos/main/run-helm-k3s-gpu.sh
wget -q https://raw.githubusercontent.com/cryptoandcoffee/akashos/main/bid-engine-script-gpu.sh
chmod +x run-helm-k3s-gpu.sh ; chmod +x bid-engine-script-gpu.sh
mv run-helm-k3s-gpu.sh run-helm-k3s.sh
mv bid-engine-script-gpu.sh bid-engine-script.sh
chown akash:akash *.sh
echo "Running Helm Provider install after first reboot to get nvidia-smi"
else
wget -q https://raw.githubusercontent.com/cryptoandcoffee/akashos/main/run-helm-k3s.sh
wget -q https://raw.githubusercontent.com/cryptoandcoffee/akashos/main/bid-engine-script.sh
chmod +x run-helm-k3s.sh ; chmod +x bid-engine-script.sh
chown akash:akash *.sh
sudo -u akash ./run-helm-k3s.sh 
fi
}

echo "🌐 Installing Akash Provider and Node"
provider_install &>> /home/akash/logs/installer/provider.log

echo "🛡️ Creating firewall rules"
cat <<EOF > ./firewall-ports.txt
8443/tcp - for manifest uploads
80/tcp - for web app deployments
443/tcp - for web app deployments
30000-32767/tcp - for Kubernetes node port range for deployments
30000-32767/udp - for Kubernetes node port range for deployments
EOF

chown akash:akash *.sh
chown akash:akash *.txt
chown akash:akash variables


# End node client mode skip
fi

if [[ $CLIENT_NODE_ == true ]]; then
echo "CLIENT_NODE=true" >> variables
echo "CLIENT_HOSTNAME=$CLIENT_HOSTNAME_" >> variables
echo "AKASH_NODE_1_IP=$AKASH_NODE_1_IP_" >> variables
# Setup hostname for client node
hostnamectl set-hostname $CLIENT_HOSTNAME_
echo $CLIENT_HOSTNAME_ | tee /etc/hostname
sed -i "s/127.0.1.1 akash-node1/127.0.1.1 $CLIENT_HOSTNAME_/g" /etc/hosts
else
echo "CLIENT_NODE=false" >> variables
echo "CLIENT_HOSTNAME=akash-node1" >> variables
fi

echo "SETUP_COMPLETE=true" >> variables

echo "Setup Complete"
echo "Rebooting ..."
reboot now --force

#Add/scale the cluster with 'microk8s add-node' and use the token on additional nodes.
#Use 'microk8s enable dns:1.1.1.1' after you add more than 1 node.

#Todos:
# Add checkup after install/first start ( 
# Add watchdog to check for updates
# Rename "start-akash" for easy user access
# Convert to simple menu / GUI for easy of use
# Support additional methods, k3s/kubespray

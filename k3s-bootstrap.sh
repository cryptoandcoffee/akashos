#!/bin/bash
#To be run on a single k3s node - to get the base Akash provider software installed.
mkdir -p  /home/akash/logs/installer
echo "Install logs are available in /home/akash/logs/installer if anything breaks"

function user_input(){

while true; do
    clear
    read -p "Is this setup for the first node/machine in the cluster? (y/n, default: y): " choice

    case "$choice" in
        n|N ) 
            CLIENT_NODE_=true
            echo "Client node setup selected."
            sleep 2
            break
            ;;
        y|Y ) 
            CLIENT_NODE_=false
            echo "Initial setup for akash-node1 selected."
            sleep 2
            break
            ;;
        * )
            echo "Invalid entry. Please enter 'y' for client node or 'n' for initial setup."
            sleep 2
            ;;
    esac
done

if [[ $CLIENT_NODE_ == true ]]; then
    while true; do
        clear
        read -p "Enter the hostname to use for this additional node (default: akash-node2): " CLIENT_HOSTNAME_
        
        if [[ -z $CLIENT_HOSTNAME_ ]]; then
            CLIENT_HOSTNAME_="akash-node2"
        fi
        
        read -p "Are you sure the hostname is correct? ($CLIENT_HOSTNAME_) (y/n): " choice
        
        case "$choice" in
            y|Y ) 
                break
                ;;
            n|N ) 
                echo "Please try again."
                sleep 2
                ;;
            * ) 
                echo "Invalid entry. Please enter 'y' for yes or 'n' for no."
                sleep 2
                ;;
        esac
    done
fi

if [[ $CLIENT_NODE_ == true ]]; then
    read -p "Do you want to attempt to automatically join the client node to the server node? (y/n): " choice
    if [[ "$choice" =~ ^[yY]$ ]]; then
        while true; do
            read -p "What is the IP address of akash-node1? : " AKASH_NODE_1_IP
            
            read -p "Are you sure the IP address of akash-node1 is correct? (Current: $AKASH_NODE_1_IP) (y/n): " confirm
            case "$confirm" in
                [yY] )
                    while true; do
                        read -p "Should this node be a control plane or an agent? (c/a): " node_type
                        case "$node_type" in
                            [cC] )
                                NODE_TYPE="control_plane"
                                break
                                ;;
                            [aA] )
                                NODE_TYPE="agent"
                                break
                                ;;
                            * )
                                echo "Invalid entry. Please enter 'c' for control plane or 'a' for agent."
                                sleep 2
                                ;;
                        esac
                    done
                    break
                    ;;
                [nN] )
                    echo "Please try again."
                    sleep 2
                    ;;
                * )
                    echo "Invalid entry. Please enter 'y' for yes or 'n' for no."
                    sleep 2
                    ;;
            esac
        done
    else
        echo "Continuing without automatically joining the client node to the server node."
    fi
fi

if [[ $CLIENT_NODE_ == "false" ]]; then
  # Check if the user has an Akash wallet
  while true; do
    clear
    read -p "Do you have an Akash wallet with at least 50 AKT and the mnemonic phrase available? (y/n, default: n): " choice

    case "$choice" in
        y|Y ) 
            NEW_WALLET_=false
            break
            ;;
        n|N ) 
            echo "New wallet required during setup."
            NEW_WALLET_=true
            sleep 2
            break
            ;;
        * )
            echo "Invalid entry. Please enter 'y' for yes or 'n' for no."
            sleep 2
            ;;
    esac
  done

  # Import key if the user knows it
  if [[ $NEW_WALLET_ == "false" ]]; then
    while true; do
      clear
      read -p "Enter the mnemonic phrase to import your provider wallet (e.g., KING SKI GOAT...): " mnemonic_

      read -p "Are you sure the wallet mnemonic is correct? ($mnemonic_) (y/n): " choice
        
      case "$choice" in
          y|Y ) 
              break
              ;;
          n|N ) 
              echo "Please try again."
              sleep 2
              ;;
          * ) 
              echo "Invalid entry. Please enter 'y' for yes or 'n' for no."
              sleep 2
              ;;
      esac
    done
  fi

  # End of client node check
fi

# GPU Support
if lspci | grep -q NVIDIA; then
  while true; do
    clear
    read -p "NVIDIA GPU Detected: Would you like to enable it on this host? (y/n, default: y): " GPU_
    
    read -p "Are you sure you want to enable GPU support? ($GPU_) (y/n): " choice
    
    case "$choice" in
        y|Y ) 
            GPU_=true
            break
            ;;
        n|N ) 
            echo "Skipping GPU support."
            GPU_=false
            sleep 3
            break
            ;;
        * )
            echo "Invalid entry. Please enter 'y' for yes or 'n' for no."
            sleep 3
            ;;
    esac
  done
fi

if [[ $CLIENT_NODE_ == "false" ]]; then
  # Domain is required
  while true; do
    clear
    read -p "Enter the domain name to use for your provider (example.com): " DOMAIN_
    
    read -p "Are you sure the provider domain is correct? ($DOMAIN_) (y/n): " choice
    
    case "$choice" in
        y|Y ) 
            break
            ;;
        n|N ) 
            echo "Please try again."
            sleep 2
            ;;
        * )
            echo "Invalid entry. Please enter 'y' for yes or 'n' for no."
            sleep 2
            ;;
    esac
  done

  # Dynamic or Static Public IP?
  while true; do
    clear
    read -p "Do you have a dynamic DNS address or a static IP address? ($ip_) (dynamic/static): " choice
    
    case "$choice" in
        dynamic|DYNAMIC ) 
            ip_=dynamic
            echo "You chose dynamic IP."
            break
            ;;
        static|STATIC ) 
            ip_=static
            echo "You chose static IP."
            break
            ;;
        * )
            echo "Invalid entry. Please enter 'dynamic' or 'static'."
            sleep 2
            ;;
    esac
  done 

  # End of client_node mode check
fi



if [[ $ip_ == "dynamic" ]]; then
echo "Dynamic IP Detected"
  echo "You must use a Dynamic DNS / No-IP service."
    while true
    do
    clear
    read -p "Enter your dynamic DNS url (akash.no-ip.com) : " DYNAMICIP_
    read -p "Are you sure the dynamic DNS url is correct? : $DYNAMICIP_ (y/n)? " choice
    case "$choice" in
      y|Y ) break;;
      n|N ) echo "Try again" ; sleep 3;;
      * ) echo "Invalid entry, please try again with Y or N" ; sleep 3;;
    esac
    done
clear
echo "📝 Creating DNS Records"
cat <<EOF > ./dns-records.txt
*.ingress 300 IN CNAME nodes.$DOMAIN_.
nodes 300 IN CNAME $DYNAMICIP_.
provider 300 IN CNAME nodes.$DOMAIN_.
rpc 300 IN CNAME nodes.$DOMAIN_.
EOF
else
clear
echo "📝 Creating DNS Records"
cat <<EOF > ./dns-records.txt
*.ingress 300 IN CNAME nodes.$DOMAIN_.
nodes 300 IN A X.X.X.X. #IP of this machine and any additional nodes
nodes 300 IN A X.X.X.X. #IP of any additional nodes
nodes 300 IN A X.X.X.X. #IP of any additional nodes
provider 300 IN CNAME nodes.$DOMAIN_.
rpc 300 IN CNAME nodes.$DOMAIN_.
EOF

fi
}
echo "Just a few questions..."
# Never log
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
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get -o Acquire::ForceIPv4=true update
apt-get install nvidia-cuda-550
#ubuntu-drivers autoinstall
apt-get install -y nvidia-cuda-toolkit nvidia-container-toolkit nvidia-container-runtime 
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

function cilium_install(){

#Get Cilium CLI
wget https://github.com/cilium/cilium-cli/releases/latest/download/cilium-linux-amd64.tar.gz
chmod +x cilium-linux-amd64.tar.gz
tar xzvf cilium-linux-amd64.tar.gz 
chmod +x cilium
chown akash:akash cilium
mv cilium /usr/local/bin/
rm -f cilium-linux-amd64.tar.gz

#cilium install --set kubeProxyReplacement=strict --set bandwidthManager.enabled=true


helm repo add cilium https://helm.cilium.io/
helm repo update
helm install cilium cilium/cilium --wait \
    --set operator.replicas=1 \
    --set global.containerRuntime.integration="containerd" \
    --set global.containerRuntime.socketPath="/var/run/k3s/containerd/containerd.sock" \
    --set kubeProxyReplacement=strict \
    --set global.bandwidthManager=true \
    --namespace kube-system


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

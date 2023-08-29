#!/bin/bash
#To be run on a single microk8s node - to get the base Akash provider software installed.

#Check what user has
while true
do
clear
#read -p "Do you have an Akash wallet with at least 50 AKT and the mnemonic phrase available? (y/n) : " NEW_WALLET_
read -p "Do you have an Akash wallet with at least 50 AKT and the mnemonic phrase available? (y/n) " choice
case "$choice" in
  y|Y ) NEW_WALLET_=false; break;;
  n|N ) echo "New wallet required during setup" ; NEW_WALLET_=true; sleep 5 ; break;;
  * ) echo "Invalid entry, please try again with Y or N" ; sleep 3;;
esac
done

#Import key if the user knows it
if [[ $NEW_WALLET_ == "false" ]]; then
while true
do
clear
read -p "Enter mnemonic phrase to import your provider wallet (KING SKI GOAT...) : " mnemonic_
read -p "Are you sure the wallet mnemonic is correct? : $mnemonic_ (y/n)? " choice
case "$choice" in
  y|Y ) break;;
  n|N ) echo "Try again" ; sleep 3;;
  * ) echo "Invalid entry, please try again with Y or N" ; sleep 3;;
esac
done
fi

#Domain is required
while true
do
clear
read -p "Enter provider domain name to use for your provider (example.com) : " DOMAIN_
read -p "Are you sure the provider domain is correct? : $DOMAIN_ (y/n)? " choice
case "$choice" in
  y|Y ) break;;
  n|N ) echo "Try again" ; sleep 3;;
  * ) echo "Invalid entry, please try again with Y or N" ; sleep 3;;
esac
done




#read -p "Enter domain name to use for your provider (example.com) : " DOMAIN_
#read -p "Enter mnemonic phrase to import your provider wallet (KING SKI GOAT...): " mnemonic_
#read -p "Enter the region for this cluster (us-west/eu-east) : " REGION_
#read -p "Enter the cpu type for this server (amd/intel) : " CPU_
#read -p "Enter the download speed of the connection in Mbps (1000) : " DOWNLOAD_
#read -p "Enter the upload speed of the connection in Mbps (250) : " UPLOAD_
#read -p "Enter the new keyring password to protect the wallet with (NewWalletPassword): " KEY_SECRET_

#Store securely for user
KEY_SECRET_=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32};echo;)

#Depends / Microk8s / Kubectl / Helm
function depends(){
#Secure DNS with DOT
cat <<EOF > /etc/systemd/resolved.conf
[Resolve]
DNS=1.1.1.1 1.0.0.1
FallbackDNS=8.8.8.10 8.8.8.8
#Domains=
#LLMNR=no
#MulticastDNS=no
DNSSEC=yes
DNSOverTLS=yes
#Cache=yes
DNSStubListener=yes
#ReadEtcHosts=yes
EOF
systemctl restart systemd-resolved.service
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get dist-upgrade -yqq
snap install microk8s --classic ; snap install kubectl --classic ; snap install helm --classic

#Disable sleep
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
#Disable any messages after login
touch /home/akash/.hushlogin
#Disable IPv6
sed -i -e 's/GRUB_CMDLINE_LINUX_DEFAULT="maybe-ubiquity"/GRUB_CMDLINE_LINUX_DEFAULT="ipv6.disable=1 maybe-ubiquity"/' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
#Fast reboots
sed -i -e 's/#DefaultTimeoutStopSec=90s/DefaultTimeoutStopSec=5s/' /etc/systemd/system.conf
systemctl daemon-reload


#mkdir -p ~/.kube ; microk8s config > ~/.kube/kubeconfig ; chmod 600 ~/.kube/kubeconfig ; export KUBECONFIG=~/.kube/kubeconfig
#mkdir -p /home/akash/.kube ; microk8s config > /home/akash/.kube/kubeconfig
#chmod 600 /home/akash/.kube/kubeconfig
#chown akash:akash /home/akash/.kube/kubeconfig
#export KUBECONFIG=/home/akash/.kube/kubeconfig
#chmod 600 /var/snap/microk8s/current/credentials/client.config
echo "export KUBECONFIG=/var/snap/microk8s/current/credentials/client.config" >> /etc/profile
usermod -aG microk8s akash
#newgrp microk8s
}
depends


microk8s enable dns:1.1.1.1
microk8s kubectl get pods -A

function install_akash(){
#Install Akash and setup wallet
curl -sSfL https://raw.githubusercontent.com/akash-network/node/master/install.sh | sh
cp bin/akash /usr/local/bin
rm -rf bin/
akash version
}
install_akash

function install_akash_provider(){
curl -sfL https://raw.githubusercontent.com/akash-network/provider/main/install.sh | bash
cp bin/provider-services /usr/local/bin
rm -rf bin/
akash version
}
install_akash_provider



function setup_wallet(){
if [[ $NEW_WALLET_ == "true" ]]; then
apt-get install -y qrencode
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
sleep 30
else
echo "$mnemonic_" | akash keys add default --recover
unset mnemonic_
echo "$KEY_SECRET_ $KEY_SECRET_" | akash keys export default > key.pem
fi
}
setup_wallet

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
check_wallet

echo "DOMAIN=$DOMAIN_" > variables
echo "ACCOUNT_ADDRESS=$ACCOUNT_ADDRESS_" >> variables
echo "KEY_SECRET=$KEY_SECRET_" >> variables
echo "REGION=$REGION_" >> variables
echo "CPU=$CPU_" >> variables
echo "UPLOAD=$UPLOAD_" >> variables
echo "DOWNLOAD=$DOWNLOAD_" >> variables
echo "KUBECONFIG=/var/snap/microk8s/current/credentials/client.config" >> variables
echo "CPU_PRICE=" >> variables
echo "MEMORY_PRICE=" >> variables
echo "DISK_PRICE=" >> variables

echo "Get latest config from github"
wget -q https://raw.githubusercontent.com/cryptoandcoffee/akashos/main/run-helm-microk8s.sh
wget -q https://raw.githubusercontent.com/cryptoandcoffee/akashos/main/bid-engine-script.sh
chmod +x run-helm-microk8s.sh ; chmod +x bid-engine-script.sh
chown akash:akash *.sh

./run-helm-microk8s.sh
 
while true
do
clear
read -p "Do you have a dynamic or static IP address? : $ip_ (dynamic/static)? " choice
case "$choice" in
  dynamic|DYNAMIC ) echo "You chose dynamic IP" ; ip_=dynamic ; break;;
  static|STATIC ) echo "You chose static" ;  ip_=static ; break;;
  * ) echo "Invalid entry, please try again with dynamic or static";;
esac
done 

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
  echo "You must configure your DNS records to match this format and open the following ports"
cat <<EOF > ./dns-records.txt
*.ingress 300 IN CNAME nodes.$DOMAIN_.
nodes 300 IN CNAME $DYNAMICIP_.
provider 300 IN CNAME nodes.$DOMAIN_.
rpc 300 IN CNAME nodes.$DOMAIN_.
EOF
  cat ./dns-records.txt
else
  echo "You must configure your DNS records to match this format and open the following ports"
cat <<EOF > ./dns-records.txt
*.ingress 300 IN CNAME nodes.$DOMAIN_.
nodes 300 IN A X.X.X.X. #IP of this machine and any additional nodes
nodes 300 IN A X.X.X.X. #IP of any additional nodes
nodes 300 IN A X.X.X.X. #IP of any additional nodes
provider 300 IN CNAME nodes.$DOMAIN_.
rpc 300 IN CNAME nodes.$DOMAIN_.
EOF
  cat ./dns-records.txt
fi

echo "Firewall Setup Required" 
echo "Please forward these ports to the IP of this machine"

cat <<EOF > ./firewall-ports.txt
8443/tcp - for manifest uploads
80/tcp - for web app deployments
443/tcp - for web app deployments
30000-32767/tcp - for Kubernetes node port range for deployments
30000-32767/udp - for Kubernetes node port range for deployments
EOF

cat ./firewall-ports.txt
rm -f microk8s-bootstrap.sh
chown akash:akash *.sh
chown akash:akash *.txt
chown akash:akash variables

#echo "WALLET_FUNDED=0" >> variables
echo "SETUP_COMPLETE=true" >> variables

echo "Setup Complete"
echo "Rebooting in 10 seconds..."
sleep 10
reboot now

#Add/scale the cluster with 'microk8s add-node' and use the token on additional nodes.
#Use 'microk8s enable dns:1.1.1.1' after you add more than 1 node.

#Todos:
# Add checkup after install/first start ( 
# Add watchdog to check for updates
# Rename "start-akash" for easy user access
# Convert to simple menu / GUI for easy of use
# Support additional methods, k3s/kubespray

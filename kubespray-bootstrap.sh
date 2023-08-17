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


#How many nodes will be in this cluster
while true
do
clear
read -p "How many nodes will be in this cluster? (1) : " NODES_REQUIRED_
read -p "Are you sure the cluster size is correct? : $NODES_REQUIRED_ (y/n)? " choice
case "$choice" in
  y|Y ) break;;
  n|N ) echo "Try again" ; sleep 3;;
  * ) echo "Invalid entry, please try again with at least 1 or less than 9" ; sleep 3;;
esac
done

LOCAL_IP=$(ip -4 addr show ens18 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

if [[ $NODES_REQUIRED_ > 1 ]]; then

for i in $(seq $NODES_REQUIRED_); do

while true
do
clear
count=$i
if [[ $i == 1 ]]; then
count=2
i=2
echo "NODE1="$LOCAL_IP"@akash" >> variables
fi
read -p "What is the IP of the $i node? (x.x.x.x) : " NODE_$i
read -p "Are you sure the IP address of the $i node is correct? : $NODE_$1 (y/n)? " choice
case "$choice" in
  y|Y ) echo "NODE$count=NODE$i" >> variables ; break;;
  n|N ) echo "Try again" ; sleep 3;;
  * ) echo "Invalid entry, please try again with at least 1 or less than 9" ; sleep 3;;
esac
done
done
else
echo "NODE1="$LOCAL_IP"@akash" >> variables
fi


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

apt-get update && apt-get dist-upgrade -yqq ; apt-get install -y unzip cloud-utils open-vm-tools qemu-guest-agent python3-pip git sshpass software-properties-common rsync snapd
add-apt-repository --yes --update ppa:ansible/ansible
sudo apt-get install -y ansible
git clone https://github.com/kubernetes-sigs/kubespray.git ; cd kubespray
pip3 install -r requirements.txt
snap install kubectl --classic ; snap install helm --classic
}
depends

#Install Akash and setup wallet
curl -sSfL https://raw.githubusercontent.com/ovrclk/akash/master/godownloader.sh | sh
cp bin/akash /usr/local/bin
rm -rf bin/
akash version

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

ACCOUNT_ADDRESS_=$(echo $KEY_SECRET_ | akash keys list | grep address | cut -d ':' -f2 | cut -c 2-)
BALANCE=$(akash query bank balances --node http://rpc.bigtractorplotting.com:26657 $ACCOUNT_ADDRESS_)
MIN_BALANCE=50

if (( $(echo "$BALANCE < 50" | bc -l) )); then
  echo "Balance is less than 50 AKT - you should send more coin to continue."
  echo "Found a balance of $BALANCE on the wallet $ACCOUNT_ADDRESS_"
else
  echo "Found a balance of $BALANCE on the wallet $ACCOUNT_ADDRESS_"
fi
sleep 5

echo "NODES_REQUIRED_=$NODES_REQUIRED_" >> variables
echo "DOMAIN=$DOMAIN_" >> variables
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
. variables

#echo "Now ready for kubespraying"
#Building array from nodes defined
declare -a IPS
readarray -t IPS <<< $(
  env | \
    grep '^NODE[[:digit:]]\+=' | sort | cut -d= -f2
)

echo "using pools ${IPS[*]}"

for HOST in "${IPS[@]}"
do
COUNTER=$(( COUNTER + 1 ))
#echo "Split"
IP=$(echo $HOST | cut -d'@' -f1)
PASS=$(echo $HOST | cut -d'@' -f2)

if ping -c 1 $IP &> /dev/null
then
echo "Found ping to $IP"
else
echo "All hosts not ready"
echo "You must fix this host before the kubespray install can continue."
echo "Please check the host"
fi

export SSHPASS=$PASS
echo $IP >> nodes.log
function multiple(){
if ssh -o BatchMode=yes -o ConnectTimeout=2 root@$IP exit
then
echo "Found good connection with correct SSH to $IP"
else
exit
ssh-keygen -f "/home/andrew/.ssh/known_hosts" -R "$IP"
ssh-keyscan $IP >> ~/.ssh/known_hosts
sshpass -e ssh-copy-id -i ~/.ssh/id_rsa.pub $USER@$IP
ssh -n $USER@$IP hostnamectl set-hostname node${COUNTER} ; hostname -f
ssh -n $USER@$IP "echo 127.0.1.1     node${COUNTER} > /etc/hosts ; cat /etc/hosts"
ssh -n $USER@$IP "sed -i '/ swap / s/^/#/' /etc/fstab"
#ssh -n $USER@$IP 'echo "br_netfilter" >> /etc/modules'
ssh -n $USER@$IP reboot
fi
}

function ansible(){
#Setup ansible
cp -rfp inventory/sample inventory/akash
#Create config.yaml
cat nodes.log
cat nodes.log | sed -e :a -e '$!N; s/\n/ /; ta'
CONFIG_FILE=inventory/akash/hosts.yaml python3 contrib/inventory_builder/inventory.py $(cat nodes.log | sed -e :a -e '$!N; s/\n/ /; ta')
cat inventory/akash/hosts.yaml
#Enable gvisor for security
ex inventory/akash/hosts.yaml <<eof
2 insert
  vars:
    cluster_id: "1.0.0.1"
    ansible_user: root
    gvisor_enabled: true
.
xit
eof
echo "File Modified"
cat inventory/akash/hosts.yaml
}
ansible

function start_cluster(){
#Run
ansible-playbook -i inventory/akash/hosts.yaml -b -v --private-key=~/.ssh/id_rsa cluster.yml
#Get the kubeconfig from master node
###########rsync -av root@$(cat nodes.log | head -n1):/root/.kube/config kubeconfig
#Use the new kubeconfig file for kubectl
export KUBECONFIG=./kubeconfig
#Get snap path right
export PATH=$PATH:/snap/bin
#Install kubectl and helm using snap
#snap install kubectl --classic
#snap install helm --classic
#Change the name of the server address in kubeconfig to master
sed -i "s/127.0.0.1/$(cat nodes.log | head -n1)/g" kubeconfig
cp kubeconfig ../kubeconfig
}
start_cluster

export KUBECONFIG=./kubeconfig
kubectl get nodes -o wide


echo "Get latest config from github"
wget -q https://raw.githubusercontent.com/88plug/akash-provider-tools/main/run-helm-microk8s.sh
wget -q https://raw.githubusercontent.com/88plug/akash-provider-tools/main/bid-engine-script.sh
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

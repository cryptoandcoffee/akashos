#!/bin/bash
export KUBECONFIG=/home/akash/.kube/kubeconfig
. /home/akash/variables
#####################################################
DOMAIN="$DOMAIN"
ACCOUNT_ADDRESS="$ACCOUNT_ADDRESS"
KEY_SECRET="$KEY_SECRET"
CHAIN_ID=akashnet-2
REGION="$REGION"
CHIA_PLOTTING=false
CPU="$CPU"
HOST="akash"
TIER="community"
NODE="http://akash-node-1:26657"
#####################################################

# Akash Helm Charts
helm repo add akash https://akash-network.github.io/helm-charts
helm repo update

# Required for cluster creation, do not edit.
kubectl create ns akash-services
kubectl label ns akash-services akash.network/name=akash-services akash.network=true
kubectl create ns lease
kubectl label ns lease akash.network=true

kubectl apply -f https://raw.githubusercontent.com/akash-network/provider/v0.4.6/pkg/apis/akash.network/crd.yaml

# Ingress Operator
ingress_charts(){
cat > ingress-nginx-custom.yaml << EOF
controller:
  service:
    type: ClusterIP
  ingressClassResource:
    name: "akash-ingress-class"
  kind: DaemonSet
  hostPort:
    enabled: true
  admissionWebhooks:
    port: 7443
  config:
    allow-snippet-annotations: false
    compute-full-forwarded-for: true
    proxy-buffer-size: "16k"
  metrics:
    enabled: true
  extraArgs:
    enable-ssl-passthrough: true
tcp:
  "1317": "akash-services/akash-node-1:1317"
  "8443": "akash-services/akash-provider:8443"
  "9090":  "akash-services/akash-node-1:9090"
  "26656": "akash-services/akash-node-1:26656"
  "26657": "akash-services/akash-node-1:26657"
EOF

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --wait --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  -f ingress-nginx-custom.yaml
 
kubectl label ns ingress-nginx app.kubernetes.io/name=ingress-nginx app.kubernetes.io/instance=ingress-nginx
kubectl label ingressclass akash-ingress-class akash.network=true

}
ingress_charts

# Node
helm upgrade --install akash-node akash/akash-node -n akash-services \
  --set akash_node.api_enable=true \
  --set akash_node.minimum_gas_prices=0uakt \
  --set state_sync.enabled=false \
  --set akash_node.snapshot_provider=polkachu \
  --set resources.limits.cpu="2" \
  --set resources.limits.memory="8Gi" \
  --set resources.requests.cpu="0.5" \
  --set resources.requests.memory="4Gi"

kubectl set env statefulset/akash-node-1 AKASH_PRUNING=custom AKASH_PRUNING_INTERVAL=100 AKASH_PRUNING_KEEP_RECENT=100 AKASH_PRUNING_KEEP_EVERY=100 -n akash-services

# Run nvidia-smi command to get GPU information
gpu_info="$(nvidia-smi --query-gpu=gpu_name --format=csv,noheader)"
gpu_models=$(echo "$gpu_info" | awk 'BEGIN {FS = ", "} ; {print $1}' | awk '{print $6 substr($4, 1) tolower(substr($5, 1))}')
# Label nodes with specific GPU models using kubectl
node_name=$(hostname)
label_prefix="akash.network/capabilities.gpu.vendor.nvidia.model."

for model in $gpu_models; do
        label_command="kubectl label node $node_name $label_prefix$model=true"
        $label_command
done

# Split the original command into two parts: before and after where the new "--set" statements should be inserted
cmd1="helm upgrade --install akash-provider akash/provider -n akash-services \
        --set attributes[0].key=region --set attributes[0].value=$REGION \
        --set attributes[1].key=chia-plotting --set attributes[1].value=$CHIA_PLOTTING \
        --set attributes[2].key=host --set attributes[2].value=$HOST \
        --set attributes[3].key=cpu --set attributes[3].value=$CPU \
        --set attributes[4].key=tier --set attributes[4].value=$TIER \
        --set attributes[5].key=organization --set attributes[5].value=$ORG \
        --set attributes[6].key=network_download --set attributes[6].value=$DOWNLOAD \
        --set attributes[7].key=network_upload --set attributes[7].value=$UPLOAD \
        --set attributes[8].key=status --set attributes[8].value=https://status.$DOMAIN \
        --set attributes[9].key=capabilities/storage/1/class --set attributes[9].value=beta1 \
        --set attributes[10].key=capabilities/storage/1/persistent --set attributes[10].value=true \
        --set attributes[11].key=capabilities/storage/2/class --set attributes[11].value=beta2 \
        --set attributes[12].key=capabilities/storage/2/persistent --set attributes[12].value=true \
        --set attributes[13].key=capabilities/storage/3/class --set attributes[13].value=beta3 \
        --set attributes[14].key=capabilities/storage/3/persistent --set attributes[14].value=true \
        --set attributes[15].key=ip-lease --set attributes[15].value=true \\"

cmd2="--set from=$ACCOUNT_ADDRESS \
        --set key=\"$(cat /home/akash/key.pem | base64)\" \
        --set keysecret=\"$(echo $KEY_SECRET | base64)\" \
        --set domain=$DOMAIN \
        --set bidpricescript=\"$(cat /home/akash/bid-engine-script.sh | openssl base64 -A)\" \
        --set node=$NODE \
        --set log_restart_patterns=\"rpc node is not catching up|bid failed\" \
        --set resources.limits.cpu=\"1\" \
        --set resources.limits.memory=\"2Gi\" \
        --set resources.requests.cpu=\"0.5\" \
        --set resources.requests.memory=\"1Gi\""

# Initialize a variable to hold the new "--set" statements
new_sets=""

# Start index for the new attributes
index=16

# Loop through each variable in the environment
for var in $(compgen -v); do
    # Check if variable starts with "GPU_"
    if [[ $var == GPU_* ]]; then
        # Append the new "--set" statements to the new_sets string
        new_sets+=" --set attributes[$index].key=capabilities/gpu/vendor/nvidia/model/${!var} --set attributes[$index].value=true \\"
        ((index++)) # Increment the index for the next attribute
    fi
done

# Concatenate cmd1, new_sets, and cmd2 to form the final command
final_cmd="$cmd1$new_sets$cmd2"

# Execute the final command
eval $final_cmd

# Provider customizations
kubectl set env statefulset/akash-provider AKASH_BROADCAST_MODE=block AKASH_TX_BROADCAST_TIMEOUT=15m0s AKASH_BID_TIMEOUT=15m0s AKASH_LEASE_FUNDS_MONITOR_INTERVAL=90s AKASH_WITHDRAWAL_PERIOD=72h -n akash-services

# Hostname Operator
helm upgrade --install akash-hostname-operator akash/akash-hostname-operator -n akash-services

# Inventory Operator
helm upgrade --install inventory-operator akash/akash-inventory-operator -n akash-services

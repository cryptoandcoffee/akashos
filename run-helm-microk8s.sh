export KUBECONFIG=/home/akash/.kube/kubeconfig
. variables
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

kubectl apply -f https://raw.githubusercontent.com/akash-network/provider/v0.2.1/pkg/apis/akash.network/crd.yaml

# Node
helm upgrade --install akash-node akash/akash-node -n akash-services \
  --set akash_node.api_enable=true \
  --set akash_node.minimum_gas_prices=0uakt \
  --set state_sync.enabled=false \
  --set akash_node.snapshot_provider=polkachu \
  --set resources.limits.cpu="4" \
  --set resources.limits.memory="8Gi" \
  --set resources.requests.cpu="2" \
  --set resources.requests.memory="4Gi"

# Provider
helm upgrade --install akash-provider akash/provider -n akash-services \
             --set attributes[0].key=region --set attributes[0].value=$REGION \
             --set attributes[1].key=chia-plotting --set attributes[1].value=$CHIA_PLOTTING \
             --set attributes[2].key=host --set attributes[2].value=$HOST \
             --set attributes[3].key=cpu --set attributes[3].value=$CPU \
             --set attributes[4].key=tier --set attributes[4].value=$TIER \
             --set attributes[5].key=network_download --set attributes[5].value=$DOWNLOAD \
             --set attributes[6].key=network_upload --set attributes[6].value=$UPLOAD \
             --set attributes[7].key=status --set attributes[7].value=https://status.$DOMAIN \
             --set from=$ACCOUNT_ADDRESS \
             --set key="$(cat ./key.pem | base64)" \
             --set keysecret="$(echo $KEY_SECRET | base64)" \
             --set domain=$DOMAIN \
             --set bidpricescript="$(cat bid-engine-script.sh | openssl base64 -A)" \
             --set node=$NODE \
             --set log_restart_patterns="rpc node is not catching up|bid failed" \
             --set resources.limits.cpu="2" \
             --set resources.limits.memory="2Gi" \
             --set resources.requests.cpu="1" \
             --set resources.requests.memory="1Gi"

# Provider customizations
kubectl set env statefulset/akash-provider AKASH_BROADCAST_MODE=block AKASH_TX_BROADCAST_TIMEOUT=15m0s AKASH_BID_TIMEOUT=15m0s AKASH_LEASE_FUNDS_MONITOR_INTERVAL=90s AKASH_WITHDRAWAL_PERIOD=1h -n akash-services

# Hostname Operator
helm upgrade --install akash-hostname-operator akash/akash-hostname-operator -n akash-services

# Inventory Operator
helm upgrade --install inventory-operator akash/akash-inventory-operator -n akash-services

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
    enable-real-ip: true
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

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --version 4.7.0 \
  --namespace ingress-nginx --create-namespace \
  -f ingress-nginx-custom.yaml
  
kubectl label ns ingress-nginx app.kubernetes.io/name=ingress-nginx app.kubernetes.io/instance=ingress-nginx
kubectl label ingressclass akash-ingress-class akash.network=true

}
ingress_charts

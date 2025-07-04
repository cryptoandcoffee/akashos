#!/bin/bash
cd /home/akash

export KUBECONFIG=/home/akash/.kube/kubeconfig
. /home/akash/variables

helm repo add akash https://akash-network.github.io/helm-charts
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add rook-release https://charts.rook.io/release
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia

helm repo update



setup_environment() {
    # Kubernetes config
    kubectl create ns akash-services
    kubectl label ns akash-services akash.network/name=akash-services akash.network=true
    kubectl create ns lease
    kubectl label ns lease akash.network=true
    kubectl apply -f https://raw.githubusercontent.com/akash-network/provider/main/pkg/apis/akash.network/crd.yaml
}

ip_leases(){
#IP leases
kubectl create ns metallb-system
helm repo add metallb https://metallb.github.io/metallb
helm upgrade --install metallb metallb/metallb -n metallb-system --wait
kubectl -n metallb-system expose deployment metallb-controller --name=controller --overrides='{"spec":{"ports":[{"protocol":"TCP","name":"monitoring","port":7472}]}}'
helm upgrade --install akash-ip-operator akash/akash-ip-operator -n akash-services --set provider_address=$ACCOUNT_ADDRESS --wait
kubectl apply -f metal-lb.yml
}


ingress_charts() {
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
  "8443": "akash-services/akash-provider:8443"
  "8444": "akash-services/akash-provider:8444"
  "1317": "akash-services/akash-node-1:1317"
  "9090":  "akash-services/akash-node-1:9090"
  "26656": "akash-services/akash-node-1:26656"
  "26657": "akash-services/akash-node-1:26657"
EOF
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
      --namespace ingress-nginx --create-namespace \
      -f ingress-nginx-custom.yaml

kubectl label ns ingress-nginx app.kubernetes.io/name=ingress-nginx app.kubernetes.io/instance=ingress-nginx
kubectl label ingressclass akash-ingress-class akash.network=true

}

node_setup() {
    helm upgrade --install akash-node akash/akash-node -n akash-services \
      --set akash_node.api_enable=true \
      --set akash_node.minimum_gas_prices=0uakt \
      --set akash_node.snapshot_provider=polkachu \
      --set state_sync.enabled=false \
      --set resources.limits.cpu="2" \
      --set resources.limits.memory="8Gi" \
      --set resources.requests.cpu="2" \
      --set resources.requests.memory="4Gi"

    #Get from Cosmos Chain Registry
    PERSISTENT_PEERS=$(curl -s https://raw.githubusercontent.com/cosmos/chain-registry/master/akash/chain.json | jq -r '.peers.seeds[] | "\(.id)@\(.address)"' | paste -sd,)
    #Get from Running Node
    LIVE_PEERS=$(curl -s https://akash-rpc.polkachu.com/net_info | jq -r '.result.peers[] | "\(.node_info.id)@\(.node_info.listen_addr)"' | grep -v "tcp" | paste -sd,)

    kubectl set env statefulset/akash-node-1 -n akash-services \
      AKASH_PRUNING=custom \
      AKASH_PRUNING_INTERVAL=10 \
      AKASH_PRUNING_KEEP_RECENT=100 \
      AKASH_PRUNING_KEEP_EVERY=0 \
      AKASH_P2P_SEED_MODE=false \
      AKASH_P2P_PEX=true \
      AKASH_P2P_PERSISTENT_PEERS="$PERSISTENT_PEERS,$LIVE_PEERS"

    kubectl rollout restart statefulset/akash-node-1 -n akash-services
}

provider_setup() {
    helm upgrade --install akash-provider akash/provider -n akash-services \
        --set attributes[0].key=region --set attributes[0].value=$REGION \
        --set attributes[1].key=chia-plotting --set attributes[1].value=$CHIA_PLOTTING \
        --set attributes[2].key=host --set attributes[2].value=$HOST \
        --set attributes[3].key=cpu --set attributes[3].value=$CPU \
        --set attributes[4].key=tier --set attributes[4].value=$TIER \
        --set attributes[5].key=network_download --set attributes[5].value=$DOWNLOAD \
        --set attributes[6].key=network_upload --set attributes[6].value=$UPLOAD \
        --set attributes[7].key=status --set attributes[7].value=https://status.$DOMAIN \
        --set attributes[8].key=capabilities/storage/1/class --set attributes[8].value=beta1 \
        --set attributes[9].key=capabilities/storage/1/persistent --set attributes[9].value=true \
        --set attributes[10].key=capabilities/storage/2/class --set attributes[10].value=beta2 \
        --set attributes[11].key=capabilities/storage/2/persistent --set attributes[11].value=true \
        --set attributes[12].key=capabilities/storage/3/class --set attributes[12].value=beta3 \
        --set attributes[13].key=capabilities/storage/3/persistent --set attributes[13].value=true \
        --set email=$PROVIDER_EMAIL \
        --set website=$PROVIDER_WEBSITE \
        --set from=$ACCOUNT_ADDRESS \
        --set key="$(cat /home/akash/key.pem | base64)" \
        --set keysecret="$(echo $KEY_SECRET | base64)" \
        --set domain=$DOMAIN \
        --set bidpricescript="$(cat /home/akash/bid-engine-script.sh | openssl base64 -A)" \
        --set ipoperator=false \
        --set log_restart_patterns="rpc node is not catching up|bid failed" \
        --set resources.limits.cpu="2" \
        --set resources.limits.memory="2Gi" \
        --set resources.requests.cpu="1" \
        --set resources.requests.memory="1Gi" \
        --set gasprices="0.025uakt" \
        --set gasadjustment="1.75" \
        --set gas="auto" \
        --set tx_broadcast_timeout="15m0s" \
        --set bid_timeout="15m0s" \
        --set lease_funds_monitor_interval="90s" \
        --set withdrawalperiod="24h" \
        --set node="https://rpc.akashedge.com:443"

    kubectl patch configmap akash-provider-scripts \
      --namespace akash-services \
      --type json \
      --patch='[{"op": "add", "path": "/data/liveness_checks.sh", "value":"#!/bin/bash\necho \"Liveness check bypassed\""}]'

    kubectl rollout restart statefulset/akash-provider -n akash-services
}


hostname_operator() {
    helm upgrade --install akash-hostname-operator akash/akash-hostname-operator -n akash-services
}

inventory_operator() {
    helm upgrade --install inventory-operator akash/akash-inventory-operator -n akash-services
}

persistent_storage() {
echo "Persistent storage - MUST INSTALL apt-get install -y lvm2 on EACH NODDE BEFORE RUNNING"
    cat > rook.yml << EOF
operatorNamespace: rook-ceph

configOverride: |
  [global]
  osd_pool_default_pg_autoscale_mode = on
  osd_pool_default_size = 1
  osd_pool_default_min_size = 1

cephClusterSpec:
  resources:

  mon:
    count: 1
  mgr:
    count: 1

  storage:
    useAllNodes: true
    useAllDevices: true
    config:
      osdsPerDevice: "1"

cephBlockPools:
  - name: akash-deployments
    spec:
      failureDomain: host
      replicated:
        size: 1
      parameters:
        min_size: "1"
        deviceFilter: "^vd[a-z]$"
    storageClass:
      enabled: true
      name: beta1
      isDefault: false
      reclaimPolicy: Delete
      allowVolumeExpansion: true
      parameters:
        imageFormat: "2"
        imageFeatures: layering
        csi.storage.k8s.io/provisioner-secret-name: rook-csi-rbd-provisioner
        csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
        csi.storage.k8s.io/controller-expand-secret-name: rook-csi-rbd-provisioner
        csi.storage.k8s.io/controller-expand-secret-namespace: rook-ceph
        csi.storage.k8s.io/node-stage-secret-name: rook-csi-rbd-node
        csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
        csi.storage.k8s.io/fstype: ext4

  - name: akash-deployments
    spec:
      failureDomain: host
      replicated:
        size: 1
      parameters:
        min_size: "1"
        deviceFilter: "^sd[a-z]$"
    storageClass:
      enabled: true
      name: beta2
      isDefault: false
      reclaimPolicy: Delete
      allowVolumeExpansion: true
      parameters:
        imageFormat: "2"
        imageFeatures: layering
        csi.storage.k8s.io/provisioner-secret-name: rook-csi-rbd-provisioner
        csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
        csi.storage.k8s.io/controller-expand-secret-name: rook-csi-rbd-provisioner
        csi.storage.k8s.io/controller-expand-secret-namespace: rook-ceph
        csi.storage.k8s.io/node-stage-secret-name: rook-csi-rbd-node
        csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
        csi.storage.k8s.io/fstype: ext4

  - name: akash-deployments
    spec:
      failureDomain: host
      replicated:
        size: 1
      parameters:
        min_size: "1"
        deviceFilter: "^nvme[0-9]$"
    storageClass:
      enabled: true
      name: beta3
      isDefault: false
      reclaimPolicy: Delete
      allowVolumeExpansion: true
      parameters:
        imageFormat: "2"
        imageFeatures: layering
        csi.storage.k8s.io/provisioner-secret-name: rook-csi-rbd-provisioner
        csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
        csi.storage.k8s.io/controller-expand-secret-name: rook-csi-rbd-provisioner
        csi.storage.k8s.io/controller-expand-secret-namespace: rook-ceph
        csi.storage.k8s.io/node-stage-secret-name: rook-csi-rbd-node
        csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
        csi.storage.k8s.io/fstype: ext4

  - name: akash-nodes
    spec:
      failureDomain: host
      replicated:
        size: 1
      parameters:
        min_size: "1"
    storageClass:
      enabled: true
      name: akash-nodes
      isDefault: false
      reclaimPolicy: Delete
      allowVolumeExpansion: true
      parameters:
        # RBD image format. Defaults to "2".
        imageFormat: "2"
        # RBD image features. Available for imageFormat: "2". CSI RBD currently supports only `layering` feature.
        imageFeatures: layering
        # The secrets contain Ceph admin credentials.
        csi.storage.k8s.io/provisioner-secret-name: rook-csi-rbd-provisioner
        csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
        csi.storage.k8s.io/controller-expand-secret-name: rook-csi-rbd-provisioner
        csi.storage.k8s.io/controller-expand-secret-namespace: rook-ceph
        csi.storage.k8s.io/node-stage-secret-name: rook-csi-rbd-node
        csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
        # Specify the filesystem type of the volume. If not specified, csi-provisioner
        # will set default as `ext4`. Note that `xfs` is not recommended due to potential deadlock
        # in hyperconverged settings where the volume is mounted on the same node as the osds.
        csi.storage.k8s.io/fstype: ext4

# Do not create default Ceph file systems, object stores
cephFileSystems:
cephObjectStores:

# Spawn rook-ceph-tools, useful for troubleshooting
toolbox:
  enabled: true
  resources:
EOF

helm search repo rook-release --version v1.12.4
helm upgrade --install --wait --create-namespace -n rook-ceph rook-ceph rook-release/rook-ceph --version 1.12.4
echo "Did you update nodes in rook-ceph-cluster.values1.yml?"
#SHOWS DUPLICATE ISSUE - WORKS WHEN RUN TWICE
helm upgrade --install --create-namespace -n rook-ceph rook-ceph-cluster --set operatorNamespace=rook-ceph rook-release/rook-ceph-cluster --version 1.12.4 -f rook.yml --force

sleep 30

kubectl label sc akash-nodes akash.network=true
kubectl label sc beta3 akash.network=true
kubectl label sc beta2 akash.network=true
kubectl label sc beta1 akash.network=true

echo "Did you update this label to the same node in rook-ceph-cluster.values1.yml?"
kubectl label node $PERSISTENT_STORAGE_NODE1 akash.network/storageclasses=${PERSISTENT_STORAGE_NODE1_CLASS} --overwrite
kubectl label node $PERSISTENT_STORAGE_NODE2 akash.network/storageclasses=${PERSISTENT_STORAGE_NODE3_CLASS} --overwrite
kubectl label node $PERSISTENT_STORAGE_NODE3 akash.network/storageclasses=${PERSISTENT_STORAGE_NODE3_CLASS} --overwrite

echo "If health not OK, do this"
kubectl -n rook-ceph exec -it $(kubectl -n rook-ceph get pod -l "app=rook-ceph-tools" -o jsonpath='{.items[0].metadata.name}') -- bash -c "ceph health mute POOL_NO_REDUNDANCY"
}

run_functions() {
    for func in "$@"; do
        if declare -f "$func" > /dev/null; then
            echo "Running $func"
            "$func"
        else
            echo "Error: $func is not a known function"
            exit 1
        fi
    done
}

if [ "$#" -eq 0 ]; then
    run_functions setup_environment ingress_charts node_setup provider_setup hostname_operator inventory_operator
else
    run_functions "$@"
fi

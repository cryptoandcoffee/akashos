#!/bin/bash
cd /home/akash

export KUBECONFIG=/home/akash/.kube/kubeconfig
# Specify the absolute path of the variables file
variables="/home/akash/variables"

# Source the variables file if it exists
[ -e "$variables" ] && . "$variables"

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
  "1317": "akash-services/akash-node-1:1317"
  "8443": "akash-services/akash-provider:8443"
  "9090":  "akash-services/akash-node-1:9090"
  "26656": "akash-services/akash-node-1:26656"
  "26657": "akash-services/akash-node-1:26657"
EOF
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
      --namespace ingress-nginx --create-namespace \
      -f ingress-nginx-custom.yaml
}

node_setup() {
    helm upgrade --install akash-node akash/akash-node -n akash-services \
      --set akash_node.api_enable=true \
      --set akash_node.minimum_gas_prices=0uakt \
      --set state_sync.enabled=false \
      --set akash_node.snapshot_provider=autostake \
      --set resources.limits.cpu="2" \
      --set resources.limits.memory="8Gi" \
      --set resources.requests.cpu="0.5" \
      --set resources.requests.memory="4Gi"

    # Node customizations
    kubectl set env statefulset/akash-node-1 AKASH_PRUNING=custom AKASH_PRUNING_INTERVAL=100 AKASH_PRUNING_KEEP_RECENT=100 AKASH_PRUNING_KEEP_EVERY=100 -n akash-services
}

provider_setup() {
# Run nvidia-smi command to get GPU information
gpu_info="$(nvidia-smi --query-gpu=gpu_name --format=csv,noheader)"
gpu_models=$(echo "$gpu_info" | awk 'BEGIN {FS = ", "} ; {print $1}' | awk '{print $6 substr($4, 1) tolower(substr($5, 1))}')

# Label nodes with specific GPU models using kubectl
node_name=$(hostname)
label_prefix="akash.network/capabilities.gpu.vendor.nvidia.model."

counter=1
for model in $gpu_models; do
    label_command="kubectl label node $node_name $label_prefix$model=true"
    $label_command
    
    # Construct the variable entry
    entry="GPU_$counter=$model"
    
    # Check if the entry already exists in the variables file
    if ! grep -q -e "^$entry$" $variables; then
        # If the entry does not exist, append it to the file
        echo "$entry" >> $variables
    fi
    
    ((counter++))
done

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
             --set attributes[14].key=capabilities/gpu/vendor/nvidia/model/$GPU_1 --set attributes[14].value=true \
             --set chainid=$CHAIN_ID \
             --set from=$ACCOUNT_ADDRESS \
             --set key="$(cat /home/akash/key.pem | base64)" \
             --set keysecret="$(echo $KEY_SECRET | base64)" \
             --set domain=$DOMAIN \
             --set bidpricescript="$(cat /home/akash/bid-engine-script.sh | openssl base64 -A)" \
             --set node=$NODE \
             --set log_restart_patterns="rpc node is not catching up|bid failed" \
             --set resources.limits.cpu="2" \
             --set resources.limits.memory="2Gi" \
             --set resources.requests.cpu="0.5" \
             --set resources.requests.memory="1Gi"

    # Provider customizations
    kubectl set env statefulset/akash-provider AKASH_BROADCAST_MODE=block AKASH_TX_BROADCAST_TIMEOUT=15m0s AKASH_BID_TIMEOUT=15m0s AKASH_LEASE_FUNDS_MONITOR_INTERVAL=90s AKASH_WITHDRAWAL_PERIOD=72h -n akash-services
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

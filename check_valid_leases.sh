. variables
export KUBECONFIG=./kubeconfig

md_pfx="akash.network"
md_lid="$md_pfx/lease.id"
md_nsn="$md_pfx/namespace"

jqexpr="[.[\"$md_nsn\"],.[\"$md_lid.owner\"],.[\"$md_lid.dseq\"],.[\"$md_lid.gseq\"],.[\"$md_lid.oseq\"],.[\"$md_lid.provider\"]]"

# Function to get namespaces with Akash Network labels
nsdata(){
  kubectl get ns -l "$md_pfx=true,$md_lid.provider" \
    -o jsonpath='{.items[*].metadata.labels}'
}

# Function to process lease data
ldata(){
  jq -rM "$jqexpr | @tsv"
}

# Iterate over namespaces and check for matching leases
nsdata | ldata | while read -r line; do
  ns="$(echo "$line" | awk '{print $1}')"
  owner="$(echo "$line" | awk '{print $2}')"
  dseq="$(echo "$line" | awk '{print $3}')"
  gseq="$(echo "$line" | awk '{print $4}')"
  oseq="$(echo "$line" | awk '{print $5}')"
  prov="$(echo "$line" | awk '{print $6}')"

  state=$(akash --node=https://akash-rpc.polkachu.com:443 query market lease get --oseq 0 --gseq 0 \
    --owner "$owner" \
    --dseq  "$dseq" \
    --gseq  "$gseq" \
    --oseq  "$oseq" \
    --provider "$prov" \
    -o yaml \
    | jq -r '.lease.state' \
  )

  if [ "$state" == "active" ]; then
    echo "Namespace $ns has an active lease with $owner"
  else
    echo "Warning: Namespace $ns does not have an active lease or lease is in state $state"
  fi
done

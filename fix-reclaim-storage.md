Add this to /etc/systemd/system/k3s.service


        '--flannel-backend=none' \
        '--kubelet-arg' \
        'eviction-hard=nodefs.available<1%,nodefs.inodesFree<1%' \
        '--kubelet-arg' \
        'eviction-soft=nodefs.available<2%,nodefs.inodesFree<2%' \
        '--kubelet-arg' \
        'eviction-soft-grace-period=nodefs.available=1m,nodefs.inodesFree=1m' \
        '--kubelet-arg' \
        'eviction-max-pod-grace-period=30' \
        '--kubelet-arg' \
        'eviction-minimum-reclaim=nodefs.available=1%,nodefs.inodesFree=1%' \
        '--kubelet-arg' \
        'eviction-pressure-transition-period=30s'

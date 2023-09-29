# AkashOS - Akash Provider OS  - Ubuntu Server 22.04 Edition


Feature Matrix and Status : Y = Working and Tested / T = Testing Phase / N = No Support

| Platform | Basic Provider | GPU | Persistent Storage | IP Leases | Update Support|
|----------|----------------|-----|--------------------|-----------|----------------
| k3s      | Y              | Y   | T                  | T         |Y
| microk8s | Y              | T   | T                  | T         |T
| k8s      | Y              | T   | T                  | T         |T


AkashOS is an unattended install of Ubuntu Server uses [Autoinstall](https://ubuntu.com/server/docs/install/autoinstall) and [cloud-init](https://cloudinit.readthedocs.io/en/latest/).  AkashOS will automatically create a Kubernetes cluster and configure itself as an Akash provider. 

Download and Attach the latest AkashOS Release ISO to any machine you would like to become a provider on the Akash Network such as Bare-Metal, VPS, or a Virtual Machine.

```
     Akash Provider
           ||
     -------------
    | Helm Charts |
     -------------
           ||
     -------------
   |  Kubernetes  |
     -------------
           ||
  -----------------------
|     cloud-init         |
  -----------------------
           ||
     -----------------------
|  Ubuntu 22.04 AutoInstall |
  --------------------------
```

# Supported Kubernetes installation methods

k3s / microk8s / kubespray

You will be prompted to choose an install path during the first boot.
The default install path is k3s.

# What is this image best used for?

You can use this image to takeover any x86 machine or virtual machine that you want to configure as a provider on the Akash network

# Target audience for this ISO - you should be on this list

1.  Hypervisor (Proxmox/VMware)
2.  Homelab
3.  Unraid/TrueNas
4.  DevOps/SRE/Kubernetes Admins
5.  Full stack developers

# Installation Difficulty Level

## Medium (terminal experience required)

Human Dependencies: ~30 minutes

  - Acquire at least 50 AKT
  - Add DNS records
  - Forward ports

Software Dependencies: ~30 minutes 

- Install Akash OS
- Configure Pricing


# Dependencies

## Human Requirements
1. Be ready to run workloads for dWeb.  Understand what you are getting into and be ready to learn.
2. Docker and Kubernetes experience will greatly help you, learn all you can.
3. With great power comes great responsibility. Be aware of the risks and use Lens to monitor your cluster.
4. If you experience any abuse, ddos, spam, or other issues please report the offending wallet address to the Akash team.

## Software
1. Domain name (example.com) that you own and can manage DNS records.
2. 50 AKT to send to new provider wallet
3. Access to your firewall/router for port forwarding
4. Lens - we recommend Lens for daily ops
5. Balena Etcher / Rufus / Ventoy
6. Dynamic DNS update client and domain for residential IP's

## Hardware Requirements First Node

- 2 CPU / 4 Threads
- 8Gb Memory 
- 32Gb Disk 

## Hardware Requirements Additional Nodes

- 1 CPU 
- 2Gb Memory 
- 8Gb Disk

# Installation Instructions
Default Username : akash
Default Password : akash

## Proxmox / VirtualBox / VMware

1. Download Akash OS ISO
2. Create VM - Attach a disk drive with the ISO
3. Start the VM
4. Reboot when install completed and detach the ISO.
6. Login with default username and password, follow the on-screen instructions.
7. Once the system has rebooted, goto the Control Panel address.
8. Update the provider attributes with the recommended values and click Save.
9. Click STOP next to Provider.
10. Click Re-Deploy Provider Button.
11. Send at least 5 AKT to the new wallet address to start the provider.

## Bare Metal Datacenter with IPMI/ISO Support

1. Download Akash OS ISO
2. Upload the ISO to the datacenter ISO storage location (Vultr/HostHatch/etc) or Attach the ISO to your IPMI Virtual Console Session.
3. Start the machine with the ISO for the boot drive (F11 may be required)
4. Reboot when install completed and detach the ISO.
6. Login with default username and password, follow the on-screen instructions.
7. Once the system has rebooted, goto the Control Panel address.
8. Update the provider attributes with the recommended values and click Save.
9. Click STOP next to Provider.
10. Click Re-Deploy Provider Button.
11. Send at least 5 AKT to the new wallet address to start the provider.

## USB Key

1. Download Akash OS ISO
2. Use Balena Etcher / Rufus / Ventoy to write the ISO to a USB key
3. Insert the USB key into the computer you want to make an Akash provider.
4. Start the machine with the USB key for the boot drive (F11 may be required)
5. Reboot when install completed and unplug the USB key.
6. Login with default username and password, follow the on-screen instructions.
7. Once the system has rebooted, goto the Control Panel address.
8. Update the provider attributes with the recommended values and click Save.
9. Click STOP next to Provider.
10. Click Re-Deploy Provider Button.
11. Send at least 5 AKT to the new wallet address to start the provider.

Todos:
-When changing pricing params, delete the configmap akash-provider-bidscripts from akash-services before re-deploy
-Remove static/dynamic question during initial boot, confusing to user
-Show nodes in cluster on Dashboard with kubectl get nodes -A -o wide
-Allow adding new node to cluster with just IP address
-Remove question for adding node to cluster for original IP, all add/remove operations should happen from Dashboard only
-Update run-helm-k3s to use functions so each can be called seperately
-Update bid-engine script with latest
-Add/Remove Attributes from Dashboard and default GPU etc


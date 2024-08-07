# AkashOS: Akash Provider OS - Ubuntu Server 24.04 Edition

![image](https://github.com/cryptoandcoffee/akashos/assets/19512127/600c9ac4-a030-4391-99ec-18738a228897)

Welcome to AkashOS, an innovative solution designed for those aspiring to become a [provider](https://deploy.cloudmos.io/providers) within the [Akash Network](https://akash.network). By harnessing the capabilities of [Autoinstall](https://ubuntu.com/server/docs/install/autoinstall) and [cloud-init](https://cloudinit.readthedocs.io/en/latest/), AkashOS facilitates a seamless, unattended installation of Ubuntu Server. It not only establishes a Kubernetes cluster autonomously but also deploys Helm charts configuring the system as an Akash Network provider.

Post-installation, users have the flexibility to configure the provider via a user-friendly Dashboard/GUI or through SSH, offering a versatile approach to provider configuration. The installation process has been meticulously refined to be as intuitive as possible for individuals aiming to join the Akash Network as providers. Users are required to answer a few straightforward questions during the installation, and AkashOS takes care of the rest, ensuring a smooth and easy setup experience.

## 🌟 Become a Provider with Ease!
Embark on your journey as a provider with a minimal investment of 25 AKT, valued at $21 at the time of writing. Dive into a world of unlimited earning possibilities within the Akash Network!

- 🧮 **Estimate Your Earnings:** Curious about what your hardware could be earning? Check out [Akash Calculator](https://akashcalcualtor.com)!
- 📊 **Explore Existing Provider Earnings:** Discover what existing providers are earning in real-time on the Akash Network at [Akash Dash](https://akashdash.com).

## 🛠 Quick & Easy Setup!
Download and attach the latest AkashOS Release ISO to your chosen hardware: **Bare-Metal, VPS, or Virtual Machine** and watch it transform into a provider on the Akash Network!

## 💡 Why AkashOS?
- **Streamlined & Automated:** Effortlessly install Ubuntu Server and configure your system with our automated setup!
- **Infinite Earnings:** Unlock unparalleled earning potential as a provider!
- **Versatile Application:** Compatible with various setups, ensuring everyone can join!

# What is this image best used for?

You can use this image to takeover any x86 machine or virtual machine that you want to configure as a provider on the Akash Network.

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

## Software Requirements
1. Domain name (example.com) that you own and can manage DNS records.
2. 50 AKT to send to new provider wallet
3. Access to your firewall/router for port forwarding
4. [Lens](https://k8slens.dev/) - Recommend for cluster daily ops - you will need this to easily interact with your new cluster
5. [Balena Etcher](https://www.balena.io/etcher/), [Rufus](https://rufus.ie/), or [Ventoy](https://www.ventoy.net/en/index.html) for creating bootable USB drives on Linux, Mac, PC.
6. Dynamic DNS update client and domain for residential IP's. 

## Hardware Requirements First Node

- 2 CPU / 4 Threads
- 8Gb Memory
- 64Gb Disk 

## Hardware Requirements Additional Nodes

- 1 CPU 
- 2Gb Memory 
- 8Gb Disk

## Proxmox / VirtualBox / VMware

1. Download Akash OS ISO
2. Create VM - Attach a disk drive with the ISO
3. Start the VM
4. Reboot when install completed and detach the ISO.
6. Login with default username and password "akash", follow the on-screen instructions.
7. Once the system has rebooted, goto the Control Panel address.
8. Update the provider attributes with the recommended values and click Save.
9. Click STOP next to Provider.
10. Click Re-Deploy Provider Button.
11. Send at least 5 AKT to the new wallet address to start the provider.
12. Click Download Kubeconfig and import into Lens. When first using Lens be sure to set the Namespace to : All or you won't see anything.

## Bare Metal Datacenter with IPMI/ISO Support

1. Download Akash OS ISO
2. Upload the ISO to the datacenter ISO storage location (Vultr/HostHatch/etc) or Attach the ISO to your IPMI Virtual Console Session.
3. Start the machine with the ISO for the boot drive (F11 may be required)
4. Reboot when install completed and detach the ISO.
6. Login with default username and password "akash", follow the on-screen instructions.
7. Once the system has rebooted, goto the Control Panel address.
8. Update the provider attributes with the recommended values and click Save.
9. Click STOP next to Provider.
10. Click Re-Deploy Provider Button.
11. Send at least 5 AKT to the new wallet address to start the provider.
12. Click Download Kubeconfig and import into Lens. When first using Lens be sure to set the Namespace to : All or you won't see anything.

## USB Key

1. Download Akash OS ISO
2. Use Balena Etcher / Rufus / Ventoy to write the ISO to a USB key
3. Insert the USB key into the computer you want to make an Akash provider.
4. Start the machine with the USB key for the boot drive (F11 may be required)
5. Reboot when install completed and unplug the USB key.
6. Login with default username and password "akash", follow the on-screen instructions.
7. Once the system has rebooted, goto the Control Panel address.
8. Update the provider attributes with the recommended values and click Save.
9. Click STOP next to Provider.
10. Click Re-Deploy Provider Button.
11. Send at least 5 AKT to the new wallet address to start the provider.
12. Click Download Kubeconfig and import into Lens. When first using Lens be sure to set the Namespace to : All or you won't see anything.

Todos:
-When changing pricing params, delete the configmap akash-provider-bidscripts from akash-services before re-deploy
-Remove static/dynamic question during initial boot, confusing to user
-Show nodes in cluster on Dashboard with kubectl get nodes -A -o wide
-Allow adding new node to cluster with just IP address
-Remove question for adding node to cluster for original IP, all add/remove operations should happen from Dashboard only
-Update run-helm-k3s to use functions so each can be called seperately
-Update bid-engine script with latest
-Add/Remove Attributes from Dashboard and default GPU etc

Stack:

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

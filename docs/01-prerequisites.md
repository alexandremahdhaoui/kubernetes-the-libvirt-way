# Prerequisites

## Bare metal machine

This tutorial leverages your bare metal machine to streamline provisioning of the compute infrastructure required to
bootstrap a Kubernetes cluster from the ground up.

### Fedora Server

Fedora Server will be the operating system we'll install on our . 
Please refer to the Fedora Server's install [documentation](TODO). 

### Folder

Please create these folders
```shell
mkdir -p /virt/images /virt/templates /virt/cloud-init
```

### Permanently disable swap

```shell
vi /etc/fstab
# And remove the `swap` partitions 
```

```shell
# Then add these command to be run on startup (even removing
systemctl mask "systemd-zram-setup@zram0.service"
swapoff -a
```

### Install a few binaries

```shell
dnf update && dnf upgrade
dnf install -y git jq bridge-utils cloud-utils genisoimage
```

### Install golang & rust for building binaries

```shell
dnf install -y golang rust cargo
```

### Create a bridge

### Create a virtual bridge that will be used for your VMs

## Virtualization

This tutorial will leverage `KVM` with `libvirt` to provide the virtualization layer.

### Fedora Cloud

Throughout this tutorial we will use the Fedora Cloud distribution, please download the qcow2 image into the 
`/virt/templates` folder

```shell
curl -Lo /virt/templates/fedora37.qcow2 \
  https://download.fedoraproject.org/pub/fedora/linux/releases/37/Cloud/x86_64/images/Fedora-Cloud-Base-37-1.7.x86_64.qcow2
```

### Verify KVM support

```shell
grep -E --color '(vmx|svm)' /proc/cpuinfo
lsmod | grep -i kvm
```

### Install libvirt dependencies

```shell
sudo dnf -y install bridge-utils libvirt virt-install qemu-kvm
```

Next: [Installing the Client Tools](02-client-tools.md)
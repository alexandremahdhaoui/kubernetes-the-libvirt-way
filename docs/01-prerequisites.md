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
mkdir -p /virt/images /virt/templates /virt/user-data
```

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
TODO


### Install libvirt dependencies
TODO

## Running Commands in Parallel with tmux

[tmux](https://github.com/tmux/tmux/wiki) can be used to run commands on multiple compute instances at the same time. Labs in this tutorial may require running the same commands across multiple compute instances, in those cases consider using tmux and splitting a window into multiple panes with synchronize-panes enabled to speed up the provisioning process.

> The use of tmux is optional and not required to complete this tutorial.

![tmux screenshot](images/tmux-screenshot.png)

> Enable synchronize-panes by pressing `ctrl+b` followed by `shift+:`. Next type `set synchronize-panes on` at the prompt. To disable synchronization: `set synchronize-panes off`.

Next: [Installing the Client Tools](02-client-tools.md)
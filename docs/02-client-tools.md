# Installing the Client Tools

In this lab you will install the command line utilities required to complete this tutorial: `bash`, `libvirt-utils`
[cfssl](https://github.com/cloudflare/cfssl), [cfssljson](https://github.com/cloudflare/cfssl), and
[kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl).

In this section, it is expected that commands are executed from the root user of your bare metal Fedora Server 
machine.

### Bash

This tutorial expects you're using `bash`, other scripting languages may not be supported.

### SSH key

Please generate an ed25519 ssh key  
```shell
ssh-keygen -t ed25519
```

Please export your public key as a variable. We will use it to generate the cloud-init generic config for our VMs.
```shell
export AUTHORIZED_KEY=$(cat ~/.ssh/id_ed25519.pub)
```

### Libvirt-utils

Libvirt-utils are bash functions abstracting VM provisioning and management operations, e.g. create/delete vms, ssh,
scp...

#### Install the libvirt-utils bash library

Just source it
```shell
. <(curl -L https://gitlab.com/alexandre.mahdhaoui/kubernetes-the-libvirt-way/-/raw/main/assets/libvirt-utils)
```

Or persist it in your bashrc
```shell
curl -sL https://gitlab.com/alexandre.mahdhaoui/kubernetes-the-libvirt-way/-/raw/main/assets/libvirt-utils.sh | tee -a ~/.bashrc
. ~/.bashrc
```

## Install CFSSL

The `cfssl` and `cfssljson` command line utilities will be used to provision a [PKI Infrastructure](https://en.wikipedia.org/wiki/Public_key_infrastructure) and generate TLS certificates.

Install `cfssl` and `cfssljson` using golang
```shell
go install github.com/cloudflare/cfssl/cmd/cfssl@latest
go install github.com/cloudflare/cfssl/cmd/cfssljson@latest
```

These command will most likely fail, we need to first install golang to build and install the binaries
```shell
dnf install -y golang
```

### Verification

Verify `cfssl` and `cfssljson` version 1.4.1 or higher is installed:

```shell
cfssl version
```

> output

```
Version: 1.4.1
Runtime: go1.12.12
```

```shell
cfssljson --version
```
```
Version: 1.4.1
Runtime: go1.12.12
```

## Install kubectl

The `kubectl` command line utility is used to interact with the Kubernetes API Server. We will build and install 
`kubectl` from source.

### Linux

```shell
{
  BINARY="kubectl"
  BIN_FOLDER="./_output/bin"
  BIN_DEST="/usr/local/bin"
  REPO="https://github.com/kubernetes/kubernetes.git"
  REPO_DIR="$(basename "${REPO}" .git)"
  VERSION="v1.26.3"
  {
    git clone -b "${VERSION}" "${REPO}"
    cd "${REPO_DIR}"
    make
    chmod 755 "./${BIN_FOLDER}"/*
  }
  mv "${BIN_FOLDER}/${BINARY}" "${BIN_DEST}"
  cd
  rm -rf "./${REPO_DIR}"
}
```

### Verification

Verify `kubectl` version 1.26.3 is installed:

```shell
kubectl version --client -o json
```

> output

```json
{
  "clientVersion": {
    "major": "1",
    "minor": "26",
    "gitVersion": "v1.26.3",
    "gitCommit": "9e644106593f3f4aa98f8a84b23db5fa378900bd",
    "gitTreeState": "clean",
    "buildDate": "2023-03-23T18:10:41Z",
    "goVersion": "go1.19.7",
    "compiler": "gc",
    "platform": "linux/amd64"
  },
  "kustomizeVersion": "v4.5.7"
}
```

Next: [Provisioning Compute Resources](03-compute-resources.md)

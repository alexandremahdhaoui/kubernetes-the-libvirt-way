# Bootstrapping the Kubernetes Worker Nodes

In this lab you will bootstrap three Kubernetes worker nodes. The following components will be installed on each node:
[runc](https://github.com/opencontainers/runc), [container networking plugins](https://github.com/containernetworking/cni),
[containerd](https://github.com/containerd/containerd), [kubelet](https://kubernetes.io/docs/admin/kubelet), and
[kube-proxy](https://kubernetes.io/docs/concepts/cluster-administration/proxies).

## Prerequisites

The commands in this lab must be run on each worker instance: `worker0`, `worker1`, and `worker2`.
Login to each worker instance using the `vm.ssh` command. Example:

```
vm.ssh worker0
```

## Provisioning a Kubernetes Worker Node

Install the OS dependencies:

```shell
{
  for x in {0..2}; do
    NAME="worker${x}"
    vm.exec "${NAME}" 'sudo dnf install -y socat conntrack ipset iptables-services nftables && sudo modprobe ip_conntrack' &
  done
}
```

> The socat binary enables support for the `kubectl port-forward` command.

### Disable Swap

By default the kubelet will fail to start if [swap](https://help.ubuntu.com/community/SwapFaq) is enabled. It is [recommended](https://github.com/kubernetes/kubernetes/issues/7294) that swap be disabled to ensure Kubernetes can provide proper resource allocation and quality of service.

Verify if swap is enabled:

```shell
sudo swapon --show
```

If output is empthy then swap is not enabled. If swap is enabled run the following command to disable swap immediately:

```shell
sudo swapoff -a
```

> To ensure swap remains off after reboot consult your Linux distro documentation.

### Download and Install Worker Binaries

List of binaries:
- `crictl`
- `runc`
- `cni-plugins`
- `containerd`
- `kubectl`
- `kube-proxy`
- `kubelet`

#### Create the installation directories:

```shell
{
  for x in {0..2}; do
    NAME="worker${x}"
    vm.exec "${NAME}" 'sudo mkdir -p /etc/cni/net.d /opt/cni/bin /var/lib/kubelet /var/lib/kube-proxy /var/lib/kubernetes /var/run/kubernetes'
  done
}
```

#### crictl

```shell
{
  BIN_FILE="crictl"
  BIN_DEST="/usr/local/bin"
  REPO="https://github.com/kubernetes-sigs/cri-tools.git"
  REPO_DIR="cri-tools"
  LATEST_PATCH=$(git ls-remote "${REPO}" | grep "v1\.26\.[0-9]*$" | sed 's/.*tags\///' | sort | tail -n 1)
  {
    git clone -b "${LATEST_PATCH}" "${REPO}"
    cd "${REPO_DIR}"
    go build "./cmd/${BIN_FILE}"
    chmod 755 "${BIN_FILE}"
  }
  for x in {0..2}; do
    NAME="worker${x}"
    vm.scp "${BIN_FILE}" "${NAME}" '~/'
    vm.exec "${NAME}" "sudo mv \"${BIN_FILE}\" \"${BIN_DEST}\""
    vm.exec "${NAME}" "sudo restorecon -Rv \"${BIN_DEST}\""
  done
  cd -
  rm -rf "./${REPO_DIR}"
}
```

#### runc

```shell
{
  BIN_FILE="runc"
  BIN_DEST="/usr/local/sbin"
  REPO="https://github.com/opencontainers/runc"
  REPO_DIR="runc"
  {
    dnf install -y libseccomp libseccomp-devel
    git clone "${REPO}"
    cd "${REPO_DIR}"
    make
    make install
    cd -
    rm -rf "./${REPO_DIR}"
    mv "/usr/local/sbin/${BIN_FILE}" ./
    chmod 755 "${BIN_FILE}"
  }
  for x in {0..2}; do
    NAME="worker${x}"
    vm.scp "${BIN_FILE}" "${NAME}" '~/'
    vm.exec "${NAME}" "sudo mv \"${BIN_FILE}\" \"${BIN_DEST}\""
    vm.exec "${NAME}" "sudo restorecon -Rv \"${BIN_DEST}\""
  done
  rm "${BIN_FILE}"
}
```

#### CNI Plugin

```shell
{
  BIN_FOLDER="cni_bin"
  BIN_DEST="/opt/cni/bin/"
  REPO="https://github.com/containernetworking/plugins.git"
  REPO_DIR="plugins"
  {
    LATEST_PATCH=$(git ls-remote "${REPO}" | grep "v1\.[0-9]*\.[0-9]*$" | sed 's/.*tags\///' | sort | tail -n 1)
    git clone -b "${LATEST_PATCH}" "${REPO}"
    cd "${REPO_DIR}"
    export GOOS="${GOOS:-linux}"
    export GOFLAGS="${GOFLAGS} -mod=vendor"
    mkdir -p "${PWD}/${BIN_FOLDER}"
    echo "Building plugins ${GOOS}"
    PLUGINS="plugins/meta/* plugins/main/* plugins/ipam/*"
    for d in $PLUGINS; do
      if [ -d "$d" ]; then
        plugin="$(basename "$d")"
        if [ "${plugin}" != "windows" ]; then
          echo "  $plugin"
          ${GO:-go} build -o "${PWD}/${BIN_FOLDER}/$plugin" "$@" ./"$d"
          chmod 755 "${BIN_FOLDER}"/*
        fi
      fi
    done   
  }
  for x in {0..2}; do
    NAME="worker${x}"
    vm.scp "${BIN_FOLDER}" "${NAME}" '~/'
    vm.exec "${NAME}" "sudo mkdir -p \"${BIN_DEST}\""
    vm.exec "${NAME}" "sudo mv \"${BIN_FOLDER}\"/* \"${BIN_DEST}\" && sudo rm -rf \"${BIN_FOLDER}\""
    vm.exec "${NAME}" "sudo restorecon -Rv \"${BIN_DEST}\""
  done
  cd
  rm -rf "./${REPO_DIR}"
}
```

#### Containerd

```shell
{
  BIN_FOLDER="containerd_bin"
  BIN_DEST="/bin/"
  REPO="https://github.com/containerd/containerd.git"
  REPO_DIR="containerd"
  {
    dnf install -y protobuf-compiler
    LATEST_PATCH=$(git ls-remote "${REPO}" | grep "v1\.[0-9]*\.[0-9]*$" | sed 's/.*tags\///' | sort | tail -n 1)
    git clone -b "${LATEST_PATCH}" "${REPO}"
    cd "${REPO_DIR}"
    make && mv ./bin "./${BIN_FOLDER}"
    chmod 755 -R "./${BIN_FOLDER}"
  }
  for x in {0..2}; do
    NAME="worker${x}"
    vm.scp "${BIN_FOLDER}" "${NAME}" '~/'
    vm.exec "${NAME}" "sudo mkdir -p \"${BIN_DEST}\""
    vm.exec "${NAME}" "sudo mv \"${BIN_FOLDER}\"/* \"${BIN_DEST}\" && sudo rm -rf \"${BIN_FOLDER}\""
    vm.exec "${NAME}" "sudo restorecon -Rv /usr/bin" # notice we are using /usr/bin because restorecon does not follow symbolic links
  done
  cd
  rm -rf "./${REPO_DIR}"
}
```

#### Kubectl, kube-prox, kubelet

```shell
{
  BINARIES="kubectl kube-proxy kubelet"
  BIN_FOLDER="kube_bin"
  BIN_DEST="/usr/local/bin"
  REPO="https://github.com/kubernetes/kubernetes.git"
  REPO_DIR="kubernetes"
  {
    LATEST_PATCH=$(git ls-remote "${REPO}" | grep "tags/v1\.26\.[0-9]*$" | sed "s/.*tags\///" | sort | tail -n 1)
    git clone -b "${LATEST_PATCH}" "${REPO}"
    cd "${REPO_DIR}"
    mkdir "${BIN_FOLDER}"
    for x in ${BINARIES}; do go build -o "${BIN_FOLDER}" "./cmd/${x}";done
    chmod 755 "./${BIN_FOLDER}"/*
  }
  for x in {0..2}; do
    NAME="worker${x}"
    vm.scp "${BIN_FOLDER}" "${NAME}" '~/'
    vm.exec "${NAME}" "sudo mkdir -p \"${BIN_DEST}\""
    vm.exec "${NAME}" "sudo mv \"${BIN_FOLDER}\"/* \"${BIN_DEST}\" && sudo rm -rf \"${BIN_FOLDER}\""
    vm.exec "${NAME}" "sudo restorecon -Rv \"${BIN_DEST}\""
  done
  cd
  rm -rf "./${REPO_DIR}"
}
```

### Configure CNI Networking

Retrieve the Pod CIDR range for the current compute instance:

Create the `bridge` network configuration file:

```shell
{
POD_CIDR="10.0.0.0/24"
FILENAME="10-bridge.conf"
DEST_PATH="/etc/cni/net.d/"
cat <<EOF | tee "${FILENAME}"
{
    "cniVersion": "0.4.0",
    "name": "bridge",
    "type": "bridge",
    "bridge": "cnio0",
    "isGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "ranges": [
          [{"subnet": "${POD_CIDR}"}]
        ],
        "routes": [{"dst": "0.0.0.0/0"}]
    }
}
EOF
for x in {0..2}; do
NAME="worker${x}"
vm.scp "${FILENAME}" "${NAME}" '~/'
vm.exec "${NAME}" "sudo mkdir -p \"${DEST_PATH}\""
vm.exec "${NAME}" "sudo mv \"${FILENAME}\" \"${DEST_PATH}\""
vm.exec "${NAME}" "sudo restorecon -Rv \"${DEST_PATH}\""
done
}
```

Create the `loopback` network configuration file:

```shell
{
POD_CIDR="10.0.0.0/24"
FILENAME="99-loopback.conf"
DEST_PATH="/etc/cni/net.d/"
cat <<EOF | tee "${FILENAME}"
{
    "cniVersion": "0.4.0",
    "name": "lo",
    "type": "loopback"
}
EOF
for x in {0..2}; do
NAME="worker${x}"
vm.scp "${FILENAME}" "${NAME}" '~/'
vm.exec "${NAME}" "sudo mkdir -p \"${DEST_PATH}\""
vm.exec "${NAME}" "sudo mv \"${FILENAME}\" \"${DEST_PATH}\""
vm.exec "${NAME}" "sudo restorecon -Rv \"${DEST_PATH}\""
done
}
```

### Configure containerd

Create the `containerd` configuration file:

```shell
{
  for x in {0..2}; do 
    NAME="worker${x}"
    vm.exec "${NAME}" "sudo mkdir -p /etc/containerd"
  done
}
```

```shell
{
FILENAME="config.toml"
DEST_PATH="/etc/containerd/"
cat <<EOF | tee "${FILENAME}"
[plugins]
  [plugins.cri.containerd]
    snapshotter = "overlayfs"
    [plugins.cri.containerd.default_runtime]
      runtime_type = "io.containerd.runtime.v1.linux"
      runtime_engine = "/usr/local/bin/runc"
      runtime_root = ""
EOF
for x in {0..2}; do
NAME="worker${x}"
vm.scp "${FILENAME}" "${NAME}" '~/'
vm.exec "${NAME}" "sudo mkdir -p \"${DEST_PATH}\""
vm.exec "${NAME}" "sudo mv \"${FILENAME}\" \"${DEST_PATH}\""
vm.exec "${NAME}" "sudo restorecon -Rv \"${DEST_PATH}\""
done
}
```

Create the `containerd.service` systemd unit file:

```shell
{
FILENAME="containerd.service"
DEST_PATH="/etc/systemd/system/"

cat <<EOF | tee "${FILENAME}"
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target

[Service]
ExecStartPre=/sbin/modprobe overlay
ExecStart=/bin/containerd
Restart=always
RestartSec=5
Delegate=yes
KillMode=process
OOMScoreAdjust=-999
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
EOF

for x in {0..2}; do
NAME="worker${x}"
vm.scp "${FILENAME}" "${NAME}" '~/'
vm.exec "${NAME}" "sudo mkdir -p \"${DEST_PATH}\""
vm.exec "${NAME}" "sudo mv \"${FILENAME}\" \"${DEST_PATH}\""
vm.exec "${NAME}" "sudo restorecon -Rv \"${DEST_PATH}\""
done
}
```

### Configure the Kubelet

In case you need to copy the files from the server again

```shell
{
  for x in {0..2}; do vm.scp worker${x}*.pem worker${x}.kubeconfig ca.pem  worker${x} '~/';done
}
```

```shell
{
  for x in {0..2}; do
    HOSTNAME="worker${x}"
    vm.exec "$HOSTNAME" "sudo mkdir -p /var/lib/kubelet /var/lib/kubernetes"
    vm.exec "${HOSTNAME}" "sudo mv \"${HOSTNAME}-key.pem\" \"${HOSTNAME}.pem\" /var/lib/kubelet/"
    vm.exec "${HOSTNAME}" "sudo mv \"${HOSTNAME}.kubeconfig\" /var/lib/kubelet/kubeconfig"
    vm.exec "${HOSTNAME}" "sudo mv ca.pem /var/lib/kubernetes/"
  done
}
```

Create the `kubelet-config.yaml` configuration file:

```shell
{
POD_CIDR="10.0.0.0/24"
CLUSTER_DNS="10.0.0.10"
FILENAME="kubelet-config.yaml"
DEST_PATH="/var/lib/kubelet/"

for x in {0..2}; do
HOSTNAME="worker${x}"
cat <<EOF | tee "${FILENAME}"
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "/var/lib/kubernetes/ca.pem"
authorization:
  mode: Webhook
clusterDomain: "cluster.local"
clusterDNS:
  - "${CLUSTER_DNS}"
podCIDR: "${POD_CIDR}"
resolvConf: "/run/systemd/resolve/resolv.conf"
runtimeRequestTimeout: "15m"
tlsCertFile: "/var/lib/kubelet/${HOSTNAME}.pem"
tlsPrivateKeyFile: "/var/lib/kubelet/${HOSTNAME}-key.pem"
EOF

vm.scp "${FILENAME}" "${HOSTNAME}" '~/'
vm.exec "${HOSTNAME}" "sudo mkdir -p \"${DEST_PATH}\""
vm.exec "${HOSTNAME}" "sudo mv \"${FILENAME}\" \"${DEST_PATH}\""
vm.exec "${HOSTNAME}" "sudo restorecon -Rv \"${DEST_PATH}\""
done
}
```

> The `resolvConf` configuration is used to avoid loops when using CoreDNS for service discovery on systems running `systemd-resolved`.

Create the `kubelet.service` systemd unit file:
```shell
{
FILENAME="kubelet.service"
DEST_PATH="/etc/systemd/system/"

cat <<EOF | tee "${FILENAME}"
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --config=/var/lib/kubelet/kubelet-config.yaml \\
  --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock \\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\
  --register-node=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

for x in {0..2}; do
NAME="worker${x}"
vm.scp "${FILENAME}" "${NAME}" '~/'
vm.exec "${NAME}" "sudo mkdir -p \"${DEST_PATH}\""
vm.exec "${NAME}" "sudo mv \"${FILENAME}\" \"${DEST_PATH}\""
vm.exec "${NAME}" "sudo restorecon -Rv \"${DEST_PATH}\""
done
}
```

### Configure the Kubernetes Proxy

```shell
{
  for x in {0..2}; do
    HOSTNAME="worker${x}"
    vm.scp kube-proxy.kubeconfig "${HOSTNAME}" '~/'
    vm.exec "${HOSTNAME}" 'sudo mkdir /var/lib/kube-proxy/'
    vm.exec "${HOSTNAME}" 'sudo mv kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig'
    vm.exec "${HOSTNAME}" 'sudo restorecon -Rv /var/lib/kube-proxy/'
  done
}
```

Create the `kube-proxy-config.yaml` configuration file:

```shell
{
CLUSTER_CIDR="10.0.0.0/24"
FILENAME="kube-proxy-config.yaml"
DEST_PATH="/var/lib/kube-proxy/"

cat <<EOF | tee "${FILENAME}"
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: "/var/lib/kube-proxy/kubeconfig"
mode: "iptables"
clusterCIDR: "${CLUSTER_CIDR}"
EOF


for x in {0..2}; do
NAME="worker${x}"
vm.scp "${FILENAME}" "${NAME}" '~/'
vm.exec "${NAME}" "sudo mkdir -p \"${DEST_PATH}\""
vm.exec "${NAME}" "sudo mv \"${FILENAME}\" \"${DEST_PATH}\""
vm.exec "${NAME}" "sudo restorecon -Rv \"${DEST_PATH}\""
done
}
```

Create the `kube-proxy.service` systemd unit file:

```shell
{
FILENAME="kube-proxy.service"
DEST_PATH="/etc/systemd/system/"

cat <<EOF | tee "${FILENAME}"
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --config=/var/lib/kube-proxy/kube-proxy-config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF


for x in {0..2}; do
HOSTNAME="worker${x}"
vm.scp "${FILENAME}" "${HOSTNAME}" '~/'
vm.exec "${HOSTNAME}" "sudo mkdir -p \"${DEST_PATH}\""
vm.exec "${HOSTNAME}" "sudo mv \"${FILENAME}\" \"${DEST_PATH}\""
vm.exec "${HOSTNAME}" "sudo restorecon -Rv \"${DEST_PATH}\""
done
}
```

### Start the Worker Services

```shell
{
  for x in {0..2}; do
    HOSTNAME="worker${x}"
    vm.exec "${HOSTNAME}" '{
      sudo systemctl daemon-reload
      sudo systemctl enable containerd kubelet kube-proxy
      sudo systemctl start containerd kubelet kube-proxy
    }' &
  done
}
```

> Remember to run the above commands on each worker node: `worker0`, `worker1`, and `worker2`.

## Verification

> The compute instances created in this tutorial will not have permission to complete this section. Run the following commands from the same machine used to create the compute instances.

List the registered Kubernetes nodes:

```shell
vm.exec controller0 'systemctl status  containerd kubelet kube-proxy'
vm.exec controller0 'kubectl get nodes --kubeconfig admin.kubeconfig'
```

> output

```
NAME       STATUS   ROLES    AGE   VERSION
worker-0   Ready    <none>   22s   v1.21.0
worker-1   Ready    <none>   22s   v1.21.0
worker-2   Ready    <none>   22s   v1.21.0
```

Next: [Configuring kubectl for Remote Access](10-configuring-kubectl.md)
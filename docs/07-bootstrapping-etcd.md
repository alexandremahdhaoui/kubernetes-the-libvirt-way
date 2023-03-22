# Bootstrapping the etcd Cluster

Kubernetes components are stateless and store cluster state in [etcd](https://github.com/etcd-io/etcd). In this lab you
will bootstrap a three node etcd cluster and configure it for high availability and secure remote access.

## Prerequisites

The commands in this lab must be run on each controller instance: `controller0`, `controller1`, and `controller2`.
Login to each controller instance using the `vm.ssh` command. Example:

```shell
vm.ssh controller0
```

### Running commands in parallel with tmux

[tmux](https://github.com/tmux/tmux/wiki) can be used to run commands on multiple compute instances at the same time.
See the [Running commands in parallel with tmux](01-prerequisites.md#running-commands-in-parallel-with-tmux) section in
the Prerequisites lab.

## Bootstrapping an etcd Cluster Member

### Download and Install the etcd Binaries

!!! TODO: move the build and install of etcd into a VM

Install prerequisites:
```shell
dnf install -y git golang
```

Build etcd: 
```shell
git clone https://github.com/etcd-io/etcd.git
cd etcd
LATEST_RELEASE=$(git tag | grep --color=none '^v[0-9]*\.[0-9]*\.[0-9]*$' | sort | tail -n 1)
git checkout "$LATEST_RELEASE"
./build.sh
sudo cp bin/* /usr/local/bin/
etcd --version
```

### Configure the etcd Server

```shell
{
  sudo mkdir -p /etc/etcd /var/lib/etcd
  sudo chmod 700 /var/lib/etcd
  sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/
}
```
Each etcd member must have a unique name within an etcd cluster. Set the etcd name to match the hostname of the current
compute instance.

Create the `etcd.service` systemd unit file:

```shell
C0_NAME="controller0"
C1_NAME="controller1"
C2_NAME="controller2"
C0_IP="$(vm.ipv4 controller0)"
C1_IP="$(vm.ipv4 controller1)"
C2_IP="$(vm.ipv4 controller2)"

INITIAL_CLUSTER="${C0_NAME}=https://${C0_IP}:2380,${C1_NAME}=https://${C1_IP}:2380,${C2_NAME}=https://${C2_IP}:2380"
INITIAL_CLUSTER_TOKEN="etcd-cluster-0"

for NAME in "${C0_NAME}" "${C1_NAME}" "${C2_NAME}"; do 
  
IP="$(vm.ipv4 "${NAME}")"
PEER_URLS="https://${IP}:2380"
ADVERTISE_CLIENT_URLS="https://${IP}:2379"
LISTEN_CLIENT_URLS="${ADVERTISE_CLIENT_URLS},https://127.0.0.1:2379"

ETCD_CONFIG="${NAME}.etcd.service"

cat <<EOF | tee ${ETCD_CONFIG}
[Unit]
Description=etcd
Documentation=https://github.com/coreos
[Service]
Type=notify
ExecStart=/usr/local/bin/etcd \\
  --name=${NAME} \\
  --cert-file=/etc/etcd/kubernetes.pem \\
  --key-file=/etc/etcd/kubernetes-key.pem \\
  --peer-cert-file=/etc/etcd/kubernetes.pem \\
  --peer-key-file=/etc/etcd/kubernetes-key.pem \\
  --trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --initial-advertise-peer-urls "${PEER_URLS}" \\
  --listen-peer-urls "${PEER_URLS}" \\
  --listen-client-urls "${LISTEN_CLIENT_URLS}" \\
  --advertise-client-urls "${ADVERTISE_CLIENT_URLS}" \\
  --initial-cluster-token "{INITIAL_CLUSTER_TOKEN}" \\
  --initial-cluster "${INITIAL_CLUSTER}" \\
  --initial-cluster-state new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF

vm.scp ${ETCD_CONFIG} ${NAME} '~/etcd.service'
done
```

In the controller VMs:
```shell
sudo cp ./etcd.service /etc/systemd/system/etcd.service
```

### Start the etcd Server

In the controller VMs:

```shell
{
  sudo update-ca-trust
  sudo systemctl daemon-reload
  sudo systemctl enable etcd
  sudo systemctl start etcd
} &
```

> Remember to run the above commands on each controller node: `controller0`, `controller1`, and `controller2`.

## Verification

List the etcd cluster members:

```shell
sudo ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.pem \
  --cert=/etc/etcd/kubernetes.pem \
  --key=/etc/etcd/kubernetes-key.pem
```

> output

```shell
3a57933972cb5131, started, controller2, https://10.240.0.12:2380, https://10.240.0.12:2379, false
f98dc20bce6225a0, started, controller0, https://10.240.0.10:2380, https://10.240.0.10:2379, false
ffed16798470cab5, started, controller1, https://10.240.0.11:2380, https://10.240.0.11:2379, false
```

Next: [Bootstrapping the Kubernetes Control Plane](08-bootstrapping-kubernetes-controllers.md)
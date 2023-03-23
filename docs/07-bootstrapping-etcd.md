# Bootstrapping the etcd Cluster

Kubernetes components are stateless and store cluster state in [etcd](https://github.com/etcd-io/etcd). In this lab you
will bootstrap a three node etcd cluster and configure it for high availability and secure remote access.

## Download and Install the etcd Binaries

!!! TODO: move all binary build into a builder VM.

Build and install etcd
```shell
{
  dnf install -y git golang
  git clone https://github.com/etcd-io/etcd.git
  cd etcd
  LATEST_RELEASE=$(git tag | grep --color=none "^v[0-9]*\.[0-9]*\.[0-9]*\$" | sort | tail -n 1)
  git checkout "$LATEST_RELEASE"
  ./build.sh
  for x in {0..2}; do
    NAME="controller${x}"
    vm.scp bin/* "${NAME}" '~/'
    vm.exec "${NAME}" 'sudo cp ~/etcd ~/etcdctl ~/etcdutl /usr/local/bin/;etcd --version'
  done
  cd -
  rm -rf ./etcd
}
```

## Configure the etcd Server

```shell
{
  for x in {0..2}; do 
    NAME="controller${x}"
    vm.exec ${NAME} '{
      sudo mkdir -p /etc/etcd /var/lib/etcd
      sudo chmod 700 /var/lib/etcd
      sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/
    }'
  done
}
```
Each etcd member must have a unique name within an etcd cluster. Set the etcd name to match the hostname of the current
compute instance.

Create the `etcd.service` systemd unit file:

```shell
{
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
LISTEN_METRICS_URLS="https://${IP}:2382,https://127.0.0.1:2382"

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
  --listen-metrics-urls "${LISTEN_METRICS_URLS}"\\
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
vm.exec ${NAME} 'sudo mv ~/etcd.service /etc/systemd/system/etcd.service'
vm.exec ${NAME} 'sudo restorecon -Rv /etc/systemd/system/etcd.service'
done
}
```

## Start the etcd Server

```shell
{
  for x in {0..2}; do
    NAME="controller${x}"
    vm.exec ${NAME} '{
      sudo update-ca-trust
      sudo systemctl daemon-reload
      sudo systemctl enable etcd
      sudo systemctl start etcd
    }' &
  done
}
```

## Verification

List the etcd cluster members:

```shell
{
  for x in {0..2}; do
    NAME="controller${x}"
    echo -e "\n--------------------------------\nVerifying ETCD for ${NAME}...\n--------------------------------"
    vm.exec ${NAME} 'sudo ETCDCTL_API=3 etcdctl member list \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/etcd/ca.pem \
    --cert=/etc/etcd/kubernetes.pem \
    --key=/etc/etcd/kubernetes-key.pem'
    echo -e "done\n--------------------------------\n"
  done
}
```

> output

```
--------------------------------
Verifying ETCD for controller0...
--------------------------------
1a8f0fcb350b8243, started, controller1, https://10.0.0.168:2380, https://10.0.0.168:2379, false
840c6724047449f1, started, controller2, https://10.0.0.176:2380, https://10.0.0.176:2379, false
df4d2d8b947878cc, started, controller0, https://10.0.0.99:2380, https://10.0.0.99:2379, false
--------------------------------


--------------------------------
Verifying ETCD for controller1...
--------------------------------
1a8f0fcb350b8243, started, controller1, https://10.0.0.168:2380, https://10.0.0.168:2379, false
840c6724047449f1, started, controller2, https://10.0.0.176:2380, https://10.0.0.176:2379, false
df4d2d8b947878cc, started, controller0, https://10.0.0.99:2380, https://10.0.0.99:2379, false
--------------------------------


--------------------------------
Verifying ETCD for controller2...
--------------------------------
1a8f0fcb350b8243, started, controller1, https://10.0.0.168:2380, https://10.0.0.168:2379, false
840c6724047449f1, started, controller2, https://10.0.0.176:2380, https://10.0.0.176:2379, false
df4d2d8b947878cc, started, controller0, https://10.0.0.99:2380, https://10.0.0.99:2379, false
--------------------------------
```

Next: [Bootstrapping the Kubernetes Control Plane](08-bootstrapping-kubernetes-controllers.md)
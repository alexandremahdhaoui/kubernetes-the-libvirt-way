# Bootstrapping the Kubernetes Control Plane

In this lab you will bootstrap the Kubernetes control plane across three compute instances and configure it for high 
availability. You will also create an external load balancer that exposes the Kubernetes API Servers to remote clients. The following components will be installed on each node: Kubernetes API Server, Scheduler, and Controller Manager.

## Provision the Kubernetes Control Plane

Create the Kubernetes configuration directory:

```shell
{
  for x in {0..2}; do
    NAME="controller${x}"
    vm.exec "${NAME}" 'sudo mkdir -p /etc/kubernetes/config'
  done
}
```

### Build and install Kubernetes Controller Binaries

We will use Kubernetes version `1.26` in its latest patch, therefore we will fetch this information from the official
github repository.
Then we will use go to build and install the binaries.

```shell
{
  LATEST_PATCH=$(git ls-remote https://github.com/kubernetes/kubernetes.git | grep "tags/v1\.26\.[0-9]*$" | sed "s/.*tags\///" | sort | tail -n 1)
  git clone -b "${LATEST_PATCH}" https://github.com/kubernetes/kubernetes.git
  cd kubernetes
  go build ./cmd/kube-apiserver
  go build ./cmd/kube-controller-manager
  go build ./cmd/kube-scheduler
  go build ./cmd/kubectl
  chmod 755 kube-apiserver kube-controller-manager kube-scheduler kubectl
  for x in {0..2}; do
    NAME="controller${x}"
    vm.scp kube-apiserver kube-controller-manager kube-scheduler kubectl "${NAME}" '~/'
    vm.exec "${NAME}" 'sudo mv kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin'
  done
  cd -
}
```

### Configure the Kubernetes API Server

Move the certificates and keys related to the `kube-apiserver` to the previously created  `/var/lib/kubernetes` folder

```shell
{
  for x in {0..2}; do
    NAME="controller${x}"
    vm.exec "${NAME}" '{
      sudo mkdir -p /var/lib/kubernetes/
      sudo mv ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem \
        service-account-key.pem service-account.pem \
        encryption-config.yaml /var/lib/kubernetes/
    }'
  done
}
```

Create the `kube-apiserver.service` systemd unit file:

```shell
{
C0_NAME="controller0"
C1_NAME="controller1"
C2_NAME="controller2"
C0_IP="$(vm.ipv4 controller0)"
C1_IP="$(vm.ipv4 controller1)"
C2_IP="$(vm.ipv4 controller2)"

KUBERNETES_LB_ADDRESS="$(vm.ipv4 "lb-controller")"
IP_RANGE="10.0.0.0/24"
ETCD_SERVERS="https://${C0_IP}:2380,https://${C1_IP}:2380,https://${C2_IP}:2380"

for NAME in "${C0_NAME}" "${C1_NAME}" "${C2_NAME}"; do

IP="$(vm.ipv4 "${NAME}")"
FILENAME="${NAME}.kube-apiserver.service"

cat <<EOF | tee "${FILENAME}"
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --advertise-address="${IP}" \\
  --allow-privileged=true \\
  --apiserver-count=3 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/audit.log \\
  --authorization-mode=Node,RBAC \\
  --bind-address=0.0.0.0 \\
  --client-ca-file=/var/lib/kubernetes/ca.pem \\
  --enable-admission-plugins=NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --etcd-cafile=/var/lib/kubernetes/ca.pem \\
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \\
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \\
  --etcd-servers="${ETCD_SERVERS}" \\
  --event-ttl=1h \\
  --encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \\
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \\
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \\
  --runtime-config='api/all=true' \\
  --service-account-key-file=/var/lib/kubernetes/service-account.pem \\
  --service-account-signing-key-file=/var/lib/kubernetes/service-account-key.pem \\
  --service-account-issuer=https://${KUBERNETES_LB_ADDRESS}:6443 \\
  --service-cluster-ip-range="${IP_RANGE}" \\
  --service-node-port-range=30000-32767 \\
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \\
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

vm.scp ${FILENAME} ${NAME} '~/kube-apiserver.service'
vm.exec ${NAME} 'sudo mv ~/kube-apiserver.service /etc/systemd/system/kube-apiserver.service'
vm.exec ${NAME} 'sudo restorecon -Rv /etc/systemd/system/kube-apiserver.service'
done
}
```

### Configure the Kubernetes Controller Manager

Move the `kube-controller-manager` kubeconfig into place:

```shell
{
  for x in {0..2}; do
    NAME="controller${x}"
    vm.exec "${NAME}" 'sudo mv kube-controller-manager.kubeconfig /var/lib/kubernetes/'
  done
}
```

Create the `kube-controller-manager.service` systemd unit file:

```shell
{
IP_RANGE="10.0.0.0/24"

for x in {0..2}; do

NAME="controller${x}"
IP="$(vm.ipv4 "${NAME}")"
FILENAME="${NAME}.kube-controller-manager.service"

cat <<EOF | tee "${FILENAME}"
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --bind-address=0.0.0.0 \\
  --cluster-cidr="${IP_RANGE} \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \\
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \\
  --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \\
  --leader-elect=true \\
  --root-ca-file=/var/lib/kubernetes/ca.pem \\
  --service-account-private-key-file=/var/lib/kubernetes/service-account-key.pem \\
  --service-cluster-ip-range="${IP_RANGE}" \\
  --use-service-account-credentials=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

vm.scp ${FILENAME} ${NAME} '~/kube-controller-manager.service'
vm.exec ${NAME} 'sudo mv ~/kube-controller-manager.service /etc/systemd/system/kube-controller-manager.service'
vm.exec ${NAME} 'sudo restorecon -Rv /etc/systemd/system/kube-controller-manager.service'
done
}
```

### Configure the Kubernetes Scheduler

Move the `kube-scheduler` kubeconfig into place:

```shell
{
  for x in {0..2}; do
    NAME="controller${x}"
    vm.exec "${NAME}" 'sudo mv kube-scheduler.kubeconfig /var/lib/kubernetes/'
  done
}

```

Create the `kube-scheduler.yaml` configuration file:

```shell
{
FILENAME="kube-scheduler.yaml"
cat <<EOF | tee "${FILENAME}"
apiVersion: kubescheduler.config.k8s.io/v1beta1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: "/var/lib/kubernetes/kube-scheduler.kubeconfig"
leaderElection:
  leaderElect: true
EOF

for x in {0..2}; do
  vm.scp ${FILENAME} ${NAME} '~/'
  vm.exec ${NAME} 'sudo mv ~/kube-scheduler.yaml /etc/kubernetes/config/kube-scheduler.yaml'
  vm.exec ${NAME} 'sudo restorecon -Rv /etc/kubernetes/config/kube-scheduler.yaml'
done
}
```

Create the `kube-scheduler.service` systemd unit file:

```shell
{
FILENAME="kube-scheduler.service"
cat <<EOF | sudo tee "${FILENAME}"
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --config=/etc/kubernetes/config/kube-scheduler.yaml \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

for x in {0..2}; do
  vm.scp ${FILENAME} ${NAME} '~/'
  vm.exec ${NAME} 'sudo mv ~/kube-scheduler.service /etc/systemd/system/kube-scheduler.service'
  vm.exec ${NAME} 'sudo restorecon -Rv /etc/systemd/system/kube-scheduler.service'
done

}
```

### Start the Controller Services

```shell
{
  for x in {0..2}; do
    NAME="controller${x}"
    vm.exec "${NAME}" '{
      sudo systemctl daemon-reload
      sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler
      sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler
    }'
  done
}
```

> Allow up to 10 seconds for the Kubernetes API Server to fully initialize.

### Enable HTTP Health Checks

The `lb-controller` will be used to distribute traffic across the three API servers and allow each API server to
terminate TLS connections and validate client certificates.
The network load balancer only supports HTTP health checks which means the HTTPS endpoint exposed 
by the API server cannot be used. As a workaround the nginx webserver can be used to proxy HTTP health checks. In this 
section nginx will be installed and configured to accept HTTP health checks on port `80` and proxy the connections to 
the API server on `https://127.0.0.1:6443/healthz`.

> The `/healthz` API server endpoint does not require authentication by default.

Install a basic web server to handle HTTP health checks:

```shell
{
  for x in {0..2}; do
    NAME="controller${x}"
    vm.exec "${NAME}" 'sudo dnf install -y nginx'
  done
}
```

```shell
{
cat <<EOF | tee kubernetes.default.svc.cluster.local
server {
  listen      80;
  server_name kubernetes.default.svc.cluster.local;

  location /healthz {
     proxy_pass                    https://127.0.0.1:6443/healthz;
     proxy_ssl_trusted_certificate /var/lib/kubernetes/ca.pem;
  }
}
EOF

for x in {0..2};do
  NAME="controller${x}"
  vm.scp kubernetes.default.svc.cluster.local "${NAME}" "~/"
  vm.exec "${NAME}" '{
  sudo mv kubernetes.default.svc.cluster.local /etc/nginx/sites-available/kubernetes.default.svc.cluster.local
    sudo ln -s /etc/nginx/sites-available/kubernetes.default.svc.cluster.local /etc/nginx/sites-enabled/
  }'
done
}
```

```shell
for x in {0..2};do
  NAME="controller${x}"
  vm.exec "${NAME}" 'sudo systemctl restart nginx;sudo systemctl enable nginx'
done
```

### Verification

```shell
for x in {0..2};do
  NAME="controller${x}"
  vm.exec "${NAME}" 'kubectl cluster-info --kubeconfig admin.kubeconfig'
done
```

```
Kubernetes control plane is running at https://127.0.0.1:6443
```

Test the nginx HTTP health check proxy:

```shell
for x in {0..2};do
  NAME="controller${x}"
  vm.exec "${NAME}" 'curl -H "Host: kubernetes.default.svc.cluster.local" -i http://127.0.0.1/healthz'
done

```

```
HTTP/1.1 200 OK
Server: nginx/1.18.0 (Ubuntu)
Date: Sun, 02 May 2021 04:19:29 GMT
Content-Type: text/plain; charset=utf-8
Content-Length: 2
Connection: keep-alive
Cache-Control: no-cache, private
X-Content-Type-Options: nosniff
X-Kubernetes-Pf-Flowschema-Uid: c43f32eb-e038-457f-9474-571d43e5c325
X-Kubernetes-Pf-Prioritylevel-Uid: 8ba5908f-5569-4330-80fd-c643e7512366

ok
```

> Remember to run the above commands on each controller node: `controller-0`, `controller-1`, and `controller-2`.

## RBAC for Kubelet Authorization

In this section you will configure RBAC permissions to allow the Kubernetes API Server to access the Kubelet API on each worker node. Access to the Kubelet API is required for retrieving metrics, logs, and executing commands in pods.

> This tutorial sets the Kubelet `--authorization-mode` flag to `Webhook`. Webhook mode uses the
[SubjectAccessReview](https://kubernetes.io/docs/admin/authorization/#checking-api-access) API to determine
authorization.

The commands in this section will effect the entire cluster and only need to be run once from one of the controller 
nodes.

Create the `system:kube-apiserver-to-kubelet` [ClusterRole](https://kubernetes.io/docs/admin/authorization/rbac/#role-and-clusterrole)
with permissions to access the Kubelet API and perform most common tasks associated with managing pods:

```shell
{
vm.exec controller0 'cat <<EOF | kubectl apply --kubeconfig admin.kubeconfig -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups:
      - ""
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
    verbs:
      - "*"
EOF'
}
```

The Kubernetes API Server authenticates to the Kubelet as the `kubernetes` user using the client certificate as defined
by the `--kubelet-client-certificate` flag.

Bind the `system:kube-apiserver-to-kubelet` ClusterRole to the `kubernetes` user:

```shell
{
vm.exec controller0 'cat <<EOF | kubectl apply --kubeconfig admin.kubeconfig -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
  namespace: ""
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: kubernetes
EOF'
}
```

## The Kubernetes Frontend Load Balancer

In this section you will provision an external load balancer to front the Kubernetes API Servers. The 
`kubernetes-the-hard-way` static IP address will be attached to the resulting load balancer.

> The compute instances created in this tutorial will not have permission to complete this section. 
**Run the following commands from the same machine used to create the compute instances**.


### Verify the load balancer

Make a HTTP request for the Kubernetes version info:

```shell
KUBERNETES_LB_ADDRESS="$(vm.ipv4 lb-controller)"
curl --cacert ca.pem https://${KUBERNETES_LB_ADDRESS}:6443/version
```

> output

```
{
  "major": "1",
  "minor": "21",
  "gitVersion": "v1.21.0",
  "gitCommit": "cb303e613a121a29364f75cc67d3d580833a7479",
  "gitTreeState": "clean",
  "buildDate": "2021-04-08T16:25:06Z",
  "goVersion": "go1.16.1",
  "compiler": "gc",
  "platform": "linux/amd64"
}
```

Next: [Bootstrapping the Kubernetes Worker Nodes](09-bootstrapping-kubernetes-workers.md)
# Generating Kubernetes Configuration Files for Authentication

In this lab you will generate [Kubernetes configuration files](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/),
also known as kubeconfigs, which enable Kubernetes clients to locate and authenticate to the Kubernetes API Servers.

## Client Authentication Configs

In this section you will generate kubeconfig files for the `controller manager`, `kubelet`, `kube-proxy`, and 
`scheduler` clients and the `admin` user.

### Kubernetes Control Plane load-balancer IP Address

Each kubeconfig requires a Kubernetes API Server to connect to. To support high availability the IP address assigned to
the internal load balancer fronting the Kubernetes API Servers will be used.

Retrieve the control plane load-balancer IP address:

```
LB_CONTROLLER_IP="$(vm.ipv4 "lb-controller")"
```

### The kubelet Kubernetes Configuration File

When generating kubeconfig files for Kubelets the client certificate matching the Kubelet's node name must be used. This
will ensure Kubelets are properly authorized by the Kubernetes [Node Authorizer](https://kubernetes.io/docs/admin/authorization/node/).

> The following commands must be run in the same directory used to generate the SSL certificates during the 
> [Generating TLS Certificates](04-certificate-authority.md) lab.

Generate a kubeconfig file for each worker node:

```shell
{
  LB_CONTROLLER_IP="$(vm.ipv4 "lb-controller")"
  LB_CONTROLLER_HOST="https://${LB_CONTROLLER_IP}:6443"
  CONTROLLER_0_HOST="https://$(vm.ipv4 "controller0"):6443"
  CONTROLLER_1_HOST="https://$(vm.ipv4 "controller1"):6443"
  CONTROLLER_2_HOST="https://$(vm.ipv4 "controller2"):6443"
  SERVER="${LB_CONTROLLER_HOST}" # TODO: fix the LB_CONTROLLER_HOST integration
  CLUSTER_NAME="k0"
  for x in {0..2}; do
    HOSTNAME="worker${x}"
    kubectl config set-cluster "${CLUSTER_NAME}" \
      --certificate-authority=ca.pem \
      --embed-certs=true \
      --server="${SERVER}" \
      --kubeconfig=${HOSTNAME}.kubeconfig
  
    kubectl config set-credentials system:node:${HOSTNAME} \
      --client-certificate=${HOSTNAME}.pem \
      --client-key=${HOSTNAME}-key.pem \
      --embed-certs=true \
      --kubeconfig=${HOSTNAME}.kubeconfig
  
    kubectl config set-context default \
      --cluster="${CLUSTER_NAME}" \
      --user=system:node:${HOSTNAME} \
      --kubeconfig=${HOSTNAME}.kubeconfig
  
    kubectl config use-context default --kubeconfig=${HOSTNAME}.kubeconfig
  done
}
```

Results:

```
worker0.kubeconfig
worker1.kubeconfig
worker2.kubeconfig
```

### The kube-proxy Kubernetes Configuration File

Generate a kubeconfig file for the `kube-proxy` service:

```shell
{
  LB_CONTROLLER_IP="$(vm.ipv4 "lb-controller")"
  LB_CONTROLLER_HOST="https://${LB_CONTROLLER_IP}:6443"
  SERVER="${LB_CONTROLLER_HOST}" # TODO: fix the LB_CONTROLLER_HOST integration
  CLUSTER_NAME="k0"
  kubectl config set-cluster "${CLUSTER_NAME}" \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server="${SERVER}" \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-credentials system:kube-proxy \
    --client-certificate=kube-proxy.pem \
    --client-key=kube-proxy-key.pem \
    --embed-certs=true \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-context default \
    --cluster=k0 \
    --user=system:kube-proxy \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig
}
```

Results:

```
kube-proxy.kubeconfig
```

### The kube-controller-manager Kubernetes Configuration File

Generate a kubeconfig file for the `kube-controller-manager` service:

```shell
{
  CLUSTER_NAME="k0"
  kubectl config set-cluster "${CLUSTER_NAME}" \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config set-credentials system:kube-controller-manager \
    --client-certificate=kube-controller-manager.pem \
    --client-key=kube-controller-manager-key.pem \
    --embed-certs=true \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config set-context default \
    --cluster="${CLUSTER_NAME}" \
    --user=system:kube-controller-manager \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config use-context default --kubeconfig=kube-controller-manager.kubeconfig
}
```

Results:

```
kube-controller-manager.kubeconfig
```


### The kube-scheduler Kubernetes Configuration File

Generate a kubeconfig file for the `kube-scheduler` service:

```shell
{
  CLUSTER_NAME="k0"
  kubectl config set-cluster "${CLUSTER_NAME}" \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config set-credentials system:kube-scheduler \
    --client-certificate=kube-scheduler.pem \
    --client-key=kube-scheduler-key.pem \
    --embed-certs=true \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config set-context default \
    --cluster="${CLUSTER_NAME}" \
    --user=system:kube-scheduler \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config use-context default --kubeconfig=kube-scheduler.kubeconfig
}
```

Results:

```
kube-scheduler.kubeconfig
```

### The admin Kubernetes Configuration File

Generate a kubeconfig file for the `admin` user:

```shell
{
  CLUSTER_NAME="k0"
  kubectl config set-cluster "${CLUSTER_NAME}" \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=admin.kubeconfig

  kubectl config set-credentials admin \
    --client-certificate=admin.pem \
    --client-key=admin-key.pem \
    --embed-certs=true \
    --kubeconfig=admin.kubeconfig

  kubectl config set-context default \
    --cluster="${CLUSTER_NAME}" \
    --user=admin \
    --kubeconfig=admin.kubeconfig

  kubectl config use-context default --kubeconfig=admin.kubeconfig
}
```

Results:

```
admin.kubeconfig
```

## Distribute the Kubernetes Configuration Files

Copy the appropriate `kubelet` and `kube-proxy` kubeconfig files to each worker instance:

```shell
{
  for x in {0..2}; do
    HOSTNAME="worker${x}"
    vm.scp "${HOSTNAME}.kubeconfig" kube-proxy.kubeconfig "${HOSTNAME}" '~/'
  done 
}
```

Copy the appropriate `kube-controller-manager` and `kube-scheduler` kubeconfig files to each controller instance:

```shell
{
  for x in {0..2}; do
    HOSTNAME="controller${x}"
    vm.scp admin.kubeconfig kube-controller-manager.kubeconfig kube-scheduler.kubeconfig ${HOSTNAME} '~/'
  done
}
```

Next: [Generating the Data Encryption Config and Key](06-data-encryption-keys.md)
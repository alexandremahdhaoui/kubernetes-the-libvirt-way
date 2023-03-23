# Configuring kubectl for Remote Access

In this lab you will generate a kubeconfig file for the `kubectl` command line utility based on the `admin` user credentials.

> Run the commands in this lab from the same directory used to generate the admin client certificates.

## The Admin Kubernetes Configuration File

Each kubeconfig requires a Kubernetes API Server to connect to. To support high availability the IP address assigned to the external load balancer fronting the Kubernetes API Servers will be used.

Generate a kubeconfig file suitable for authenticating as the `admin` user:

```shell
{
  CLUSTER_NAME="k0"
  ENDPOINT="https://$(vm.ipv4 controller0):6443" # TODO: Fix Load-balancer setup
  kubectl config set-cluster "${CLUSTER_NAME}" \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server="${ENDPOINT}"

  kubectl config set-credentials admin \
    --client-certificate=admin.pem \
    --client-key=admin-key.pem

  kubectl config set-context "${CLUSTER_NAME}" \
    --cluster="${CLUSTER_NAME}" \
    --user=admin

  kubectl config use-context "${CLUSTER_NAME}"
}
```

## Verification

Check the version of the remote Kubernetes cluster:

```
kubectl version -o json
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
  "kustomizeVersion": "v4.5.7",
  "serverVersion": {
    "major": "1",
    "minor": "26",
    "gitVersion": "v1.26.3",
    "gitCommit": "9e644106593f3f4aa98f8a84b23db5fa378900bd",
    "gitTreeState": "clean",
    "buildDate": "2023-03-23T18:04:20Z",
    "goVersion": "go1.19.7",
    "compiler": "gc",
    "platform": "linux/amd64"
  }
}
```

List the nodes in the remote Kubernetes cluster:

```
kubectl get nodes
```

> output

```
NAME      STATUS   ROLES    AGE    VERSION
worker0   Ready    <none>   25m   v1.26.3
worker1   Ready    <none>   23m   v1.26.3
worker2   Ready    <none>   23m   v1.26.3
```

Next: [Provisioning Pod Network Routes](11-pod-network-routes.md)
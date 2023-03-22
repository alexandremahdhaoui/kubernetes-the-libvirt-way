# Provisioning a CA and Generating TLS Certificates

In this lab you will provision a [PKI Infrastructure](https://en.wikipedia.org/wiki/Public_key_infrastructure) 
using CloudFlare's PKI toolkit, [cfssl](https://github.com/cloudflare/cfssl), then use it to bootstrap a Certificate 
Authority, and generate TLS certificates for the following components: etcd, kube-apiserver, kube-controller-manager, 
kube-scheduler, kubelet, and kube-proxy.

Install `cfssl` and `cfssljson` using:
```shell
go install github.com/cloudflare/cfssl/cmd/cfssl@latest
go install github.com/cloudflare/cfssl/cmd/cfssljson@latest
```

## Certificate Authority

In this section you will provision a Certificate Authority that can be used to generate additional TLS certificates.

Generate the CA configuration file, certificate, and private key:

```shell
{
cat > ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}
EOF

cat > ca-csr.json <<EOF
{
  "CN": "Kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "Kubernetes",
      "OU": "CA",
      "ST": "Oregon"
    }
  ]
}
EOF

cfssl gencert -initca ca-csr.json | cfssljson -bare ca
}
```

Results:

```shell
ca-key.pem
ca.pem
```

## Client and Server Certificates

In this section you will generate client and server certificates for each Kubernetes component and a client certificate 
for the Kubernetes `admin` user.

### The Admin Client Certificate

Generate the `admin` client certificate and private key:

```shell
{

cat > admin-csr.json <<EOF
{
  "CN": "admin",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:masters",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  admin-csr.json | cfssljson -bare admin

}
```

Results:

```shell
admin-key.pem
admin.pem
```

### The Kubelet Client Certificates

Kubernetes uses a [special-purpose authorization mode](https://kubernetes.io/docs/admin/authorization/node/) called Node
Authorizer, that specifically authorizes API requests made by [Kubelets](https://kubernetes.io/docs/concepts/overview/components/#kubelet).
In order to be authorized by the Node Authorizer, Kubelets must use a credential that identifies them as being in the 
`system:nodes` group, with a username of `system:node:<nodeName>`. In this section you will create a certificate for 
each Kubernetes worker node that meets the Node Authorizer requirements.

Generate a certificate and private key for each Kubernetes worker node:

```shell
for x in {0..2}; do
HOSTNAME="worker${x}"
EXTERNAL_IP="$(vm.ipv4 "lb-worker")"
INTERNAL_IP="$(vm.ipv4 ${HOSTNAME})"

cat > "${HOSTNAME}-csr.json" <<EOF
{
  "CN": "system:node:${HOSTNAME}",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:nodes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname="${HOSTNAME},${EXTERNAL_IP},${INTERNAL_IP}" \
  -profile=kubernetes \
  "${HOSTNAME}-csr.json" | cfssljson -bare "${HOSTNAME}"
done
```

Results:

```shell
worker0-key.pem
worker0.pem
worker1-key.pem
worker1.pem
worker2-key.pem
worker2.pem
```

### The Controller Manager Client Certificate

Generate the `kube-controller-manager` client certificate and private key:

```shell
{

cat > kube-controller-manager-csr.json <<EOF
{
  "CN": "system:kube-controller-manager",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:kube-controller-manager",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kube-controller-manager-csr.json | cfssljson -bare kube-controller-manager

}
```

Results:

```shell
kube-controller-manager-key.pem
kube-controller-manager.pem
```


### The Kube Proxy Client Certificate

Generate the `kube-proxy` client certificate and private key:

```shell
{

cat > kube-proxy-csr.json <<EOF
{
  "CN": "system:kube-proxy",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:node-proxier",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kube-proxy-csr.json | cfssljson -bare kube-proxy

}
```

Results:

```
kube-proxy-key.pem
kube-proxy.pem
```

### The Scheduler Client Certificate

Generate the `kube-scheduler` client certificate and private key:

```shell
{

cat > kube-scheduler-csr.json <<EOF
{
  "CN": "system:kube-scheduler",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:kube-scheduler",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kube-scheduler-csr.json | cfssljson -bare kube-scheduler

}
```

Results:

```shell
kube-scheduler-key.pem
kube-scheduler.pem
```


### The Kubernetes API Server Certificate

The `kubernetes-the-hard-way` static IP address will be included in the list of subject alternative names for the 
Kubernetes API Server certificate. This will ensure the certificate can be validated by remote clients.

Generate the Kubernetes API Server certificate and private key:

```shell
{

KUBERNETES_PUBLIC_ADDRESS="$(vm.ipv4 "lb-controller")"
KUBERNETES_HOSTNAMES="kubernetes,kubernetes.default,kubernetes.default.svc,kubernetes.default.svc.cluster,kubernetes.svc.cluster.local"
IP_0="$(vm.ipv4 "controller0")"
IP_1="$(vm.ipv4 "controller1")"
IP_2="$(vm.ipv4 "controller2")"

cat > kubernetes-csr.json <<EOF
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "Kubernetes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname="${IP_0},${IP_1},${IP_2},${KUBERNETES_PUBLIC_ADDRESS},127.0.0.1,${KUBERNETES_HOSTNAMES} " \
  -profile=kubernetes \
  kubernetes-csr.json | cfssljson -bare kubernetes

}
```

> The Kubernetes API server is automatically assigned the `kubernetes` internal dns name, which will be linked to the first IP address (`10.32.0.1`) from the address range (`10.32.0.0/24`) reserved for internal cluster services during the [control plane bootstrapping](08-bootstrapping-kubernetes-controllers.md#configure-the-kubernetes-api-server) lab.

Results:

```shell
kubernetes-key.pem
kubernetes.pem
```

## The Service Account Key Pair

The Kubernetes Controller Manager leverages a key pair to generate and sign service account tokens as described in the [managing service accounts](https://kubernetes.io/docs/admin/service-accounts-admin/) documentation.

Generate the `service-account` certificate and private key:

```shell
{

cat > service-account-csr.json <<EOF
{
  "CN": "service-accounts",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "Kubernetes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  service-account-csr.json | cfssljson -bare service-account

}
```

Results:

```shell
service-account-key.pem
service-account.pem
```


## Distribute the Client and Server Certificates

Copy the appropriate certificates and private keys to each worker instance:

```shell
for x in {0..2}; do
  HOSTNAME="worker${x}"
  vm.scp ca.pem "${HOSTNAME}-key.pem" "${HOSTNAME}.pem" "${HOSTNAME}" '~/'
done
```

Copy the appropriate certificates and private keys to each controller instance:

```shell
for x in {0..2}; do
  HOSTNAME="controller${x}"
  vm.scp ca.pem ca-key.pem\
    kubernetes-key.pem kubernetes.pem\
    service-account-key.pem service-account.pem\
    "${HOSTNAME}" '~/'
done
```

> The `kube-proxy`, `kube-controller-manager`, `kube-scheduler`, and `kubelet` client certificates will be used to 
generate client authentication configuration files in the next lab.

Next: [Generating Kubernetes Configuration Files for Authentication](05-kubernetes-configuration-files.md)
# Kubernetes the Libvirt way

This tutorial walks you through setting up Kubernetes the hard way but using Libvirt on your bare metal machine.
This guide is not for people looking for a fully automated command to bring up a Kubernetes cluster.
If that's you then check out the
[Getting Started Guides](https://kubernetes.io/docs/setup).

Kubernetes The Libvirt Way is optimized for learning, which means taking the long route to ensure you understand each task
required to bootstrap a Kubernetes cluster.

> The results of this tutorial should not be viewed as production ready, and may receive limited support from the 
community, but don't let that stop you from learning!

## Important information

This tutorial will only cover creating a Kubernetes cluster on 1 single bare metal server. The setup using a cluster of
3 or more bare metal server is not covered here, but I plan to cover it in a next tutorial.

Indeed, creating a VM orchestration cluster using KVM/Libvirt requires more than a few bash functions.

For learning purposes, most of the binaries used in this tutorial will be built from source.

## Target Audience

The target audience for this tutorial is someone planning to support a production Kubernetes cluster and wants to 
understand how everything fits together.

## Cluster Details

Kubernetes The Hard Way guides you through bootstrapping a highly available Kubernetes cluster with end-to-end 
encryption between components and RBAC authentication.

* [kubernetes](https://github.com/kubernetes/kubernetes) v1.26.0
* [containerd](https://github.com/containerd/containerd) v1.4.4
* [coredns](https://github.com/coredns/coredns) v1.8.3
* [cni](https://github.com/containernetworking/cni) v0.9.1
* [etcd](https://github.com/etcd-io/etcd) v3.5.7

## Labs

This tutorial assumes you have access to a bare metal machine. While a bare metal machine is used for basic 
infrastructure requirements the lessons learned in this tutorial can be applied to other platforms.

* [Prerequisites](docs/01-prerequisites.md)
* [Installing the Client Tools](docs/02-client-tools.md)
* [Provisioning Compute Resources](docs/03-compute-resources.md)
* [Provisioning the CA and Generating TLS Certificates](docs/04-certificate-authority.md)
* [Generating Kubernetes Configuration Files for Authentication](docs/05-kubernetes-configuration-files.md)
* [Generating the Data Encryption Config and Key](docs/06-data-encryption-keys.md)
* [Bootstrapping the etcd Cluster](docs/07-bootstrapping-etcd.md)
* [Bootstrapping the Kubernetes Control Plane](docs/08-bootstrapping-kubernetes-controllers.md)
* [Bootstrapping the Kubernetes Worker Nodes](docs/09-bootstrapping-kubernetes-workers.md)
* [Configuring kubectl for Remote Access](docs/10-configuring-kubectl.md)
* [Provisioning Pod Network Routes](docs/11-pod-network-routes.md)
* [Deploying the DNS Cluster Add-on](docs/12-dns-addon.md)
* [Smoke Test](docs/13-smoke-test.md)
* [Cleaning Up](docs/14-cleanup.md)



# Provisioning Compute Resources

Kubernetes requires a set of machines to host the Kubernetes control plane and the worker nodes where containers are 
ultimately run. In this lab you will provision the compute resources required for running a secure and highly available
Kubernetes cluster across a single [compute zone](https://cloud.google.com/compute/docs/regions-zones/regions-zones).

> Ensure a default compute zone and region have been set as described in the 
[Prerequisites](01-prerequisites.md#set-a-default-compute-region-and-zone) lab.

## Networking

The Kubernetes [networking model](https://kubernetes.io/docs/concepts/cluster-administration/networking/#kubernetes-model)
assumes a flat network in which containers and nodes can communicate with each other. In cases where this is not desired
[network policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/) can limit how groups of 
containers are allowed to communicate with each other and external network endpoints.

> Setting up network policies is out of scope for this tutorial.

## Compute Instances

The compute instances in this lab will be provisioned using Fedora Cloud 37. Each compute instance will be provisioned 
with a fixed private IP address to simplify the Kubernetes bootstrapping process.

> The Kubernetes cluster CIDR range is defined by the Controller Manager's `--cluster-cidr` flag. In this tutorial the 
cluster CIDR range will be set to `10.200.0.0/16`, which supports 254 subnets.

Create three compute instances which will host the Kubernetes worker nodes:

If you need to clean up your server during the tutorial
```shell
{
  for x in $(ls); do if [ "${x}" == "anaconda-ks.cfg" ]; then
    echo keeping artifact "${x}"; else rm -f "${x}";fi;
  done
}
```

## Provision your VMs

```shell
for x in controller worker; do for y in {0..2}; do vm.new "${x}${y}" fedora37;done;done
```

If you need to delete all machines please run:
```shell
{
  for x in $(vm.list | jq -r .[].name);do vm.rm $x;done
  rm -f ~/.ssh/known_hosts
}
```

### Verification

List the compute instances in your default compute zone:

```shell
vm.list
```

> output

```
NAME          ZONE        MACHINE_TYPE   PREEMPTIBLE  INTERNAL_IP  EXTERNAL_IP    STATUS
controller-0  us-west1-c  e2-standard-2               10.240.0.10  XX.XX.XX.XXX   RUNNING
controller-1  us-west1-c  e2-standard-2               10.240.0.11  XX.XXX.XXX.XX  RUNNING
controller-2  us-west1-c  e2-standard-2               10.240.0.12  XX.XXX.XX.XXX  RUNNING
worker-0      us-west1-c  e2-standard-2               10.240.0.20  XX.XX.XXX.XXX  RUNNING
worker-1      us-west1-c  e2-standard-2               10.240.0.21  XX.XX.XX.XXX   RUNNING
worker-2      us-west1-c  e2-standard-2               10.240.0.22  XX.XXX.XX.XX   RUNNING
```

If you want to verify your VMs were started successfully
```shell
{
  for x in controller worker; do for y in {0..2}; do
    vm.exec "${x}${y}" 'echo "$(hostname)" started successfully'
  done;done
}
```

## Configuring SSH Access

SSH will be used to configure the controller and worker instances. When connecting to compute instances for the first 
time SSH keys will be generated for you and stored in the project or instance metadata as described in the 
[connecting to instances](https://cloud.google.com/compute/docs/instances/connecting-to-instance) documentation.

Test SSH access to the `controller0` compute instances:

```shell
vm.ssh controller0
```

Type `exit` at the prompt to exit the `controller0` compute instance:

```
$USER@controller-0:~$ exit
```
> output

```
logout
Connection to XX.XX.XX.XXX closed
```

## Provision the load-balancers

Create the load-balancer
```shell
vm.new lb-controller fedora37
vm.new lb-worker fedora37
```

Generate the nginx configuration
```shell
{
generate_lb_nginx_conf() {
NAME_PREFIX="${1}"
PORT="${2}"
ADDR_0="$(vm.id "${NAME_PREFIX}0"):${PORT}"
ADDR_1="$(vm.id "${NAME_PREFIX}1"):${PORT}"
ADDR_2="$(vm.id "${NAME_PREFIX}2"):${PORT}"
FILEPATH="lb-${NAME_PREFIX}.nginx.conf"

cat <<EOF > "${FILEPATH}"
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log notice;
pid /run/nginx.pid;
# Load dynamic modules. See /usr/share/doc/nginx/README.dynamic.
include /usr/share/nginx/modules/*.conf;
events {
    worker_connections 1024;
}
# https://docs.nginx.com/nginx/admin-guide/load-balancer/http-load-balancer/
http {
  upstream backend {
    server ${ADDR_0};
    server ${ADDR_1};
    server ${ADDR_2};
  }
  server {
    location / {
      proxy_pass http://backend;
    }
  }
}
EOF
}

generate_lb_nginx_conf worker 6443
generate_lb_nginx_conf controller 6443

done
}
```

Distribute the configurations to the load balancer
```shell
{
  for x in worker controller; do
    NAME="lb-${x}"
    vm.scp "${NAME}.nginx.conf" "${NAME}" '~/nginx.conf'
    vm.exec "${NAME}" '{
      sudo mv ~/nginx.conf /etc/nginx/nginx.conf
      sudo dnf install nginx
      sudo systemctl enable --now nginx
    }'
  done
}
```



Next: [Provisioning a CA and Generating TLS Certificates](04-certificate-authority.md)
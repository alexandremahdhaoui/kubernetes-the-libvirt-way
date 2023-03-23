# Provisioning Compute Resources

Kubernetes requires a set of machines to host the Kubernetes control plane and the worker nodes where containers are 
ultimately run. In this lab you will provision the compute resources required for running a secure and highly available
Kubernetes cluster across a single [compute zone](https://cloud.google.com/compute/docs/regions-zones/regions-zones).

> Ensure a default compute zone and region have been set as described in the 
[Prerequisites](01-prerequisites.md#set-a-default-compute-region-and-zone) lab.

## Cleanup resources

Run the following command to clean up your server and start the tutorial again
```shell
{
  for x in $(ls); do if [ "${x}" == "anaconda-ks.cfg" ] || [ "${x}" == "encryption-key" ]; then
    echo keeping artifact "${x}"; else rm -rf "${x}";fi;
  done
  for x in $(vm.list | jq -r .[].name);do vm.rm $x;done
  rm -f ~/.ssh/known_hosts
}
```

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
cluster CIDR range will be set to `10.0.0.0/24`.


## Important information: monitor progress of VM provisioning

Because we will be provisioning 8 VMs in this chapter and IO or CPU might be blocking, you can monitor the progress of 
the cloud-init scripts by running the command bellow
```shell
vm.exec lb-worker 'sudo tail -f /var/log/cloud-init-output.log'
```

In my case, we can observe a relatively high IO wait
```
[root@n0 ~]# sar 5 55
Linux 6.1.18-200.fc37.x86_64 (n0.mahdhaoui.com)         03/22/2023      _x86_64_        (16 CPU)

06:23:51 PM     CPU     %user     %nice   %system   %iowait    %steal     %idle
06:23:56 PM     all      0.55      0.00      0.50     27.37      0.00     71.56
[...]
```

More precisely, the bottleneck was block io
```
[root@n0 ~]# sar 2 222 -d
Linux 6.1.18-200.fc37.x86_64 (n0.mahdhaoui.com)         03/22/2023      _x86_64_        (16 CPU)

06:24:52 PM       DEV       tps     rkB/s     wkB/s     dkB/s   areq-sz    aqu-sz     await     %util
06:24:54 PM       sda     24.50      0.00      0.00      0.00      0.00      0.00      0.10      2.20
06:24:54 PM       sdb      4.50      0.00     16.75      0.00      3.72      0.00      0.44      0.20
06:24:54 PM       sdc    196.00    652.00  11760.00      0.00     63.33      9.37     42.77    101.75
[...]
```

## Provision your VMs

```shell
for x in controller worker; do for y in {0..2}; do vm.new "${x}${y}" fedora37;done;done
```

Please wait your VMs are fully provisioned before continuing. To monitor the progress of VM provisioning, please refer
to [the previous section](#important-information-monitor-progress-of-vm-provisioning).


### Fix hostname and verify the VM were started successfully

```shell
{
  for x in controller worker; do for y in {0..2}; do
    HOSTNAME="${x}${y}"
    vm.exec "${HOSTNAME}" "sudo hostnamectl set-hostname --static \"${HOSTNAME}\"" 
    vm.exec "${HOSTNAME}" 'echo "$(hostname)" started successfully'
  done;done
}
```

### Verification

List the compute instances in your default compute zone:

```shell
vm.list
```

> output

```json
[
  {
    "id": "1",
    "name": "controller0",
    "ipv4": "10.0.0.194",
    "status": "running"
  },
  {
    "id": "2",
    "name": "controller1",
    "ipv4": "10.0.0.35",
    "status": "running"
  },
  {
    "id": "3",
    "name": "controller2",
    "ipv4": "10.0.0.75",
    "status": "running"
  },
  {
    "id": "4",
    "name": "worker0",
    "ipv4": "10.0.0.82",
    "status": "running"
  },
  {
    "id": "5",
    "name": "worker1",
    "ipv4": "10.0.0.76",
    "status": "running"
  },
  {
    "id": "6",
    "name": "worker2",
    "ipv4": "10.0.0.166",
    "status": "running"
  }
]
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
$USER@controller0:~$ exit
```
> output

```
logout
Connection to XX.XX.XX.XXX closed
```

## Provision the load-balancers

Create the load-balancer
```shell
{
  vm.new lb-controller fedora37
  vm.new lb-worker fedora37
}
```

Fix the hostname before continuing

```shell
{
  for x in controller worker; do 
    HOSTNAME="lb-${x}"
    vm.exec "${HOSTNAME}" "sudo hostnamectl set-hostname --static \"${HOSTNAME}\"" 
  done
}
```

Generate the nginx configuration
```shell
{
  generate_lb_nginx_conf worker 30000 ""
  generate_lb_nginx_conf controller 6443 "health_check port=80,uri=/healthz;"
}
```

Once the execution is done, you can proceed

Distribute the configurations to the load balancer
```shell
{
  for x in worker controller; do
    NAME="lb-${x}"
    vm.scp "${NAME}.nginx.conf" "${NAME}" '~/nginx.conf'
    vm.exec "${NAME}" '{
      sudo dnf install -y nginx
      sudo mv ~/nginx.conf /etc/nginx/nginx.conf
      sudo chmod 644 /etc/nginx/nginx.conf
      sudo restorecon -Rv /etc/nginx/nginx.conf
      sudo systemctl enable --now nginx
    }'
  done
}
```

Verify Nginx is running
```shell
{
  vm.exec lb-worker 'systemctl status nginx'
  vm.exec lb-controller 'systemctl status nginx'
}
```

If you need to troubleshoot nginx 
```shell
vm.exec lb-worker 'sudo journalctl -xeu nginx.service'
```


Next: [Provisioning a CA and Generating TLS Certificates](04-certificate-authority.md)
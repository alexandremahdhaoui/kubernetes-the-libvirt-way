# Cleaning Up

In this lab you will delete the compute resources created during this tutorial.

## Compute Instances

Delete the controller and worker compute instances:

```shell
{
  for x in $(ls); do if [ "${x}" == "anaconda-ks.cfg" ] || [ "${x}" == "encryption-key" ]; then
    echo keeping artifact "${x}"; else rm -rf "${x}";fi;
  done
  for x in $(vm.list | jq -r .[].name);do vm.rm $x;done
  rm -f ~/.ssh/known_hosts
}
```

## Network resources

```shell
{
  for x in $(virsh net-list | awk 'NR > 2 {print $1}'); do
    virsh net-destroy $x
  done
}
```
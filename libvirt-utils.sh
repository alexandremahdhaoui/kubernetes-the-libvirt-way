make_user_data() {
cat <<EOF > user-data
#cloud-config
users:
  - name: default
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    shell: /bin/bash
    groups: ["wheel", "sudo"]
    ssh_authorized_keys:
      - $AUTHORIZED_KEY

packages:
  - qemu-guest-agent

package_update: true
package_upgrade: true

bootcmd:
  - systemctl enable --now qemu-guest-agent

runcmd:
  - restorecon -R ~/.ssh
EOF
}

vm.new() {
  VM_NAME="$1"
  IMAGE_NAME="$2.qcow2"
  OS_VARIANT=$2
  NET_BRIDGE=virbr2

  /usr/bin/cp -f "/templates/${IMAGE_NAME}" "/images/${VM_NAME}.qcow2"

  virt-install --name "${VM_NAME}"\
    --ram 4096 --vcpus 2\
    --disk /images/"${VM_NAME}.qcow2"\
    --os-variant "${OS_VARIANT}" --graphics none\
    --console none --noautoconsole\
    --network bridge="${NET_BRIDGE}"\
    --cloud-init user-data=user-data
}

vm.ipv4() {
  VM_NAME="$1"
  IPV4=$(virsh qemu-agent-command "${VM_NAME}"\
    '{"execute":"guest-network-get-interfaces"}'|\
    jq '.return[]."ip-addresses"'| \
    jq -rs 'flatten | .[] | select(."ip-address-type" == "ipv4")| select(."ip-address" != "127.0.0.1") | ."ip-address"')
  if [ -z "${IPV4}" ]; then echo "undefined"; else echo "${IPV4}";fi
}

vm.rm() {
  VM_NAME="$1"
  virsh destroy "${VM_NAME}"
  virsh undefine "${VM_NAME}"
  rm -f /images/"${VM_NAME}.qcow2"
}

vm.id() {
  VM_NAME="$1"
  ID=$(virsh list --all | grep --color=none "${VM_NAME}" | awk '{print $1}')
  if [ -z "${ID}" ]; then echo "undefined";else echo "${ID}";fi
}

vm.status() {
  VM_NAME="$1"
  STATUS=$(virsh list --all | grep --color=none "${VM_NAME}" | awk '{print $3}')
  if [ -z "${STATUS}" ]; then echo "undefined"; else echo "${STATUS}"; fi
}

vm.describe() {
  VM_NAME="$1"
  id="$(vm.id "${VM_NAME}")"
  ipv4="$(vm.ipv4 "${VM_NAME}")"
  status=$(vm.status "${VM_NAME}")
  jq --null-input \
    --arg id "$id" \
    --arg name "${VM_NAME}" \
    --arg ipv4 "$ipv4" \
    --arg status "$status"\
    '{"id": $id, "name": $name, "ipv4": $ipv4, "status": $status}'
}

vm.list() {
  # get running vm names
  VM_NAME=$(virsh list | grep --color=none running | awk '{print $2}')
  BUFFER=""
  for x in $VM_NAME; do
    BUFFER+="$(vm.describe "$x")"
  done
  echo "$BUFFER" | jq -s
}
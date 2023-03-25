generate_lb_nginx_conf() {
NAME_PREFIX="${1}"
PORT="${2}"
HEALTH_CHECK="${3}"

ADDR_0="$(vm.ipv4 "${NAME_PREFIX}0"):${PORT}"
ADDR_1="$(vm.ipv4 "${NAME_PREFIX}1"):${PORT}"
ADDR_2="$(vm.ipv4 "${NAME_PREFIX}2"):${PORT}"
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
      # proxy_set_header Host kubernetes.default.svc.cluster.local
      ${HEALTH_CHECK}
    }
  }
}
EOF
}

vm.new() {
  if [ -z "${1}" ];then echo "a hostname should be provided";return 1;fi
  if [ -z "${2}" ];then echo "an image name should be provided";return 1;fi

  HOSTNAME="${1}"
  IMAGE_NAME="${2}.qcow2"
  OS_VARIANT="${2}"
  NET_BRIDGE="virbr2"
  BASE_PATH="/virt"
  METADATA="${BASE_PATH}/cloud-init/${HOSTNAME}-metadata"
  USERDATA="${BASE_PATH}/cloud-init/${HOSTNAME}-userdata"

  for host in $(vm.list | jq '.[].name'); do
    if [ "${HOSTNAME}" == "${host}" ]; then
      echo "Hostname should be unique, ${HOSTNAME} is already set."
      echo "Exiting..."
      return 1
    fi
  done

  /usr/bin/cp -f "${BASE_PATH}/templates/${IMAGE_NAME}" "${BASE_PATH}/images/${HOSTNAME}.qcow2"
  vm.cloud_init "${HOSTNAME}"

  virt-install --name "${HOSTNAME}"\
    --ram 4096 --vcpus 2\
    --disk /virt/images/"${HOSTNAME}.qcow2"\
    --os-variant "${OS_VARIANT}" --graphics none\
    --console none --noautoconsole\
    --network bridge="${NET_BRIDGE}"\
    --cloud-init meta-data="${METADATA}",user-data="${USERDATA}"
}

vm.cloud_init() {
HOSTNAME="$1"
_key_filepath="$(find ~ -name "id*.pub" |head -n 1)"
AUTHORIZED_KEY="$(cat "${_key_filepath}")"
UUID="$(uuidgen)"
DEST_PATH="/virt/cloud-init"

cat <<EOF > "${DEST_PATH}/${HOSTNAME}-userdata"
#cloud-config
users:
  - name: clouduser
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    shell: /bin/bash
    groups: ["wheel", "sudo"]
    ssh_authorized_keys:
      - ${AUTHORIZED_KEY}
timezone: "Europe/Berlin"
packages:
  - qemu-guest-agent
package_update: true
package_upgrade: true
bootcmd:
  - systemctl mask "systemd-zram-setup@zram0.service"
  - swapoff -a
  - systemctl enable --now qemu-guest-agent
runcmd:
  - restorecon -R ~/.ssh
EOF

cat <<EOF > "${DEST_PATH}/${HOSTNAME}-metadata"
hostname: "${HOSTNAME}"
instance-id: "${UUID}"
EOF
# cloud-localds -m local "${DEST_PATH}/${HOSTNAME}.img" "${DEST_PATH}/${HOSTNAME}-userdata" "${DEST_PATH}/${HOSTNAME}-metadata"
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
  rm -f /virt/images/"${VM_NAME}.qcow2"
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
  VM_NAME=$(virsh list --all | awk 'NR > 2' | awk '{print $2}')
  BUFFER=""
  for x in $VM_NAME; do
    BUFFER+="$(vm.describe "$x")"
  done
  echo "$BUFFER" | jq -s
}

vm.ssh() {
  VM_NAME="$1"
  ssh "clouduser@$(vm.ipv4 "${VM_NAME}")"
}

vm.scp() {
  # shellcheck disable=SC2206
  ARGS=($@)
  LENGTH_MINUS_TWO="$(("${#ARGS[@]}" - 2))"
  REMOTE_NAME="${ARGS[-2]}"
  REMOTE_IP="$(vm.ipv4 "${REMOTE_NAME}")"
  REMOTE_PATH="${ARGS[-1]}"

  # shellcheck disable=SC2068
  scp -rp ${ARGS[@]:0:${LENGTH_MINUS_TWO}} "clouduser@${REMOTE_IP}:${REMOTE_PATH}"
}

vm.exec() {
  VM_NAME="$1"
  CMD="$2"
  # shellcheck disable=SC2068
  # shellcheck disable=SC2029
  ssh "clouduser@$(vm.ipv4 "${VM_NAME}")" "${CMD}"
}

# Provide the VM DNS server

### Provision the DNS VM

```shell
{
  vm.new dns0 fedora37
}
```

### Build "BetterDNS"

```shell
{
  HOSTNAME="dns0"
  BIN="betterdns"
  FILES="Corefile dns_manifest Rocket.toml"
  DEST="/var/lib/betterdns"
  REPO="https://gitlab.com/alexandre.mahdhaoui/betterdns.git"
  REPO_DIR="$(basename "${REPO}" .git)"
  DOMAIN_NAME=tutorial.cloud
  DNS_IP="10.128.0.2"
 
  git clone "${REPO}"
  cd "${REPO_DIR}"
  cargo build --release
  chmod 755 "$(find . -name "${BIN}")"
cat <<EOF > Corefile
${DOMAIN_NAME}:53 {
    log stdout
    file dns_manifest
}
EOF
cat <<EOF > dns_manifest
$TTL 3600
${DOMAIN_NAME} IN SOA sns.dns.icann.org. noc.dns.icann.org. 3 7200 3600 1209600 3600
${DOMAIN_NAME} IN NS b.iana-servers.net.
${DOMAIN_NAME} IN NS a.iana-servers.net.
dns IN A ${DNS_IP}
EOF

  BIN_="$(find . -name "${BIN}")"
  FILES_="$(for x in ${FILES}; do find . -name "${x}" | head -1; done)"
  vm.exec "${HOSTNAME}" "sudo mkdir -p ${DEST}"
  vm.scp "${BIN_}" ${FILES_}  "${HOSTNAME}" '~/'
  vm.exec "${HOSTNAME}" "sudo mv \"${BIN}\"  \"${DEST}\""
  vm.exec "${HOSTNAME}" "sudo mv ${FILES}  \"${DEST}\""
  vm.exec "${HOSTNAME}" "sudo restorecon -Rv \"${DEST}\""
  cd
  rm -rf "./${REPO_DIR}"
}
```

### Create DNS Service

```shell
{
HOSTNAME="dns0"
FILENAME="betterdns.service"
DEST_PATH="/etc/systemd/system/"

cat <<EOF | tee "${FILENAME}"
[Unit]
Description=betterdns
Documentation=https://gitlab.com/alexandre.mahdhaoui/betterdns

[Service]
ExecStart=/var/lib/betterdns/betterdns
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

vm.scp "${FILENAME}" "${HOSTNAME}" '~/'
vm.exec "${HOSTNAME}" "sudo mkdir -p \"${DEST_PATH}\""
vm.exec "${HOSTNAME}" "sudo mv \"${FILENAME}\" \"${DEST_PATH}\""
vm.exec "${HOSTNAME}" "sudo restorecon -Rv \"${DEST_PATH}\""
}
```

### Enable the betterdns service

```shell
{
  HOSTNAME="dns0"
  vm.exec ${HOSTNAME} '{
    sudo systemctl daemon-reload
    sudo systemctl enable betterdns
    sudo systemctl start betterdns
  }'
}
```

Next: [Installing the Client Tools](../docs/02-client-tools.md)

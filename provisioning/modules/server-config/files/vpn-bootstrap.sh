#!/usr/bin/env bash
# First-boot setup for the VPN server. cloud-init runs this once, after the
# packages are installed and the config files from the server-config module
# are in place. It is safe to re-run.
set -euo pipefail

# shellcheck source=/dev/null
. /etc/vpn/vpn.env

wg_dir=/etc/wireguard
wg_conf="$wg_dir/$WG_IFACE.conf"

# The server's private key is generated here, on the server, so it never
# passes through Terraform state or the machine that ran the deploy.
umask 077
if [[ ! -s "$wg_dir/server.key" ]]; then
  wg genkey > "$wg_dir/server.key"
fi
wg pubkey < "$wg_dir/server.key" > "$wg_dir/server.pub"
chmod 644 "$wg_dir/server.pub"

# Put the key into the interface config. awk reads it from the file so it
# never shows up in a process argument list.
tmp=$(mktemp "$wg_conf.XXXXXX")
awk -v keyfile="$wg_dir/server.key" '
  BEGIN { getline key < keyfile }
  /^PrivateKey = / { $0 = "PrivateKey = " key }
  { print }
' "$wg_conf" > "$tmp"
chmod 600 "$tmp"
mv "$tmp" "$wg_conf"

sysctl --system > /dev/null

nft -c -f /etc/nftables.conf
systemctl enable nftables
systemctl restart nftables

systemctl enable --now "wg-quick@$WG_IFACE"

# Ubuntu's unbound package can repoint the server's own resolver at
# 127.0.0.1, where this unbound does not listen. Keep systemd-resolved.
systemctl disable --now unbound-resolvconf.service 2> /dev/null || true
unbound-checkconf
systemctl enable unbound
systemctl restart unbound

systemctl enable --now fail2ban
systemctl restart ssh

echo "vpn-bootstrap: done. Server public key: $(cat "$wg_dir/server.pub")"

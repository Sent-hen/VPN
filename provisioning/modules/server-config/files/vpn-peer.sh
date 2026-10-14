#!/usr/bin/env bash
# Manage WireGuard peers on the VPN server without rebuilding it.
#
#   vpn-peer list
#   vpn-peer add <name> <public-key>
#   vpn-peer remove <name>
#   vpn-peer server-pubkey
#
# Each peer is a block in the interface config, introduced by a
# "# peer: <name>" comment. Changes are applied live with `wg syncconf`.
#
# This script is called over SSH, so every argument is validated before it
# touches the config file.
set -euo pipefail

# shellcheck source=/dev/null
. "${VPN_ENV_FILE:-/etc/vpn/vpn.env}"
WG_CONF="${WG_CONF:-/etc/wireguard/$WG_IFACE.conf}"
SERVER_PUBKEY_FILE="${SERVER_PUBKEY_FILE:-/etc/wireguard/server.pub}"
LOCK_FILE="${LOCK_FILE:-/run/lock/vpn-peer.lock}"

die() {
  echo "vpn-peer: $*" >&2
  exit 1
}

valid_name() { [[ $1 =~ ^[a-z0-9][a-z0-9-]{0,31}$ ]]; }

# A WireGuard key is 32 bytes of base64: 43 significant characters plus "=".
# The last character before the padding can only encode 4 bits.
valid_key() { [[ $1 =~ ^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw048]=$ ]]; }

reload() {
  [[ -n "${VPN_PEER_NO_RELOAD:-}" ]] && return
  wg syncconf "$WG_IFACE" <(wg-quick strip "$WG_IFACE")
}

lock() {
  command -v flock > /dev/null || return 0
  exec 9> "$LOCK_FILE"
  flock 9
}

# Prints the lowest host number in 2..254 that no peer is using yet.
next_host() {
  local used n
  used=$(grep -oE "^AllowedIPs = ${TUNNEL_IPV4_PREFIX//./\\.}\.[0-9]+/" "$WG_CONF" |
    grep -oE '[0-9]+/$' | tr -d / || true)
  for n in $(seq 2 254); do
    if ! grep -qx "$n" <<< "$used"; then
      echo "$n"
      return
    fi
  done
  die "no free addresses left in $TUNNEL_IPV4_PREFIX.0/24"
}

cmd_list() {
  printf 'NAME\tADDRESSES\tPUBLIC KEY\n'
  awk '
    /^# peer: / { name = $3 }
    /^PublicKey = / { key = $3 }
    /^AllowedIPs = / {
      sub(/^AllowedIPs = /, "")
      printf "%s\t%s\t%s\n", name, $0, key
    }
  ' "$WG_CONF"
}

cmd_add() {
  [[ $# -eq 2 ]] || die "usage: vpn-peer add <name> <public-key>"
  local name=$1 key=$2 host ipv4 ipv6
  valid_name "$name" || die "invalid name: use lowercase letters, digits and dashes (max 32)"
  valid_key "$key" || die "invalid WireGuard public key"

  lock
  grep -Fqx "# peer: $name" "$WG_CONF" && die "peer '$name' already exists"
  grep -Fqx "PublicKey = $key" "$WG_CONF" && die "that public key is already registered"

  host=$(next_host)
  ipv4="$TUNNEL_IPV4_PREFIX.$host"
  ipv6="$TUNNEL_IPV6_BASE$(printf '%x' "$host")"
  printf '\n# peer: %s\n[Peer]\nPublicKey = %s\nAllowedIPs = %s/32, %s/128\n' \
    "$name" "$key" "$ipv4" "$ipv6" >> "$WG_CONF"
  reload

  # KEY=VALUE output so the client tooling can parse it.
  echo "NAME=$name"
  echo "ADDRESS_IPV4=$ipv4"
  echo "ADDRESS_IPV6=$ipv6"
  echo "DNS=$SERVER_TUNNEL_IPV4,$SERVER_TUNNEL_IPV6"
  echo "SERVER_PUBLIC_KEY=$(cat "$SERVER_PUBKEY_FILE")"
  echo "PORT=$WG_PORT"
}

cmd_remove() {
  [[ $# -eq 1 ]] || die "usage: vpn-peer remove <name>"
  local name=$1 tmp
  valid_name "$name" || die "invalid name"

  lock
  grep -Fqx "# peer: $name" "$WG_CONF" || die "no peer named '$name'"
  tmp=$(mktemp "$WG_CONF.XXXXXX")
  awk -v target="# peer: $name" '
    $0 == target { skip = 1; next }
    skip && /^# peer: / { skip = 0 }
    !skip { print }
  ' "$WG_CONF" > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$WG_CONF"
  reload
  echo "removed $name"
}

cmd_server_pubkey() {
  cat "$SERVER_PUBKEY_FILE"
}

case "${1:-}" in
  list) cmd_list ;;
  add) shift && cmd_add "$@" ;;
  remove) shift && cmd_remove "$@" ;;
  server-pubkey) cmd_server_pubkey ;;
  *) die "usage: vpn-peer {list|add <name> <public-key>|remove <name>|server-pubkey}" ;;
esac

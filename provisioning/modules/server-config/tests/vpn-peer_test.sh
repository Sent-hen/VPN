#!/usr/bin/env bash
# Exercises vpn-peer against a scratch config, without WireGuard installed.
#   bash provisioning/modules/server-config/tests/vpn-peer_test.sh
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
peer="$here/../files/vpn-peer.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat > "$work/vpn.env" << 'EOF'
WG_IFACE=wg0
WG_PORT=51820
TUNNEL_IPV4_PREFIX=10.8.0
TUNNEL_IPV6_BASE=fd86:ea04:1115::
SERVER_TUNNEL_IPV4=10.8.0.1
SERVER_TUNNEL_IPV6=fd86:ea04:1115::1
EOF
cat > "$work/wg0.conf" << 'EOF'
[Interface]
Address = 10.8.0.1/24, fd86:ea04:1115::1/64
ListenPort = 51820
PrivateKey = GENERATED_ON_FIRST_BOOT

# peer: laptop
[Peer]
PublicKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
AllowedIPs = 10.8.0.2/32, fd86:ea04:1115::2/128
EOF
echo "SERVERPUBKEY=" > "$work/server.pub"

export VPN_ENV_FILE="$work/vpn.env" WG_CONF="$work/wg0.conf" \
  SERVER_PUBKEY_FILE="$work/server.pub" LOCK_FILE="$work/lock" VPN_PEER_NO_RELOAD=1

key_b=BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBA=
key_c=CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCA=
key_d=DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDA=

fails=0
check() { # check <description> <command...>
  local desc=$1
  shift
  if "$@" > /dev/null 2>&1; then
    echo "ok   $desc"
  else
    echo "FAIL $desc"
    fails=$((fails + 1))
  fi
}
rejects() { # rejects <description> <args...>
  local desc=$1
  shift
  if bash "$peer" "$@" > /dev/null 2>&1; then
    echo "FAIL $desc (accepted)"
    fails=$((fails + 1))
  else
    echo "ok   $desc"
  fi
}

out=$(bash "$peer" add phone "$key_b")
check "add assigns next free host" grep -qx "ADDRESS_IPV4=10.8.0.3" <<< "$out"
check "add assigns matching IPv6" grep -qx "ADDRESS_IPV6=fd86:ea04:1115::3" <<< "$out"
check "add reports server key" grep -qx "SERVER_PUBLIC_KEY=SERVERPUBKEY=" <<< "$out"

bash "$peer" add tablet "$key_c" > /dev/null
bash "$peer" remove phone > /dev/null
check "remove drops the peer block" bash -c "! grep -q 'phone\|$key_b' '$WG_CONF'"
check "remove keeps other peers" grep -q "# peer: tablet" "$WG_CONF"
check "remove keeps the interface" grep -q "^ListenPort = 51820" "$WG_CONF"

out=$(bash "$peer" add desktop "$key_d")
check "freed host is reused" grep -qx "ADDRESS_IPV4=10.8.0.3" <<< "$out"
check "list shows every peer" bash -c "[ \$(bash '$peer' list | wc -l) -eq 4 ]"

rejects "duplicate name" add laptop "$key_b"
rejects "duplicate key" add other "$key_c"
rejects "bad key" add other "not-a-key"
rejects "key with trailing config" add other "$key_b
AllowedIPs = 0.0.0.0/0"
rejects "name with newline" add "x
[Interface]" "$key_b"
rejects "uppercase name" add Phone "$key_b"
rejects "path-like name" add ../etc "$key_b"
rejects "unknown peer" remove nobody
rejects "unknown command" frobnicate

[[ $fails -eq 0 ]] && echo "all passed" || { echo "$fails failed"; exit 1; }

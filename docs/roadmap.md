# Roadmap

Ship Tier A (the usable product) completely before starting Tier B (the
educational tunnel). Windows is the first fully supported client.

## Target layout

```
cmd/vpnctl/          CLI: device keys, client configs (exists)
cmd/vpnd/            privileged Windows service (Phase 3)
internal/wgkey/      key generation (exists)
internal/keystore/   device key storage (exists; DPAPI in Phase 3)
internal/clientconf/ config building (exists)
internal/ipc/        authenticated named-pipe protocol (Phase 4)
ui/                  Tauri app (Phase 4)
provisioning/        Terraform + cloud-init (exists)
toytunnel/           Tier B (Phase 6)
docs/                threat model, runbook, reports
```

## Phase 1: manual baseline ✅ documented

See [manual-setup.md](manual-setup.md). Still to do: run it once and record
the verification checklist results.

## Phase 2: automated provisioning ✅ in progress

- [x] Hetzner server, cloud firewall, SSH key (Terraform)
- [x] cloud-init: admin user, SSH hardening, WireGuard, nftables, NAT (IPv4 and IPv6), Unbound, unattended upgrades, fail2ban
- [x] Server key generated on the server; device keys generated on the device
- [x] `vpn-peer` for adding and removing devices without a rebuild
- [x] `vpnctl` keygen and client-config
- [ ] First real deploy; measure time from `terraform apply` to first handshake
- [ ] Teardown and rebuild test (`terraform destroy && terraform apply`)
- [ ] Pin SSH host keys instead of trust on first use
- [ ] Optional ad and tracker blocklist for Unbound
- [ ] CI: `terraform validate`, `go test`, `shellcheck`, `tests/vpn-peer_test.sh`

## Phase 3: Windows daemon (`vpnd`)

- Windows service written in Go, using wireguard-nt through
  `golang.zx2c4.com/wireguard/windows` (the same stack as the official client)
- Owns the tunnel: create the adapter, set addresses, routes and DNS
- Kill switch with Windows Filtering Platform rules: block everything except
  the tunnel adapter, the endpoint's UDP port, DHCP and loopback
- Handshake monitoring, reconnect, and clean recovery after crash or sleep
- Private keys stored with DPAPI (machine scope, service-only ACL)

## Phase 4: Tauri UI

- Named-pipe IPC with an ACL limited to the interactive user, plus a per-session token
- Screens in order: status, live stats, devices (QR code for phones), servers
  (deploy wizard), safety checks, settings, diagnostics bundle

## Phase 5: verification and hardening

- Automated leak tests: IP, DNS, IPv6, network change, sleep and wake, tunnel
  drop with kill switch on
- iperf3 throughput and latency with and without the VPN
- Review the design against [threat-model.md](threat-model.md)

## Phase 6: Tier B toy tunnel (optional)

Userspace TUN tunnel using a Noise library and AEAD with a replay window.
Benchmark against WireGuard and write up the gaps. Labeled educational and
never used for real traffic.

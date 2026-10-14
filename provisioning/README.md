# Provisioning

Creates a hardened WireGuard server on Hetzner Cloud with Terraform and
cloud-init.

- `modules/server-config/` turns a fresh Ubuntu 24.04 server into the VPN
  server. It works with any provider and outputs only cloud-init user data.
- `hetzner/` creates the Hetzner server, firewall and SSH key, and feeds them
  the module's user data.

## What you get

| | |
|---|---|
| Open to the internet | UDP 51820 (WireGuard), ICMP. SSH only from `admin_cidrs`. |
| Inside the tunnel | 10.8.0.0/24 and fd86:ea04:1115::/64. The server is .1 / ::1. |
| DNS | Unbound on the server, DNSSEC-validating, no query logs, tunnel clients only |
| NAT | IPv4 and IPv6 masquerade, so the tunnel carries both and IPv6 cannot leak |
| Isolation | Clients reach the internet but not each other |
| Hardening | Key-only SSH as `vpnadmin`, root login off, fail2ban, unattended security upgrades with 04:00 reboots |
| Keys | Server key generated on the server. Device keys generated on devices. No private key in Terraform state. |

## Deploy

Requirements: [Terraform](https://developer.hashicorp.com/terraform/install)
1.6+, an SSH key (`ssh-keygen -t ed25519`), a Hetzner Cloud project with an
API token (Security > API tokens, read/write), and Go 1.26+ for `vpnctl`.

```powershell
# 1. Create this device's key. Only the public key is printed.
go run ./cmd/vpnctl keygen -device laptop

# 2. Configure.
cd provisioning/hetzner
copy terraform.tfvars.example terraform.tfvars   # paste the public key, set admin_cidrs
$env:TF_VAR_hcloud_token = "<token>"

# 3. Create the server (about 1 minute; first-boot setup takes 2-3 more).
terraform init
terraform apply

# 4. Build the client config. This waits for first boot to finish, fetches the
#    server's public key over SSH, and checks it matches this device.
cd ../..
go run ./cmd/vpnctl client-config -device laptop
```

Import the written `.conf` in [WireGuard for Windows](https://www.wireguard.com/install/),
activate it, and delete the file.

Get your public IP for `admin_cidrs` with `curl.exe -4 ifconfig.me`. Once
connected, you can set `admin_cidrs = []` and `terraform apply` again: SSH
then only works through the tunnel (`ssh vpnadmin@10.8.0.1`).

## Add or remove a device later

Changing `peers` in Terraform does **not** affect a running server: the
initial peers are only applied at first boot, so that an edit can never
silently destroy the server and every client's config. Instead:

```bash
ssh vpnadmin@10.8.0.1 sudo vpn-peer add phone <public-key>
ssh vpnadmin@10.8.0.1 sudo vpn-peer list
ssh vpnadmin@10.8.0.1 sudo vpn-peer remove phone
```

## Rebuild or tear down

```powershell
terraform apply -replace="hcloud_server.vpn"   # fresh server, new IP and key
terraform destroy                              # stop paying
```

After a rebuild, run `vpnctl client-config` again: the server key and IP have
changed. Devices added with `vpn-peer` must be added again, or listed in
`peers`.

## Debugging first boot

```bash
ssh vpnadmin@<ip> cloud-init status --long
ssh vpnadmin@<ip> sudo journalctl -u cloud-final
ssh vpnadmin@<ip> sudo wg show
ssh vpnadmin@<ip> sudo nft list ruleset
```

## Tests

```bash
bash provisioning/modules/server-config/tests/vpn-peer_test.sh
```

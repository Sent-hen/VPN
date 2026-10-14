# Personal VPN

> One command deploys a private WireGuard server in the cloud, and a desktop
> app connects me to it. My traffic on café Wi-Fi is encrypted, and I control
> every piece instead of trusting a VPN company.

**Status:** server provisioning works (Phase 2). The Windows daemon and
desktop UI come next. See the [roadmap](docs/roadmap.md).

## What it is, and what it isn't

A VPN makes your device send everything through an encrypted tunnel to a
server, which then talks to the internet for you. The coffee-shop network and
your ISP see only encrypted packets going to one address.

It moves trust: from the local network and ISP to the server and the cloud host
running it. Here, that server is mine. **This is privacy on untrusted networks,
not anonymity.** The [threat model](docs/threat-model.md) lists exactly what it
does and does not protect against.

## Architecture

```
 [ Desktop UI ]  Tauri                                   planned (Phase 4)
      |  named pipe, authenticated
 [ vpnd ]  Go Windows service: tunnel, routes, DNS,      planned (Phase 3)
      |    kill switch (WFP)
 [ WireGuard ]  wireguard-nt
      |
      |  encrypted UDP 51820
      v
 [ VPN server ]  Ubuntu 24.04 on Hetzner                 working
      WireGuard, nftables (NAT, default-deny), Unbound DNS,
      key-only SSH, fail2ban, automatic security updates

 [ Provisioner ]  Terraform + cloud-init                 working
 [ vpnctl ]  device keys and client configs              working
```

Two design choices to point out:

- **No home-made crypto in the product.** It uses WireGuard. A from-scratch
  tunnel built on a vetted library is a separate, clearly labeled learning
  module (Tier B).
- **Private keys never travel.** Each device generates its own key and only
  shares the public half. The server generates its key at first boot. Terraform
  state contains no secrets except your API token, which stays in an environment
  variable.

## Quick start

You need Terraform 1.6+, Go 1.26+, an SSH key, and a Hetzner Cloud API token.
It costs about €4 a month while the server exists.

```powershell
go run ./cmd/vpnctl keygen -device laptop        # prints the public key
cd provisioning/hetzner
copy terraform.tfvars.example terraform.tfvars   # paste it in, set admin_cidrs
$env:TF_VAR_hcloud_token = "<token>"
terraform init; terraform apply
cd ../..
go run ./cmd/vpnctl client-config -device laptop # writes the WireGuard config
```

Import the config in [WireGuard for Windows](https://www.wireguard.com/install/).
Full instructions: [provisioning/README.md](provisioning/README.md).

## Repository

| Path | |
|---|---|
| [provisioning/](provisioning/) | Terraform for Hetzner and the provider-agnostic server config |
| [cmd/vpnctl](cmd/vpnctl/) | Client CLI |
| [internal/](internal/) | Key generation, key storage, client config building |
| [docs/threat-model.md](docs/threat-model.md) | What this protects against, and what it doesn't |
| [docs/manual-setup.md](docs/manual-setup.md) | Every step the automation does, by hand |
| [docs/roadmap.md](docs/roadmap.md) | Phases and progress |

## Development

```powershell
go test ./...
bash provisioning/modules/server-config/tests/vpn-peer_test.sh
terraform -chdir=provisioning/hetzner validate
```

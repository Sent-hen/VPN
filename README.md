# Personal VPN

My own WireGuard VPN. One command sets up a server in the cloud, and (once
it's built) a desktop app will connect me to it. I wanted my traffic on café
Wi-Fi encrypted without having to trust a VPN company with it.

**Status:** server provisioning works (Phase 2). The Windows daemon and
desktop UI are next. See the [roadmap](docs/roadmap.md).

## What a VPN does and doesn't do

Your device sends all its traffic through an encrypted tunnel to a server, and
the server talks to the internet for you. The café network and your ISP only
see encrypted packets going to one address.

That doesn't remove the need for trust. It moves it from the local network and
ISP to the server and whoever hosts it. In this case the server is mine.
**This gives you privacy on networks you don't trust. It doesn't make you
anonymous.** The [threat model](docs/threat-model.md) spells out what it
protects against and what it doesn't.

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

Two decisions worth knowing about:

- **No home-made crypto.** The real tunnel is WireGuard. Later I plan to
  write a toy tunnel from scratch on a vetted crypto library, just to learn how
  it works. That will stay separate and won't carry real traffic (Tier B).
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

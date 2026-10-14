# Manual setup (Phase 1 runbook)

These are the steps the provisioning code automates, done by hand on a fresh
Ubuntu 24.04 server. Doing them once explains what every file in
`provisioning/modules/server-config` is for. Each step names the file that
automates it.

## 1. Create the server

Create the smallest Ubuntu 24.04 server in the Hetzner console, with your SSH
key. *(provisioning/hetzner/main.tf)*

## 2. Admin user and SSH hardening

```bash
adduser --disabled-password vpnadmin
usermod -aG sudo vpnadmin
mkdir -p /home/vpnadmin/.ssh
cp ~/.ssh/authorized_keys /home/vpnadmin/.ssh/
chown -R vpnadmin: /home/vpnadmin/.ssh
```

Write `/etc/ssh/sshd_config.d/05-vpn-hardening.conf`
*(templates/sshd-hardening.conf.tftpl)*, then `systemctl restart ssh`. Test
that you can still log in as `vpnadmin` **before** closing the root session.

## 3. Packages and automatic updates

```bash
apt update && apt full-upgrade -y
apt install -y wireguard nftables unbound unattended-upgrades fail2ban
```

Enable unattended upgrades and the 04:00 reboot
*(`20auto-upgrades` and `52vpn-auto-reboot` in main.tf)*.

## 4. Forwarding

```bash
echo 'net.ipv4.ip_forward = 1' >  /etc/sysctl.d/99-vpn-forwarding.conf
echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.d/99-vpn-forwarding.conf
sysctl --system
```

Without this the server receives your packets but never passes them on.

## 5. WireGuard

```bash
umask 077
wg genkey | tee /etc/wireguard/server.key | wg pubkey > /etc/wireguard/server.pub
```

Write `/etc/wireguard/wg0.conf` *(templates/wg0.conf.tftpl)* with the server's
private key and one `[Peer]` per device, then:

```bash
systemctl enable --now wg-quick@wg0
wg show
```

## 6. Firewall and NAT

Write `/etc/nftables.conf` *(templates/nftables.conf.tftpl)*. Then:

```bash
nft -c -f /etc/nftables.conf   # check syntax first
systemctl enable --now nftables
nft list ruleset
```

The `masquerade` rules rewrite tunnel addresses (10.8.0.x) to the server's
public IP, which is the only way replies can find their way back.

## 7. DNS resolver

Write `/etc/unbound/unbound.conf.d/vpn.conf`
*(templates/unbound.conf.tftpl)*, then:

```bash
systemctl disable --now unbound-resolvconf
unbound-checkconf && systemctl restart unbound
```

## 8. Client

Install [WireGuard for Windows](https://www.wireguard.com/install/), create a
tunnel, and copy its public key into the server's `[Peer]`. Fill in the client
side as `vpnctl client-config` would.

## 9. Verify (record these for the report)

- [ ] `curl -4 ifconfig.me` and `curl -6 ifconfig.me` from the client show the
      server's IPs while connected and your own when disconnected.
- [ ] A DNS leak test site lists only the server's IP as your resolver.
- [ ] Wireshark on the Wi-Fi adapter shows only UDP to the server on port
      51820. No DNS, no TCP to anything else.
- [ ] `wg show` on the server shows a recent handshake and growing transfer
      counters.
- [ ] `nmap -sU -p 51820 <server>` and `nmap <server>` from another network
      report nothing open (WireGuard stays silent).

# Renders the cloud-init user data that turns a fresh Ubuntu 24.04 server into
# the VPN server. Provider-agnostic: any cloud that accepts cloud-init can use
# this output.

locals {
  server_ipv4 = cidrhost(var.tunnel_ipv4_cidr, 1)
  server_ipv6 = cidrhost(var.tunnel_ipv6_cidr, 1)

  peers = {
    for name, p in var.peers : name => {
      public_key = p.public_key
      ipv4       = cidrhost(var.tunnel_ipv4_cidr, p.host)
      ipv6       = cidrhost(var.tunnel_ipv6_cidr, p.host)
    }
  }

  template_vars = {
    admin_user         = var.admin_user
    admin_ipv4_cidrs   = [for c in var.admin_cidrs : c if !strcontains(c, ":")]
    admin_ipv6_cidrs   = [for c in var.admin_cidrs : c if strcontains(c, ":")]
    wg_port            = var.wg_port
    tunnel_ipv4_cidr   = var.tunnel_ipv4_cidr
    tunnel_ipv6_cidr   = var.tunnel_ipv6_cidr
    tunnel_ipv4_prefix = join(".", slice(split(".", cidrhost(var.tunnel_ipv4_cidr, 0)), 0, 3))
    tunnel_ipv6_base   = cidrhost(var.tunnel_ipv6_cidr, 0) # e.g. "fd86:ea04:1115::"
    server_ipv4        = local.server_ipv4
    server_ipv6        = local.server_ipv6
    peers              = local.peers
  }

  # Files are deferred so they land after package installation; otherwise
  # dpkg could stop to ask about the conffiles we replace.
  files = [
    {
      path        = "/etc/vpn/vpn.env"
      permissions = "0644"
      content     = templatefile("${path.module}/templates/vpn.env.tftpl", local.template_vars)
    },
    {
      path        = "/etc/wireguard/wg0.conf"
      permissions = "0600"
      content     = templatefile("${path.module}/templates/wg0.conf.tftpl", local.template_vars)
    },
    {
      path        = "/etc/nftables.conf"
      permissions = "0755"
      content     = templatefile("${path.module}/templates/nftables.conf.tftpl", local.template_vars)
    },
    {
      path        = "/etc/unbound/unbound.conf.d/vpn.conf"
      permissions = "0644"
      content     = templatefile("${path.module}/templates/unbound.conf.tftpl", local.template_vars)
    },
    {
      path        = "/etc/ssh/sshd_config.d/05-vpn-hardening.conf"
      permissions = "0644"
      content     = templatefile("${path.module}/templates/sshd-hardening.conf.tftpl", local.template_vars)
    },
    {
      path        = "/etc/sysctl.d/99-vpn-forwarding.conf"
      permissions = "0644"
      content     = "net.ipv4.ip_forward = 1\nnet.ipv6.conf.all.forwarding = 1\n"
    },
    {
      path        = "/etc/apt/apt.conf.d/20auto-upgrades"
      permissions = "0644"
      content     = "APT::Periodic::Update-Package-Lists \"1\";\nAPT::Periodic::Unattended-Upgrade \"1\";\n"
    },
    {
      # Kernel and WireGuard fixes need a reboot to take effect.
      path        = "/etc/apt/apt.conf.d/52vpn-auto-reboot"
      permissions = "0644"
      content     = "Unattended-Upgrade::Automatic-Reboot \"true\";\nUnattended-Upgrade::Automatic-Reboot-Time \"04:00\";\n"
    },
    {
      path        = "/usr/local/sbin/vpn-bootstrap"
      permissions = "0755"
      content     = file("${path.module}/files/vpn-bootstrap.sh")
    },
    {
      path        = "/usr/local/sbin/vpn-peer"
      permissions = "0755"
      content     = file("${path.module}/files/vpn-peer.sh")
    },
  ]

  cloud_config = {
    users = [{
      name                = var.admin_user
      groups              = ["sudo"]
      shell               = "/bin/bash"
      lock_passwd         = true
      sudo                = "ALL=(ALL) NOPASSWD:ALL" # key-only account with no password to type
      ssh_authorized_keys = [var.admin_ssh_public_key]
    }]
    disable_root    = true
    ssh_pwauth      = false
    package_update  = true
    package_upgrade = true
    packages        = ["wireguard", "nftables", "unbound", "unattended-upgrades", "fail2ban"]
    write_files     = [for f in local.files : merge(f, { owner = "root:root", defer = true })]
    runcmd          = [["/usr/local/sbin/vpn-bootstrap"]]
  }
}

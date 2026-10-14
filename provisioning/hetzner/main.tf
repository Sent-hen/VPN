module "server_config" {
  source = "../modules/server-config"

  admin_user           = var.admin_user
  admin_ssh_public_key = trimspace(file(pathexpand(var.admin_ssh_public_key_path)))
  admin_cidrs          = var.admin_cidrs
  wg_port              = var.wg_port
  tunnel_ipv4_cidr     = var.tunnel_ipv4_cidr
  tunnel_ipv6_cidr     = var.tunnel_ipv6_cidr
  peers                = var.peers
}

resource "hcloud_ssh_key" "admin" {
  name       = "${var.name}-admin"
  public_key = trimspace(file(pathexpand(var.admin_ssh_public_key_path)))
}

# First layer of filtering, applied by Hetzner before traffic reaches the
# server. nftables on the server repeats these rules.
resource "hcloud_firewall" "vpn" {
  name = var.name

  rule {
    description = "WireGuard"
    direction   = "in"
    protocol    = "udp"
    port        = tostring(var.wg_port)
    source_ips  = ["0.0.0.0/0", "::/0"]
  }

  rule {
    description = "ICMP, needed for path MTU discovery"
    direction   = "in"
    protocol    = "icmp"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }

  dynamic "rule" {
    for_each = length(var.admin_cidrs) > 0 ? [1] : []
    content {
      description = "SSH from admin networks"
      direction   = "in"
      protocol    = "tcp"
      port        = "22"
      source_ips  = var.admin_cidrs
    }
  }
}

resource "hcloud_server" "vpn" {
  name         = var.name
  server_type  = var.server_type
  image        = var.image
  location     = var.location
  ssh_keys     = [hcloud_ssh_key.admin.id]
  firewall_ids = [hcloud_firewall.vpn.id]
  user_data    = module.server_config.user_data

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  labels = {
    app = "personal-vpn"
  }

  lifecycle {
    # Changing user_data would destroy the server, along with its key and IP,
    # and every client config with it. Peers added later are managed with
    # `vpn-peer`. To rebuild on purpose: terraform apply -replace=hcloud_server.vpn
    ignore_changes = [user_data]
  }
}

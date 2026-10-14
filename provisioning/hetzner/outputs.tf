output "server_ipv4" {
  value = hcloud_server.vpn.ipv4_address
}

output "server_ipv6" {
  value = hcloud_server.vpn.ipv6_address
}

output "ssh" {
  description = "SSH command for the admin account."
  value       = "ssh ${var.admin_user}@${hcloud_server.vpn.ipv4_address}"
}

# Read by `vpnctl client-config`. Contains no secrets: the server's private
# key never leaves the server and device private keys never leave devices.
output "client" {
  value = {
    endpoint    = "${hcloud_server.vpn.ipv4_address}:${var.wg_port}"
    server_ipv4 = hcloud_server.vpn.ipv4_address
    admin_user  = var.admin_user
    dns         = [module.server_config.server_tunnel_ipv4, module.server_config.server_tunnel_ipv6]
    peers       = module.server_config.peers
  }
}

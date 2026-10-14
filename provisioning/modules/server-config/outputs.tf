output "user_data" {
  description = "cloud-init user data for the VPN server."
  value       = "#cloud-config\n${yamlencode(local.cloud_config)}"
}

output "server_tunnel_ipv4" {
  description = "The server's address inside the tunnel (also the DNS resolver)."
  value       = local.server_ipv4
}

output "server_tunnel_ipv6" {
  description = "The server's IPv6 address inside the tunnel (also the DNS resolver)."
  value       = local.server_ipv6
}

output "peers" {
  description = "Tunnel addresses assigned to each first-boot peer."
  value       = local.peers
}

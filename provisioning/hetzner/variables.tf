variable "hcloud_token" {
  description = "Hetzner Cloud API token (read/write). Prefer setting TF_VAR_hcloud_token over writing it to a file."
  type        = string
  sensitive   = true
}

variable "name" {
  description = "Name for the server and its related resources."
  type        = string
  default     = "personal-vpn"
}

variable "location" {
  description = "Hetzner location: fsn1, nbg1, hel1 (EU), ash, hil (US), sin (Asia)."
  type        = string
  default     = "nbg1"
}

variable "server_type" {
  description = "Hetzner server type. The VPN needs very little; use the cheapest type that is orderable (`hcloud server-type list`)."
  type        = string
  default     = "cx23"
}

variable "image" {
  description = "OS image. The server config is written for Ubuntu 24.04."
  type        = string
  default     = "ubuntu-24.04"
}

variable "admin_user" {
  description = "SSH admin account created on the server."
  type        = string
  default     = "vpnadmin"
}

variable "admin_ssh_public_key_path" {
  description = "Path to the OpenSSH public key used for the admin account."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "admin_cidrs" {
  description = <<-EOT
    Networks allowed to reach SSH from the internet, such as your current
    public IP as x.x.x.x/32. Needed once to fetch the server's public key.
    Set to [] afterwards and SSH is only reachable through the tunnel.
  EOT
  type        = list(string)
  default     = []
}

variable "wg_port" {
  description = "UDP port WireGuard listens on."
  type        = number
  default     = 51820
}

variable "tunnel_ipv4_cidr" {
  description = "IPv4 /24 used inside the tunnel."
  type        = string
  default     = "10.8.0.0/24"
}

variable "tunnel_ipv6_cidr" {
  description = "IPv6 ULA /64 used inside the tunnel."
  type        = string
  default     = "fd86:ea04:1115::/64"
}

variable "peers" {
  description = "Devices allowed at first boot: { name = { public_key = \"...\", host = 2 } }. Generate keys on the device with `vpnctl keygen`."
  type = map(object({
    public_key = string
    host       = number
  }))
  default = {}
}

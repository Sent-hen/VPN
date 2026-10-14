variable "admin_user" {
  description = "Name of the SSH admin account created on the server."
  type        = string
  default     = "vpnadmin"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_-]{0,31}$", var.admin_user))
    error_message = "admin_user must be a valid lowercase Linux user name."
  }
}

variable "admin_ssh_public_key" {
  description = "OpenSSH public key allowed to log in as admin_user."
  type        = string
}

variable "admin_cidrs" {
  description = "Networks allowed to reach SSH from the internet. SSH is always reachable from inside the tunnel."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.admin_cidrs : can(cidrhost(c, 0))])
    error_message = "Every admin_cidrs entry must be a CIDR block, such as 203.0.113.7/32."
  }
}

variable "wg_port" {
  description = "UDP port WireGuard listens on."
  type        = number
  default     = 51820
}

variable "tunnel_ipv4_cidr" {
  description = "IPv4 network inside the tunnel. Must be a /24; the server takes .1."
  type        = string
  default     = "10.8.0.0/24"

  validation {
    condition     = can(cidrhost(var.tunnel_ipv4_cidr, 0)) && endswith(var.tunnel_ipv4_cidr, "/24") && !strcontains(var.tunnel_ipv4_cidr, ":")
    error_message = "tunnel_ipv4_cidr must be an IPv4 /24."
  }
}

variable "tunnel_ipv6_cidr" {
  description = "IPv6 ULA network inside the tunnel. Must be a /64; the server takes ::1."
  type        = string
  default     = "fd86:ea04:1115::/64"

  validation {
    condition     = can(cidrhost(var.tunnel_ipv6_cidr, 0)) && endswith(var.tunnel_ipv6_cidr, "/64") && strcontains(var.tunnel_ipv6_cidr, ":")
    error_message = "tunnel_ipv6_cidr must be an IPv6 /64."
  }
}

variable "peers" {
  description = <<-EOT
    Devices allowed to connect at first boot, keyed by device name. Only the
    public key leaves the device. `host` is the device's host number inside
    the tunnel (2-254). Add devices later with `vpn-peer add` on the server.
  EOT
  type = map(object({
    public_key = string
    host       = number
  }))
  default = {}

  validation {
    condition     = alltrue([for name, _ in var.peers : can(regex("^[a-z0-9][a-z0-9-]{0,31}$", name))])
    error_message = "Peer names must be lowercase letters, digits and dashes (max 32)."
  }

  validation {
    condition     = alltrue([for p in values(var.peers) : can(regex("^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw048]=$", p.public_key))])
    error_message = "Every peer public_key must be a base64 WireGuard key."
  }

  validation {
    condition     = alltrue([for p in values(var.peers) : p.host >= 2 && p.host <= 254 && floor(p.host) == p.host])
    error_message = "Peer host numbers must be whole numbers from 2 to 254."
  }

  validation {
    condition     = length(distinct([for p in values(var.peers) : p.host])) == length(var.peers)
    error_message = "Two peers share the same host number."
  }
}

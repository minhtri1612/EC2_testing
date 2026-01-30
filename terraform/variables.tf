variable "name_prefix" {
  description = "Name prefix for created resources."
  type        = string
  default     = "ec2-bastion-vpn"
}

variable "vpc_cidr" {
  description = "VPC CIDR (use an RFC1918 private range)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Public subnet CIDR."
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "Private subnet CIDR."
  type        = string
  default     = "10.0.3.0/24"
}

variable "admin_cidr" {
  description = "Your public IP / CIDR allowed to reach the VPN admin and SSH (e.g. 1.2.3.4/32)."
  type        = string
  default     = "0.0.0.0/0"
}

variable "openvpn_instance_type" {
  description = "Instance type for OpenVPN server."
  type        = string
  default     = "t3.micro"
}

variable "private_instance_type" {
  description = "Instance type for private EC2."
  type        = string
  default     = "t3.micro"
}

variable "openvpn_client_cidr" {
  description = "VPN client subnet used by OpenVPN Access Server (used to add return route in private route table)."
  type        = string
  default     = "10.8.0.0/24"
}


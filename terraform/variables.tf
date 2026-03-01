variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "prefix" {
  description = "Resource name prefix"
  type        = string
  default     = "so-ai-lab"
}

variable "admin_cidr" {
  description = "Your public IP in CIDR notation (e.g., 73.45.123.89/32)"
  type        = string
}

variable "admin_username" {
  description = "Admin username for all VMs"
  type        = string
  default     = "labadmin"
}

variable "ssh_public_key" {
  description = "SSH public key content. Leave empty to auto-generate."
  type        = string
  default     = ""
}

variable "so_vm_size" {
  description = "Security Onion VM size (minimum 16GB RAM)"
  type        = string
  default     = "Standard_B4ms"
}

variable "so_image_version" {
  description = "Security Onion Marketplace image version"
  type        = string
  default     = "2.4.201"
}

variable "attacker_vm_size" {
  description = "Attacker VM size"
  type        = string
  default     = "Standard_B2ms"
}

variable "victim_vm_size" {
  description = "Victim VM size"
  type        = string
  default     = "Standard_B2ms"
}

variable "tags" {
  description = "Tags for all resources"
  type        = map(string)
  default = {
    project     = "security-onion-ai-demo"
    environment = "lab"
  }
}

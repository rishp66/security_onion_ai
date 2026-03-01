# =============================================================================
# Security Onion AI Demo Lab — Azure Infrastructure (Marketplace Edition v2)
# =============================================================================
# Lessons learned baked in:
#   - SO Marketplace image (no manual install)
#   - Post-deploy script: swap, iptables INPUT rule, nginx/kratos URL rewrite
#   - No manual so-firewall or so-allow needed
#
# Pre-requisite (one-time):
#   az vm image terms accept --publisher securityonionsolutions --offer securityonion --plan so2
#
# Usage:
#   terraform init
#   terraform plan -out=lab.tfplan
#   terraform apply lab.tfplan
# =============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
    tls     = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# =============================================================================
# SSH Key Generation
# =============================================================================

resource "tls_private_key" "ssh" {
  count     = var.ssh_public_key == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

locals {
  ssh_public_key  = var.ssh_public_key != "" ? var.ssh_public_key : tls_private_key.ssh[0].public_key_openssh
  ssh_private_key = var.ssh_public_key != "" ? "" : tls_private_key.ssh[0].private_key_pem
}

# =============================================================================
# Marketplace Agreement
# =============================================================================

resource "azurerm_marketplace_agreement" "securityonion" {
  publisher = "securityonionsolutions"
  offer     = "securityonion"
  plan      = "so2"
}

# =============================================================================
# Resource Group
# =============================================================================

resource "azurerm_resource_group" "lab" {
  name     = "${var.prefix}-rg"
  location = var.location
  tags     = var.tags
}

# =============================================================================
# Virtual Network + Subnets
# =============================================================================

resource "azurerm_virtual_network" "lab" {
  name                = "${var.prefix}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = var.tags
}

resource "azurerm_subnet" "monitoring" {
  name                 = "monitoring-subnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "attack" {
  name                 = "attack-subnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.0.2.0/24"]
}

# =============================================================================
# Network Security Groups
# =============================================================================

resource "azurerm_network_security_group" "management" {
  name                = "${var.prefix}-mgmt-nsg"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  security_rule {
    name                       = "Allow-SSH-Home"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.admin_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTPS-Home"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = var.admin_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-VNET-Inbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

resource "azurerm_network_security_group" "attack" {
  name                = "${var.prefix}-attack-nsg"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  security_rule {
    name                       = "Allow-SSH-Home"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.admin_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-VNET-Inbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

resource "azurerm_subnet_network_security_group_association" "monitoring" {
  subnet_id                 = azurerm_subnet.monitoring.id
  network_security_group_id = azurerm_network_security_group.management.id
}

resource "azurerm_subnet_network_security_group_association" "attack" {
  subnet_id                 = azurerm_subnet.attack.id
  network_security_group_id = azurerm_network_security_group.attack.id
}

# =============================================================================
# Security Onion VM — Marketplace Image
# =============================================================================

resource "azurerm_public_ip" "securityonion" {
  name                = "${var.prefix}-so-pip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "so_mgmt" {
  name                = "${var.prefix}-so-mgmt-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  ip_configuration {
    name                          = "mgmt"
    subnet_id                     = azurerm_subnet.monitoring.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.10"
    public_ip_address_id          = azurerm_public_ip.securityonion.id
    primary                       = true
  }

  tags = var.tags
}

resource "azurerm_network_interface" "so_monitor" {
  name                  = "${var.prefix}-so-monitor-nic"
  location              = azurerm_resource_group.lab.location
  resource_group_name   = azurerm_resource_group.lab.name
  ip_forwarding_enabled = true

  ip_configuration {
    name                          = "monitor"
    subnet_id                     = azurerm_subnet.attack.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.2.10"
  }

  tags = var.tags
}

resource "azurerm_linux_virtual_machine" "securityonion" {
  name                  = "${var.prefix}-securityonion"
  location              = azurerm_resource_group.lab.location
  resource_group_name   = azurerm_resource_group.lab.name
  size                  = var.so_vm_size
  admin_username        = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.so_mgmt.id,
    azurerm_network_interface.so_monitor.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = local.ssh_public_key
  }

  os_disk {
    name                 = "${var.prefix}-so-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 256
  }

  source_image_reference {
    publisher = "securityonionsolutions"
    offer     = "securityonion"
    sku       = "so2"
    version   = var.so_image_version
  }

  plan {
    name      = "so2"
    publisher = "securityonionsolutions"
    product   = "securityonion"
  }

  depends_on = [azurerm_marketplace_agreement.securityonion]

  tags = var.tags
}

# =============================================================================
# Post-Deploy Script — Runs after SO setup wizard completes
# =============================================================================
# This extension runs ONCE after the VM is created. It sets up swap and creates
# a helper script that the user runs AFTER completing the SO setup wizard.
# The helper script fixes: iptables, nginx URL, kratos URL for public IP access.

resource "azurerm_virtual_machine_extension" "so_post_deploy" {
  name                 = "so-post-deploy"
  virtual_machine_id   = azurerm_linux_virtual_machine.securityonion.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.1"

  protected_settings = jsonencode({
    commandToExecute = <<-SCRIPT
      #!/bin/bash
      set -e
      ADMIN_USER="${var.admin_username}"

      # --- 1. Create persistent swap (survives reboots) ---
      if [ ! -f /swapfile ]; then
        fallocate -l 8G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
      fi

      # --- 2. Create post-setup helper script ---
      cat > /home/$ADMIN_USER/so-fix-public-access.sh << 'HELPER'
#!/bin/bash
# Fixes Security Onion for public IP access after setup wizard
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run with sudo: sudo bash $0"
  exit 1
fi

# Get the public IP from Azure metadata
PUBLIC_IP=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2021-02-01&format=text")

if [ -z "$PUBLIC_IP" ]; then
  echo "ERROR: Could not determine public IP from Azure metadata."
  echo "Pass it manually: sudo bash $0 <PUBLIC_IP>"
  exit 1
fi

PRIVATE_IP="10.0.1.10"

echo "============================================="
echo "  SO Public Access Fix"
echo "  Private IP: $PRIVATE_IP"
echo "  Public IP:  $PUBLIC_IP"
echo "============================================="

# Fix nginx URLs
if [ -f /opt/so/conf/nginx/nginx.conf ]; then
  echo "[*] Updating nginx.conf..."
  sed -i "s|$PRIVATE_IP|$PUBLIC_IP|g" /opt/so/conf/nginx/nginx.conf
fi

# Fix Kratos URLs
if [ -f /opt/so/conf/kratos/kratos.yaml ]; then
  echo "[*] Updating kratos.yaml..."
  sed -i "s|$PRIVATE_IP|$PUBLIC_IP|g" /opt/so/conf/kratos/kratos.yaml
fi

# Fix iptables INPUT chain for port 443 and 80
echo "[*] Adding iptables INPUT rules..."
iptables -I INPUT 2 -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
iptables -I INPUT 2 -p tcp --dport 80 -j ACCEPT 2>/dev/null || true

# Persist iptables via cron @reboot
(crontab -l 2>/dev/null | grep -v "iptables.*dport"; echo "@reboot /sbin/iptables -I INPUT 2 -p tcp --dport 443 -j ACCEPT && /sbin/iptables -I INPUT 2 -p tcp --dport 80 -j ACCEPT") | crontab -

# Restart affected containers
echo "[*] Restarting nginx and kratos..."
docker restart so-nginx so-kratos

echo ""
echo "============================================="
echo "  DONE! Access SOC console at:"
echo "  https://$PUBLIC_IP"
echo "  (Accept the self-signed certificate warning)"
echo "============================================="
HELPER

      chmod +x /home/$ADMIN_USER/so-fix-public-access.sh
      chown $ADMIN_USER:$ADMIN_USER /home/$ADMIN_USER/so-fix-public-access.sh

      # --- 3. Create MOTD banner with instructions ---
      cat > /etc/profile.d/so-lab-instructions.sh << 'MOTD'
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Security Onion AI Demo Lab                                 ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║                                                              ║"
echo "║  AFTER SO setup wizard completes, run:                       ║"
echo "║    sudo bash ~/so-fix-public-access.sh                       ║"
echo "║                                                              ║"
echo "║  Then check status:  sudo so-status                          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
MOTD
    SCRIPT
  })

  tags = var.tags
}

# =============================================================================
# Attacker VM
# =============================================================================

resource "azurerm_public_ip" "attacker" {
  name                = "${var.prefix}-attacker-pip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "attacker" {
  name                = "${var.prefix}-attacker-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.attack.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.2.20"
    public_ip_address_id          = azurerm_public_ip.attacker.id
  }

  tags = var.tags
}

resource "azurerm_linux_virtual_machine" "attacker" {
  name                  = "${var.prefix}-attacker"
  location              = azurerm_resource_group.lab.location
  resource_group_name   = azurerm_resource_group.lab.name
  size                  = var.attacker_vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.attacker.id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = local.ssh_public_key
  }

  os_disk {
    name                 = "${var.prefix}-attacker-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 64
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(file("${path.module}/setup_scripts/attacker_cloud_init.yaml"))

  tags = var.tags
}

# =============================================================================
# Victim VM
# =============================================================================

resource "azurerm_public_ip" "victim" {
  name                = "${var.prefix}-victim-pip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "victim" {
  name                = "${var.prefix}-victim-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.attack.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.2.30"
    public_ip_address_id          = azurerm_public_ip.victim.id
  }

  tags = var.tags
}

resource "azurerm_linux_virtual_machine" "victim" {
  name                  = "${var.prefix}-victim"
  location              = azurerm_resource_group.lab.location
  resource_group_name   = azurerm_resource_group.lab.name
  size                  = var.victim_vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.victim.id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = local.ssh_public_key
  }

  os_disk {
    name                 = "${var.prefix}-victim-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 64
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(file("${path.module}/setup_scripts/victim_cloud_init.yaml"))

  tags = var.tags
}

# =============================================================================
# Route Table
# =============================================================================

resource "azurerm_route_table" "victim_to_so" {
  name                = "${var.prefix}-victim-rt"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = var.tags
}

resource "azurerm_route" "victim_default" {
  name                   = "victim-to-so"
  resource_group_name    = azurerm_resource_group.lab.name
  route_table_name       = azurerm_route_table.victim_to_so.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = "10.0.2.10"
}

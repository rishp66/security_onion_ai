output "security_onion" {
  value = {
    public_ip   = azurerm_public_ip.securityonion.ip_address
    private_ip  = "10.0.1.10"
    monitor_ip  = "10.0.2.10"
    ssh_command = "ssh ${var.admin_username}@${azurerm_public_ip.securityonion.ip_address}"
    soc_console = "https://${azurerm_public_ip.securityonion.ip_address}"
  }
}

output "attacker" {
  value = {
    public_ip   = azurerm_public_ip.attacker.ip_address
    private_ip  = "10.0.2.20"
    ssh_command = "ssh ${var.admin_username}@${azurerm_public_ip.attacker.ip_address}"
  }
}

output "victim" {
  value = {
    public_ip   = azurerm_public_ip.victim.ip_address
    private_ip  = "10.0.2.30"
    ssh_command = "ssh ${var.admin_username}@${azurerm_public_ip.victim.ip_address}"
  }
}

output "ssh_private_key" {
  value     = local.ssh_private_key
  sensitive = true
}

output "quick_start" {
  value = <<-EOT

    ══════════════════════════════════════════════════════════
      Security Onion AI Demo Lab — Quick Start
    ══════════════════════════════════════════════════════════

    STEP 1: Save SSH key (if auto-generated)
      terraform output -raw ssh_private_key > ~/.ssh/so-lab-key.pem
      chmod 600 ~/.ssh/so-lab-key.pem

    STEP 2: SSH into Security Onion
      ssh -i ~/.ssh/so-lab-key.pem ${var.admin_username}@${azurerm_public_ip.securityonion.ip_address}
      → Setup wizard launches on first login
      → Choose: STANDALONE, eth0=mgmt, eth1=monitor
      → Set admin email + password
      → Wait 15-30 min for install to complete

    STEP 3: After setup completes, fix public access
      sudo bash ~/so-fix-public-access.sh
      sudo so-status   # verify all green

    STEP 4: Access SOC console
      https://${azurerm_public_ip.securityonion.ip_address}

    STEP 5: Run attacks
      ssh -i ~/.ssh/so-lab-key.pem ${var.admin_username}@${azurerm_public_ip.attacker.ip_address}
      cd ~/attacks && ./run_all.sh

    COST MANAGEMENT:
      Deallocate: az vm deallocate --ids $(az vm list -g ${var.prefix}-rg --query "[].id" -o tsv)
      Restart:    az vm start --ids $(az vm list -g ${var.prefix}-rg --query "[].id" -o tsv)
      Destroy:    terraform destroy

    ══════════════════════════════════════════════════════════

  EOT
}

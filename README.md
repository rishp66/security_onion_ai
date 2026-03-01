# The Intern That Never Sleeps: Putting Security Onion's AI to Work

A Terraform-deployed Azure lab for demonstrating Security Onion's native AI capabilities — AI Summaries, Guided Analysis, Playbooks, and the Onion AI Assistant — using real attack traffic.

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    Azure VNET (10.0.0.0/16)              │
│                                                          │
│  Monitoring Subnet (10.0.1.0/24)                         │
│  ┌─────────────────────────────────┐                     │
│  │  Security Onion (10.0.1.10)    │◄── SSH/HTTPS from    │
│  │  Marketplace Image v2.4.201    │    your IP only      │
│  │  Management NIC (eth0)         │                      │
│  └─────────────────────────────────┘                     │
│                                                          │
│  Attack Subnet (10.0.2.0/24)                             │
│  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐    │
│  │  Attacker    │  │  Victim      │  │ SO Monitor  │    │
│  │  10.0.2.20   │─▶│  10.0.2.30  │  │ NIC (eth1)  │    │
│  │  Nmap, curl  │  │  Apache, SSH │  │ 10.0.2.10   │    │
│  └──────┬───────┘  └──────────────┘  └──────▲──────┘    │
│         │                                    │           │
│         └──── attack.sh targets eth1 ────────┘           │
└──────────────────────────────────────────────────────────┘
```

> **Note:** Azure does not mirror traffic between VMs on the same subnet.
> Attack traffic between the attacker and victim VMs will NOT be seen by
> SO's monitoring interface. To generate Suricata alerts, attacks must be
> directed at SO's monitoring NIC (10.0.2.10) using `attack.sh`.

## Prerequisites

- **Azure subscription** with B-series VM quota (8 vCPUs needed)
- **Terraform** ≥ 1.5.0 — `brew install hashicorp/tap/terraform`
- **Azure CLI** — `brew install azure-cli && az login`

## Deploy (6 Steps)

### 1. Accept Marketplace Terms (one-time)

```bash
az vm image terms accept \
  --publisher securityonionsolutions \
  --offer securityonion \
  --plan so2
```

### 2. Configure

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
```

Set your values in `terraform.tfvars`:

```hcl
subscription_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # az account show --query id -o tsv
admin_cidr      = "YOUR.IP.ADDRESS/32"                     # curl -s ifconfig.me, add /32
```

### 3. Deploy

```bash
terraform init
terraform plan -out=lab.tfplan
terraform apply lab.tfplan
```

If you get a marketplace agreement error, import the existing agreement:

```bash
terraform import azurerm_marketplace_agreement.securityonion \
  "/subscriptions/YOUR-SUB-ID/providers/Microsoft.MarketplaceOrdering/agreements/securityonionsolutions/offers/securityonion/plans/so2"
```

### 4. Save SSH Key (if you didn't provide your own)

```bash
terraform output -raw ssh_private_key > ~/.ssh/so-lab-key.pem
chmod 600 ~/.ssh/so-lab-key.pem
```

### 5. Set Up Security Onion

**Important:** After `terraform apply`, wait 30-40 minutes before SSHing in. The Marketplace image auto-launches the setup wizard on first boot. SSHing in too early can interfere with the setup process.

After waiting, SSH into the SO VM:

```bash
SO_IP=$(terraform output -json security_onion | jq -r '.public_ip')
ssh -i ~/.ssh/so-lab-key.pem -o ServerAliveInterval=60 labadmin@$SO_IP
```

If the setup wizard launches interactively, choose:
- **STANDALONE** mode
- **eth0** for management
- **eth1** for monitoring
- Set your admin email + password

Wait 15-30 minutes for install. If the SSH session times out, just reconnect — the install continues in the background. After install completes:

```bash
# Verify all services are running
sudo so-status

# If Elasticsearch shows "missing", restart it:
sudo docker restart so-elasticsearch
# Wait 60 seconds, then check again:
sudo so-status
```

### 6. Fix Public IP Access

The SOC console defaults to the private IP (`10.0.1.10`). Fix it:

```bash
PUBLIC_IP=<YOUR_SO_PUBLIC_IP>
sudo sed -i "s|10.0.1.10|$PUBLIC_IP|g" /opt/so/conf/nginx/nginx.conf
sudo sed -i "s|10.0.1.10|$PUBLIC_IP|g" /opt/so/conf/kratos/kratos.yaml
sudo iptables -I INPUT 2 -p tcp --dport 443 -j ACCEPT
sudo iptables -I INPUT 2 -p tcp --dport 80 -j ACCEPT
sudo docker restart so-nginx so-kratos
```

To make this permanent (survives Salt highstates), also update the Salt pillar:

```bash
sudo sed -i "s|url_base: '10.0.1.10'|url_base: '$PUBLIC_IP'|g" \
  /opt/so/saltstack/local/pillar/global/soc_global.sls
```

Access the SOC console: `https://<SO_PUBLIC_IP>` in Chrome (accept the self-signed cert warning). Brave browser may not work due to shield/ad-blocking interference with self-signed certs.

## Run Attacks

Attacks must target SO's monitoring NIC (`10.0.2.10`) directly — Azure does not mirror inter-VM traffic to eth1.

```bash
ATTACKER_IP=$(terraform output -json attacker | jq -r '.public_ip')
ssh -i ~/.ssh/so-lab-key.pem labadmin@$ATTACKER_IP

# Run the alert generator (scans, DNS, protocol probes)
sudo bash ~/attacks/attack.sh 10.0.2.10
```

Wait 2-3 minutes after completion, then check the SOC console: Alerts → Last 1 hour → Refresh.

### What `attack.sh` Does

| Stage | Technique | Suricata Rules Triggered |
|-------|-----------|--------------------------|
| 1 - Port Scans | SYN, FIN, XMAS, NULL, ACK, UDP, OS fingerprint | ET SCAN, ET POLICY |
| 2 - Protocol Probes | Telnet, FTP, SMB, SNMP, SSH brute force, RDP | ET FTP, ET POLICY, ET NETBIOS |
| 3 - Malicious DNS | DGA domains, DNS tunneling, TXT C2, zone transfers | ET DNS, Zeek dns.log anomalies |

> **Note:** HTTP-based attacks (SQLi, XSS, Shellshock) require a web server
> listening on the target. Since SO's monitoring NIC is passive, these won't
> generate alerts. Use PCAP imports for HTTP-layer detections if needed:
> `sudo so-import-pcap /path/to/malware.pcap`

## Security Onion AI Features

| Feature | License | What It Does |
|---------|---------|-------------|
| **AI Summaries** | Free | Plain-English summaries of 58,000+ detection rules |
| **Playbooks** | Free | 58,000+ investigation playbooks per rule |
| **Guided Analysis** | Free | Automated investigation questions with inline query results |
| **Onion AI Assistant** | Pro | Conversational LLM that queries your local SO data |
| **MCP Server** | Pro | Connect your own LLM to SO via Model Context Protocol |

## Cost Management

```bash
# Deallocate all VMs (compute stops, disks still charged ~$0.50/day)
az vm deallocate --ids $(az vm list -g so-ai-lab-rg --query "[].id" -o tsv)

# Restart all VMs
az vm start --ids $(az vm list -g so-ai-lab-rg --query "[].id" -o tsv)

# After restart, wait 5-10 min for SO services to come back up:
# ssh in, then: sudo so-status

# Destroy everything
terraform destroy
```

| State | Daily Cost |
|-------|-----------|
| All running | ~$9/day |
| All deallocated | ~$0.50/day |

## Troubleshooting

### Deployment Issues

**Marketplace terms error during `terraform apply`:**
Import the existing agreement into Terraform state:
```bash
terraform import azurerm_marketplace_agreement.securityonion \
  "/subscriptions/YOUR-SUB-ID/providers/Microsoft.MarketplaceOrdering/agreements/securityonionsolutions/offers/securityonion/plans/so2"
```

**Quota errors:**
Check your quota with `az vm list-usage --location eastus -o table`. The lab needs 8 vCPUs of B-series. Request increases in Azure Portal → Quotas if needed.

### SO Setup Issues

**SSH session times out during SO setup:**
The install continues in the background — your SSH session is not required. Reconnect and check progress with `sudo so-status`. Use `ssh -o ServerAliveInterval=60` to prevent future timeouts.

**Setup hangs on "Syncing Repos" or "optional-integrations-load":**
These steps can take 10-30 minutes on a B4ms VM. The repo sync depends on Security Onion's mirror speed. The optional integrations load is non-critical — core services (Suricata, Zeek, Elasticsearch) are typically already running while this step churns. Open a second SSH session and check `sudo so-status`.

**Salt master authentication failures (`Unable to sign_in to master`):**
This is a known race condition in SO's setup script. If setup was auto-launched on first boot, let it retry — it typically resolves itself. If you need to re-run setup manually:
```bash
sudo systemctl stop salt-master salt-minion
sudo rm -rf /etc/salt/pki/master/* /etc/salt/pki/minion/*
sudo systemctl start salt-master
sleep 30
sudo systemctl start salt-minion
sleep 10
sudo salt-key -A -y
sudo salt '*' test.ping   # Should return True
sudo bash /securityonion/setup/so-setup network
```
**Important:** Avoid re-running `so-setup` if the first-boot auto-setup already completed. Re-runs trigger a "reinstall init" that wipes Salt keys and recreates the race condition.

**Elasticsearch shows "missing" in `so-status`:**
Usually caused by memory pressure. The Terraform template creates 8GB swap automatically, but if swap is missing:
```bash
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
sudo docker restart so-elasticsearch
# Wait 60 seconds
sudo so-status
```

### Web Console Access Issues

**Browser redirects to private IP (10.0.1.10):**
SO's nginx and Kratos are configured with the private management IP by default. Fix by rewriting the configs to use the public IP:
```bash
PUBLIC_IP=<YOUR_PUBLIC_IP>
sudo sed -i "s|10.0.1.10|$PUBLIC_IP|g" /opt/so/conf/nginx/nginx.conf
sudo sed -i "s|10.0.1.10|$PUBLIC_IP|g" /opt/so/conf/kratos/kratos.yaml
sudo docker restart so-nginx so-kratos
```
The `so-fix-public-access.sh` helper script (created by Terraform) automates this, but if the Azure metadata endpoint doesn't return the public IP, run the sed commands manually as shown above.

**Connection timed out on port 443:**
SO's host-level firewall (iptables) blocks port 443 by default — the Azure NSG alone is not enough. Add an INPUT rule:
```bash
sudo iptables -I INPUT 2 -p tcp --dport 443 -j ACCEPT
sudo iptables -I INPUT 2 -p tcp --dport 80 -j ACCEPT
```
Persist across reboots:
```bash
(sudo crontab -l 2>/dev/null; echo "@reboot /sbin/iptables -I INPUT 2 -p tcp --dport 443 -j ACCEPT && /sbin/iptables -I INPUT 2 -p tcp --dport 80 -j ACCEPT") | sudo crontab -
```

**SOC console won't load in Brave browser:**
Brave's shields/ad-blocking can interfere with self-signed certificates. Use Chrome or Firefox instead, or disable shields for the SO IP.

**Can't reach SOC console after IP change:**
Your home IP may have changed. Check with `curl -s ifconfig.me`, update `admin_cidr` in `terraform.tfvars`, and run `terraform apply`.

### Post-Restart Issues

**SO services down after VM restart or deallocate/start:**
Services take 5-10 minutes to start after a reboot. Check with `sudo so-status`. If it shows "No highstate has completed since the system was restarted," just wait. The iptables rules do NOT persist across deallocate cycles — you'll need to re-run them. If you updated the Salt pillar `url_base` (see Step 6), nginx/kratos configs will survive highstates, but iptables still needs re-adding:
```bash
sudo iptables -I INPUT 2 -p tcp --dport 443 -j ACCEPT
sudo iptables -I INPUT 2 -p tcp --dport 80 -j ACCEPT
```
If you did NOT update the Salt pillar, you'll also need to re-run the full sed fix:
```bash
PUBLIC_IP=<YOUR_PUBLIC_IP>
sudo sed -i "s|10.0.1.10|$PUBLIC_IP|g" /opt/so/conf/nginx/nginx.conf
sudo sed -i "s|10.0.1.10|$PUBLIC_IP|g" /opt/so/conf/kratos/kratos.yaml
sudo iptables -I INPUT 2 -p tcp --dport 443 -j ACCEPT
sudo iptables -I INPUT 2 -p tcp --dport 80 -j ACCEPT
sudo docker restart so-nginx so-kratos
```

**Password issues:**
Reset with `sudo so-user passwd your-email@example.com`. List users with `sudo so-user list`.

**Attack.sh**

This was an additional file that I created to ensure more alerts were being generated in Security Onion and was not included in part of the Terraform deployment. A challenge for you to is develop your own scripts to see how Security Onion behaves and acts!!

## File Structure

```
security-onion-ai-demo/
├── README.md
├── attack.sh
└── terraform/
    ├── main.tf                          # Azure resources + post-deploy script
    ├── variables.tf                     # Configurable parameters
    ├── outputs.tf                       # Connection info + quick start guide
    ├── terraform.tfvars.example         # Template — copy to terraform.tfvars
    ├── .gitignore
    └── setup_scripts/
        ├── attacker_cloud_init.yaml     # Attack tools + base scripts
        ├── victim_cloud_init.yaml       # Apache + SSH target
```

## 🏆 DEFCON Challenge: Azure Virtual Network TAP

The current setup requires `attack.sh` to target SO's monitoring NIC directly (`10.0.2.10`) because Azure does not mirror traffic between VMs on the same subnet to a third interface. This means attacker→victim traffic is invisible to Security Onion's passive monitoring.

**Your challenge:** Configure [Azure Virtual Network TAP](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-network-tap-overview) so that traffic between the attacker (`10.0.2.20`) and victim (`10.0.2.30`) is mirrored to SO's monitoring NIC (`eth1` / `10.0.2.10`). If done correctly, you can run attacks against the victim VM and have SO detect them passively — just like a real network tap or SPAN port.

Hints:
- Azure Virtual Network TAP is currently in preview and requires registration
- You'll need to configure a TAP on the attacker and/or victim NIC with SO's eth1 as the destination
- The Terraform `azurerm_virtual_network_tap` resource can automate the configuration
- Alternatively, explore running a software tap/bridge on the victim VM that mirrors traffic to eth1

If you get it working, please let me know, I'd love to know how you did it!

## License

MIT

# Peeling Back the Layers of Security: Putting Security Onion's AI to Work

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
│  └──────────────┘  └──────────────┘  └─────────────┘    │
└──────────────────────────────────────────────────────────┘
```

## Prerequisites

- **Azure subscription** with B-series VM quota (8 vCPUs needed)
- **Terraform** ≥ 1.5.0 — `brew install hashicorp/tap/terraform`
- **Azure CLI** — `brew install azure-cli && az login`

## Deploy (5 Steps)

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

SSH into the SO VM — the setup wizard launches on first login:

```bash
SO_IP=$(terraform output -json security_onion | jq -r '.public_ip')
ssh -i ~/.ssh/so-lab-key.pem labadmin@$SO_IP
```

In the wizard, choose:
- **STANDALONE** mode
- **eth0** for management
- **eth1** for monitoring
- Set your admin email + password

Wait 15-30 minutes for install. Elasticsearch may take extra time — if the SSH session times out, just reconnect. After install completes:

```bash
# Verify all services are running
sudo so-status

# If Elasticsearch shows "missing", restart it:
sudo docker restart so-elasticsearch
# Wait 60 seconds, then check again:
sudo so-status

# Fix public IP access (rewrites nginx/kratos URLs + opens firewall)
sudo bash ~/so-fix-public-access.sh
```

Access the SOC console: `https://<SO_PUBLIC_IP>` (accept the self-signed cert warning).

## Run Attacks

```bash
ATTACKER_IP=$(terraform output -json attacker | jq -r '.public_ip')
ssh -i ~/.ssh/so-lab-key.pem labadmin@$ATTACKER_IP

cd ~/attacks
./run_all.sh --dry-run   # Preview what will run
./run_all.sh             # Execute all stages
```

Then check the SOC console for alerts with AI Summaries and Guided Analysis.

## Attack Scripts

| Script | Stage | What SO Detects |
|--------|-------|-----------------|
| `01_recon.sh` | Nmap scans | Scan detection rules, Zeek conn.log patterns |
| `02_malicious_traffic.sh` | DGA DNS + suspicious user-agents | ET sigs, suspicious DNS/HTTP logs |
| `03_c2_beacon.sh` | Self-signed TLS beacon with jitter | Zeek ssl.log, periodic conn.log |
| `04_exfil_sim.sh` | HTTPS exfil + DNS tunneling | Anomalous outbound volume, tunnel patterns |
| `run_all.sh` | Runs all stages | Full kill chain visibility |

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
Services take 5-10 minutes to start after a reboot. Check with `sudo so-status`. If it shows "No highstate has completed since the system was restarted," just wait. The iptables and nginx/kratos URL fixes do NOT persist across deallocate cycles — you'll need to re-run them:
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

## File Structure

```
security-onion-ai-demo/
├── README.md
└── terraform/
    ├── main.tf                          # Azure resources + post-deploy script
    ├── variables.tf                     # Configurable parameters
    ├── outputs.tf                       # Connection info + quick start guide
    ├── terraform.tfvars.example         # Template — copy to terraform.tfvars
    ├── .gitignore
    └── setup_scripts/
        ├── attacker_cloud_init.yaml     # Attack tools + scripts
        └── victim_cloud_init.yaml       # Apache + SSH target
```

## License

MIT
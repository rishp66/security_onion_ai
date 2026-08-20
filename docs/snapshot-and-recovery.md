# Snapshot & Recovery

Manual, human-run steps. Claude Code does not run these — they touch live
Azure infra. This doc exists to turn a bad-day 30-40 min SO reinstall into a
~5 min disk restore, plus a checklist for the routine deallocate/restart
cycle this lab already goes through for cost management.

## VM resource names (confirmed from `terraform/main.tf` and `outputs.tf`)

- Resource group: `so-ai-lab-rg` (from `var.prefix = "so-ai-lab"` + `-rg`)
- SO VM resource: `azurerm_linux_virtual_machine.securityonion`, Azure name
  `so-ai-lab-securityonion`
- SO OS disk name: `so-ai-lab-so-osdisk` (set explicitly in the `os_disk`
  block, `main.tf` ~line 269)

These are derived directly from the Terraform in this repo, not guessed —
if you changed `prefix` in `terraform.tfvars`, substitute your value.

## Take an OS-disk snapshot of the SO VM

Snapshotting the OS disk lets you restore SO to a known-good state (e.g.
right after setup completes and the public-IP fix is applied) without
re-running the 30-40 minute Marketplace install wizard.

```bash
# 1. Look up the OS disk ID (belt-and-suspenders — confirms the disk name
#    above actually matches what's deployed, in case prefix was customized)
DISK_ID=$(az vm show \
  --resource-group so-ai-lab-rg \
  --name so-ai-lab-securityonion \
  --query "storageProfile.osDisk.managedDisk.id" -o tsv)

# 2. Create the snapshot
az snapshot create \
  --resource-group so-ai-lab-rg \
  --source "$DISK_ID" \
  --name so-ai-lab-so-osdisk-snapshot-$(date +%Y%m%d)
```

Take this snapshot once SO is fully set up and the public-IP fix (README
Step 6) is applied — that's the state worth restoring to. A ~5 min restore
beats a ~30-40 min reinstall on talk day.

### Restoring from a snapshot (if the VM is unrecoverable)

```bash
# Create a new managed disk from the snapshot
az disk create \
  --resource-group so-ai-lab-rg \
  --name so-ai-lab-so-osdisk-restored \
  --source so-ai-lab-so-osdisk-snapshot-YYYYMMDD

# Stop the VM, swap the OS disk, restart
az vm deallocate --resource-group so-ai-lab-rg --name so-ai-lab-securityonion
az vm update \
  --resource-group so-ai-lab-rg \
  --name so-ai-lab-securityonion \
  --os-disk so-ai-lab-so-osdisk-restored
az vm start --resource-group so-ai-lab-rg --name so-ai-lab-securityonion
```

After restore, still run the full Post-Restart Issues checklist below —
iptables rules do not survive a disk swap either.

## Deallocate/restart recovery checklist

Copied from README's "Post-Restart Issues" section — reuse these exact,
tested commands. Do not invent new steps.

1. **Wait 5-10 minutes** after start/restart for SO services to come back up.
   Check with `sudo so-status`. If it shows "No highstate has completed
   since the system was restarted," just wait.

2. **iptables rules do NOT persist across deallocate cycles.** Re-add them:
   ```bash
   sudo iptables -I INPUT 2 -p tcp --dport 443 -j ACCEPT
   sudo iptables -I INPUT 2 -p tcp --dport 80 -j ACCEPT
   ```

3. **If Elasticsearch shows "missing" in `so-status`:**
   ```bash
   sudo docker restart so-elasticsearch
   # Wait 60 seconds, then check again:
   sudo so-status
   ```

4. **If the Salt pillar `url_base` was NOT updated (README Step 6, "to make
   this permanent"), also re-run the full sed fix** — nginx/kratos configs
   revert to the private IP on a highstate if the pillar wasn't updated:
   ```bash
   PUBLIC_IP=<YOUR_PUBLIC_IP>
   sudo sed -i "s|10.0.1.10|$PUBLIC_IP|g" /opt/so/conf/nginx/nginx.conf
   sudo sed -i "s|10.0.1.10|$PUBLIC_IP|g" /opt/so/conf/kratos/kratos.yaml
   sudo iptables -I INPUT 2 -p tcp --dport 443 -j ACCEPT
   sudo iptables -I INPUT 2 -p tcp --dport 80 -j ACCEPT
   sudo docker restart so-nginx so-kratos
   ```
   If you DID update the Salt pillar, nginx/kratos survive the highstate —
   only iptables (step 2) still needs re-adding.

5. **Password issues:** reset with `sudo so-user passwd your-email@example.com`.
   List users with `sudo so-user list`.

## New for this branch: confirm the victim's Fleet agent survived

Endpoint telemetry (persistence detection) depends on the victim VM's
Elastic Agent staying enrolled and healthy across restarts — this is a new
failure point that didn't exist before the endpoint telemetry layer.

- After restarting/deallocating the victim VM (10.0.2.30), open the SOC
  console → **Fleet → Agents** and confirm the victim's agent still shows
  **Healthy**, not "Offline" or "Unenrolled."
- If it shows unhealthy, check on the victim VM that the Elastic Agent
  service is running, and re-check network reachability to the SO manager's
  Fleet server (10.0.1.10) — the iptables reset (step 2 above) affects the
  SO manager side, but confirm the victim's own agent connectivity too.
- See `docs/endpoint-telemetry-setup.md` for full enrollment steps if
  re-enrollment is needed.

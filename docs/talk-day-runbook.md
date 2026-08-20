# Talk Day Runbook — DC862, Sept 4

One-page ordered checklist. Manual, human-run — Claude Code does not execute
these steps.

## Before the talk

- [ ] **~3 hours before:** start all VMs.
  ```bash
  az vm start --ids $(az vm list -g so-ai-lab-rg --query "[].id" -o tsv)
  ```
  Wait 5-10 min for SO services to come up (`sudo so-status`).

- [ ] **Re-apply the iptables fix** (does not survive deallocate — see
  `docs/snapshot-and-recovery.md`):
  ```bash
  sudo iptables -I INPUT 2 -p tcp --dport 443 -j ACCEPT
  sudo iptables -I INPUT 2 -p tcp --dport 80 -j ACCEPT
  ```

- [ ] **Confirm the SOC console loads over the public IP** in Chrome or
  Firefox (not Brave): `https://<SO_PUBLIC_IP>`. If it redirects to the
  private IP, re-run the nginx/kratos sed fix from README Step 6 /
  `docs/snapshot-and-recovery.md`.

- [ ] **Confirm the victim's Elastic Agent is healthy:** SOC console →
  Fleet → Agents → victim (10.0.2.30) shows "Healthy."

- [ ] **~20 min before going live:** run persistence stages on the victim.
  ```bash
  ssh -i ~/.ssh/so-lab-key.pem labadmin@<VICTIM_PUBLIC_IP>
  sudo bash persistence.sh
  ```
  Gives events time to index before you query live.

- [ ] **Sanity-check one query from `queries/ground_truth.md`** against the
  live cluster before trusting the AI/MCP layer on stage. Confirm it returns
  the expected hits.

- [ ] **Have a backup demo video ready in a second browser tab**, cued up,
  in case live Elasticsearch/MCP queries stall or the network is flaky at
  the venue.

## After the talk

- [ ] **Deallocate all VMs** to drop cost from ~$9/day to ~$0.50/day (figures
  from README Cost Management):
  ```bash
  az vm deallocate --ids $(az vm list -g so-ai-lab-rg --query "[].id" -o tsv)
  ```

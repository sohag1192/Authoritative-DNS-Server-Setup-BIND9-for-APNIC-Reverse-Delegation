#!/bin/bash
# ==============================================================================
# Script Name: setup_dns.sh
# Description: Automated Authoritative DNS Server Setup (BIND9)
#              Tailored for APNIC /22 IPv4 Reverse DNS Delegation
# Target OS  : Ubuntu 20.04 / 22.04 / 24.04, Debian 11/12
# Author     : Network Automation & DNS Administration
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# 0. Root Permission Check
# ------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
  echo "[-] Error: This script must be run as root. Please use 'sudo ./setup_dns.sh'." >&2
  exit 1
fi

echo "=================================================================="
echo " Starting BIND9 Authoritative Reverse DNS Setup for APNIC /22 Block"
echo "=================================================================="

# ------------------------------------------------------------------------------
# 1. Configuration Parameters
# ------------------------------------------------------------------------------
# Modify these variables to match your network allocation and domain setup:
NS1="dns1.asiannetworkbd.net."
NS2="dns2.asiannetworkbd.net."
ADMIN_EMAIL="root.asiannetworkbd.net."    # DNS SOA contact (root@asiannetworkbd.net)
DOMAIN_SUFFIX="asiannetworkbd.net."       # Target PTR FQDN domain suffix
OCTET1="103"
OCTET2="106"
THIRD_OCTETS=(240 241 242 243)            # The 4 contiguous /24 subnets in the /22
SERIAL=$(date +%Y%m%d01)                  # Serial format: YYYYMMDDNN
ZONES_DIR="/etc/bind/zones"

echo "[i] Nameservers    : $NS1 , $NS2"
echo "[i] Admin Contact  : $ADMIN_EMAIL"
echo "[i] IP Subnet Block: ${OCTET1}.${OCTET2}.[${THIRD_OCTETS[*]}]/24"
echo "[i] Serial Number  : $SERIAL"
echo "------------------------------------------------------------------"

# ------------------------------------------------------------------------------
# 2. Automated Configuration Backup
# ------------------------------------------------------------------------------
BACKUP_DIR="/root/bind-backup-$(date +%Y%m%d-%H%M%S)"
echo "[1/7] Checking for existing BIND configuration and creating backup..."

if [ -d "/etc/bind" ]; then
  mkdir -p "$BACKUP_DIR"
  [ -f /etc/bind/named.conf.options ] && cp -a /etc/bind/named.conf.options "$BACKUP_DIR/"
  [ -f /etc/bind/named.conf.local ] && cp -a /etc/bind/named.conf.local "$BACKUP_DIR/"
  [ -d "$ZONES_DIR" ] && cp -a "$ZONES_DIR" "$BACKUP_DIR/"
  echo "[+] Backup successfully saved to: $BACKUP_DIR"
else
  echo "[i] No existing /etc/bind directory found; fresh installation."
fi

# ------------------------------------------------------------------------------
# 3. Package Installation
# ------------------------------------------------------------------------------
echo "[2/7] Installing BIND9 and DNS troubleshooting utilities..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y

# Ubuntu 24.04 uses bind9-utils, older distributions use bind9utils
APT_PACKAGES=("bind9" "dnsutils" "bind9-doc")
if apt-cache show bind9-utils >/dev/null 2>&1; then
  APT_PACKAGES+=("bind9-utils")
elif apt-cache show bind9utils >/dev/null 2>&1; then
  APT_PACKAGES+=("bind9utils")
fi

apt-get install -y "${APT_PACKAGES[@]}"

# ------------------------------------------------------------------------------
# 4. Configure named.conf.options (Authoritative Only & Security Hardening)
# ------------------------------------------------------------------------------
echo "[3/7] Configuring /etc/bind/named.conf.options..."
cat > /etc/bind/named.conf.options <<'EOF'
options {
    directory "/var/cache/bind";

    // SECURITY: Authoritative-only DNS.
    // Disable recursion to prevent Open Resolver amplification DDoS abuse.
    recursion no;
    allow-query-cache { none; };

    // Zone transfers: blocked globally (allow only to trusted secondary if configured)
    allow-transfer { none; };

    // Public queries must be permitted for APNIC reverse delegation testing & resolvers
    allow-query { any; };

    // Standard DNSSEC validation
    dnssec-validation auto;

    // Listen on all IPv4 and IPv6 interfaces
    listen-on { any; };
    listen-on-v6 { any; };
};
EOF

# ------------------------------------------------------------------------------
# 5. Configure named.conf.local (Zone Declarations)
# ------------------------------------------------------------------------------
echo "[4/7] Configuring /etc/bind/named.conf.local..."
cat > /etc/bind/named.conf.local <<EOF
// =============================================================================
// APNIC /22 Reverse DNS Zones (${OCTET1}.${OCTET2}.240.0/22)
// Published across 4 standard /24 octet boundaries
// =============================================================================
EOF

for octet in "${THIRD_OCTETS[@]}"; do
  ZONE_NAME="${octet}.${OCTET2}.${OCTET1}.in-addr.arpa"
  ZONE_FILE="${ZONES_DIR}/db.${ZONE_NAME}"

  cat >> /etc/bind/named.conf.local <<EOF
zone "${ZONE_NAME}" {
    type master;
    file "${ZONE_FILE}";
    allow-update { none; };
    allow-query { any; };
};

EOF
done

# ------------------------------------------------------------------------------
# 6. Create Zone Files with SOA, NS & $GENERATE PTR Records
# ------------------------------------------------------------------------------
echo "[5/7] Generating reverse zone files with SOA and PTR records..."
mkdir -p "$ZONES_DIR"

for octet in "${THIRD_OCTETS[@]}"; do
  ZONE_NAME="${octet}.${OCTET2}.${OCTET1}.in-addr.arpa"
  ZONE_FILE="${ZONES_DIR}/db.${ZONE_NAME}"

  cat > "$ZONE_FILE" <<EOF
\$TTL 86400
@   IN  SOA ${NS1} ${ADMIN_EMAIL} (
            ${SERIAL}   ; Serial (YYYYMMDDNN)
            3600         ; Refresh (1 hour)
            240          ; Retry (4 mins - RFC/APNIC recommended)
            1209600      ; Expire (2 weeks)
            86400 )      ; Minimum / Negative Cache TTL
;
; Authoritative Name Servers
@   IN  NS  ${NS1}
@   IN  NS  ${NS2}

;
; Reverse PTR Records (${OCTET1}.${OCTET2}.${octet}.0/24)
; Generates PTR for 0 through 255. Note the required trailing FQDN dot.
\$GENERATE 0-255 \$ PTR ${OCTET1}-${OCTET2}-${octet}-\$-${DOMAIN_SUFFIX}
EOF

  echo "[+] Generated zone file: $ZONE_FILE"
done

# Ensure correct BIND ownership and file permissions
chown -R bind:bind "$ZONES_DIR"
chmod 755 "$ZONES_DIR"
chmod 644 "$ZONES_DIR"/*

# ------------------------------------------------------------------------------
# 7. Configure Firewall (UFW)
# ------------------------------------------------------------------------------
echo "[6/7] Configuring UFW firewall rules for DNS (Port 53 TCP & UDP)..."
if command -v ufw >/dev/null 2>&1; then
  ufw allow 53/tcp comment "BIND9 DNS TCP" || true
  ufw allow 53/udp comment "BIND9 DNS UDP" || true
  if ufw status | grep -qw "active"; then
    ufw reload || true
  fi
  echo "[+] UFW port 53 rules applied."
else
  echo "[i] UFW not installed or active; make sure Port 53 (UDP & TCP) is open in your cloud provider firewall."
fi

# ------------------------------------------------------------------------------
# 8. Syntax Validation & Service Restart
# ------------------------------------------------------------------------------
echo "[7/7] Validating BIND9 configuration and zone files..."

# Main configuration check
if ! named-checkconf /etc/bind/named.conf; then
  echo "[-] ERROR: named-checkconf failed! Please inspect syntax errors above." >&2
  exit 1
fi

named-checkconf -z /etc/bind/named.conf

# Individual zone file validation
for octet in "${THIRD_OCTETS[@]}"; do
  ZONE_NAME="${octet}.${OCTET2}.${OCTET1}.in-addr.arpa"
  ZONE_FILE="${ZONES_DIR}/db.${ZONE_NAME}"
  echo "[*] Checking zone: $ZONE_NAME"
  if ! named-checkzone "$ZONE_NAME" "$ZONE_FILE"; then
    echo "[-] ERROR: Zone validation failed for $ZONE_NAME!" >&2
    exit 1
  fi
done

# Determine service name (bind9 vs named)
SERVICE_NAME="bind9"
if systemctl list-unit-files | grep -qw "bind9.service"; then
  SERVICE_NAME="bind9"
elif systemctl list-unit-files | grep -qw "named.service"; then
  SERVICE_NAME="named"
fi

echo "[*] Restarting $SERVICE_NAME service..."
systemctl restart "$SERVICE_NAME"
systemctl enable "$SERVICE_NAME"

echo ""
echo "=================================================================="
echo " SUCCESS: BIND9 Authoritative Reverse DNS Setup Complete!"
echo "=================================================================="
systemctl status "$SERVICE_NAME" --no-pager | grep -E "Active:|Loaded:" || true

echo ""
echo "Quick Local Verification:"
echo "------------------------------------------------------------------"
if command -v dig >/dev/null 2>&1; then
  FIRST_OCTET="${THIRD_OCTETS[0]}"
  echo "[Query SOA]: dig @127.0.0.1 +norecurse ${FIRST_OCTET}.${OCTET2}.${OCTET1}.in-addr.arpa SOA +short"
  dig @127.0.0.1 +norecurse "${FIRST_OCTET}.${OCTET2}.${OCTET1}.in-addr.arpa" SOA +short || true
  
  echo "[Query PTR]: dig @127.0.0.1 +norecurse -x ${OCTET1}.${OCTET2}.${FIRST_OCTET}.2 +short"
  dig @127.0.0.1 +norecurse -x "${OCTET1}.${OCTET2}.${FIRST_OCTET}.2" +short || true
fi

echo ""
echo "[i] Next Steps:"
echo "  1. Run './test_dns.sh' to perform full UDP, TCP, SOA, and PTR verification."
echo "  2. Confirm your forward nameserver A records point to your public IP:"
echo "       ${NS1} -> <Your Server Public IP>"
echo "       ${NS2} -> <Your Server Public IP>"
echo "  3. Log in to MyAPNIC and submit reverse delegation for each /24 zone."
echo "  4. In case of issues, restore your backup from: $BACKUP_DIR"
echo "=================================================================="

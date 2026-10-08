#!/bin/bash
# ==============================================================================
# Script Name: rollback.sh
# Description: Restores BIND9 configuration from a previous backup
# Usage      : ./rollback.sh [/path/to/bind-backup-dir]
# ==============================================================================

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "[-] Error: Please run this script as root (use sudo)." >&2
  exit 1
fi

# Locate backup directory
if [ -n "${1:-}" ]; then
  BACKUP_DIR="$1"
else
  # Find latest backup in /root
  LATEST_BACKUP=$(ls -td /root/bind-backup-* 2>/dev/null | head -n 1 || true)
  if [ -z "$LATEST_BACKUP" ]; then
    echo "[-] Error: No backup directories found in /root/bind-backup-*." >&2
    echo "    Please specify the backup path: ./rollback.sh /path/to/backup" >&2
    exit 1
  fi
  BACKUP_DIR="$LATEST_BACKUP"
fi

echo "=================================================================="
echo " BIND9 Configuration Rollback Utility"
echo "=================================================================="
echo "Restoring from: $BACKUP_DIR"

if [ ! -d "$BACKUP_DIR" ]; then
  echo "[-] Error: Target backup directory does not exist: $BACKUP_DIR" >&2
  exit 1
fi

echo "[1/4] Restoring configuration files..."
if [ -f "$BACKUP_DIR/named.conf.local" ]; then
  cp -a "$BACKUP_DIR/named.conf.local" /etc/bind/named.conf.local
  echo "[+] Restored /etc/bind/named.conf.local"
fi

if [ -f "$BACKUP_DIR/named.conf.options" ]; then
  cp -a "$BACKUP_DIR/named.conf.options" /etc/bind/named.conf.options
  echo "[+] Restored /etc/bind/named.conf.options"
fi

if [ -d "$BACKUP_DIR/zones" ]; then
  mkdir -p /etc/bind/zones
  cp -a "$BACKUP_DIR/zones/"* /etc/bind/zones/
  chown -R bind:bind /etc/bind/zones
  echo "[+] Restored /etc/bind/zones"
fi

echo "[2/4] Validating restored configuration syntax..."
named-checkconf /etc/bind/named.conf
named-checkconf -z /etc/bind/named.conf

SERVICE="bind9"
systemctl list-unit-files | grep -qw "named.service" && SERVICE="named"

echo "[3/4] Reloading/Restarting service ($SERVICE)..."
if command -v rndc >/dev/null 2>&1 && rndc status >/dev/null 2>&1; then
  rndc reconfig
  rndc reload
else
  systemctl restart "$SERVICE"
fi

echo "[4/4] Verifying status..."
systemctl is-active "$SERVICE"

echo "=================================================================="
echo " Rollback completed successfully!"
echo "=================================================================="

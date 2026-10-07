
# 🌐 Authoritative DNS Server Setup (BIND9) for APNIC Reverse Delegation

This repository/guide provides a complete setup for configuring an authoritative DNS server using **BIND9** on Ubuntu/Debian. It is specifically tailored for ISPs and Network Operators needing to set up **APNIC Reverse DNS Delegations** (e.g., for a `/22` or `/24` IPv4 block) and standard Forward DNS Zones.

## 📋 Table of Contents
- [Prerequisites](#prerequisites)
- [Automated Installation (Bash Script)](#automated-installation)
- [Manual Configuration Guide](#manual-configuration-guide)
  - [1. Global Options](#1-global-options)
  - [2. Reverse DNS (PTR) Zones](#2-reverse-dns-ptr-zones)
  - [3. Forward DNS (A/NS) Zone](#3-forward-dns-ans-zone)
- [Firewall Rules (UFW)](#firewall-rules)
- [Testing & Validation](#testing--validation)
- [MyAPNIC Delegation Submission](#myapnic-delegation-submission)

---

## 🛠 Prerequisites
- **OS:** Ubuntu 20.04 / 22.04 / 24.04 or Debian.
- **Access:** `root` or `sudo` privileges.
- **IP Block:** An assigned APNIC IPv4 block (e.g., `103.106.240.0/22`).
- **Domain:** A registered domain for name servers (e.g., `asiannetworkbd.net`).

---

## 🚀 Automated Installation

You can use the provided bash script to automatically install BIND9, configure the global options, and generate the reverse zone files for a `/22` block.

1. Create the script file:
   ```bash
   nano setup_dns.sh

```

2. Paste the automation script (ensure variables like `NS1`, `NS2`, and block ranges are correctly set).
3. Make it executable and run:
```bash
chmod +x setup_dns.sh
sudo ./setup_dns.sh

```



---

## ⚙️ Manual Configuration Guide

If you prefer manual setup, follow these steps:

### 1. Global Options

Edit `/etc/bind/named.conf.options`:

```text
options {
    directory "/var/cache/bind";
    recursion no;               # Disable recursion for authoritative servers
    allow-transfer { none; };   # Disable zone transfers for security
    allow-query { any; };       # Allow public queries (required by APNIC)
    dnssec-validation auto;
    listen-on-v6 { any; };
};

```

### 2. Reverse DNS (PTR) Zones

For a `/22` block (e.g., `103.106.240.0/22`), declare four `/24` zones in `/etc/bind/named.conf.local`:

```text
zone "240.106.103.in-addr.arpa" { type master; file "/etc/bind/zones/db.103.106.240"; };
zone "241.106.103.in-addr.arpa" { type master; file "/etc/bind/zones/db.103.106.241"; };
zone "242.106.103.in-addr.arpa" { type master; file "/etc/bind/zones/db.103.106.242"; };
zone "243.106.103.in-addr.arpa" { type master; file "/etc/bind/zones/db.103.106.243"; };

```

Create the zone files in `/etc/bind/zones/` and define your PTR records.

### 3. Forward DNS (A/NS) Zone

To resolve your own name servers, create a forward zone.
Add to `named.conf.local`:

```text
zone "asiannetworkbd.net" {
    type master;
    file "/etc/bind/zones/db.asiannetworkbd";
};

```

Edit `/etc/bind/zones/db.asiannetworkbd`:

```text
$TTL 86400
@ IN SOA dns1.asiannetworkbd.net. admin.asiannetworkbd.net. (
        2026100701 ; Serial
        3600       ; Refresh
        240        ; Retry
        1209600    ; Expire
        86400 )    ; Minimum TTL

; Name Servers
@ IN NS dns1.asiannetworkbd.net.
@ IN NS dns2.asiannetworkbd.net.

; A Records
@    IN A 103.106.243.111
dns1 IN A 103.106.243.111
dns2 IN A 103.106.243.111
www  IN A 103.106.243.111

```

---

## 🛡 Firewall Rules

APNIC requires DNS servers to communicate over **Port 53 (TCP & UDP)**.

```bash
sudo ufw allow 53/tcp
sudo ufw allow 53/udp
sudo ufw reload

```

---

## ✅ Testing & Validation

Always check your syntax before restarting the service to prevent downtime.

**1. Check main configuration syntax:**

```bash
sudo named-checkconf

```

**2. Check reverse and forward zone syntax:**

```bash
sudo named-checkzone 240.106.103.in-addr.arpa /etc/bind/zones/db.103.106.240
sudo named-checkzone asiannetworkbd.net /etc/bind/zones/db.asiannetworkbd

```

**3. Restart Service:**

```bash
sudo systemctl restart named
sudo systemctl enable named
sudo systemctl status named

```

**4. Local Query Test:**

```bash
dig @localhost -x 103.106.240.1
dig @localhost dns1.asiannetworkbd.net

```

---

## 🌐 MyAPNIC Delegation Submission

Once the server is running and returning `NOERROR` for local queries:

1. Log in to [MyAPNIC](https://myapnic.net/).
2. Navigate to **Resource Manager > Reverse DNS Delegations > Add Reverse Delegations**.
3. Since APNIC accepts `/24` boundaries, submit 4 separate requests for your `/22` block:
* `103.106.240.0/24`
* `103.106.241.0/24`
* `103.106.242.0/24`
* `103.106.243.0/24`


4. Set **Name Server 1** to `dns1.asiannetworkbd.net` and **Name Server 2** to `dns2.asiannetworkbd.net`.
5. Submit. Wait up to 2 hours for `ns.apnic.net` to reload.
6. Verify globally: `dig +trace -x 103.106.240.1`

---

*Created for Network Automation & DNS Administration.*

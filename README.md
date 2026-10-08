# 🌐 Authoritative DNS Server Setup (BIND9) for APNIC Reverse Delegation

*Bilingual Guide: [English](#-english-version) | [বাংলা (Bengali)](#-বাংলা-সংস্করণ-bengali-version)*

---

## 🇺🇸 English Version

This repository provides an enterprise-ready, automated and manual guide for deploying an authoritative DNS server using **BIND9** on Ubuntu/Debian (including Ubuntu 20.04, 22.04, and 24.04 LTS).

It is specifically designed for ISPs, Telcos, and Network Operators managing **APNIC IPv4 Reverse DNS Delegations** (such as a `/22` block spanning four `/24` subnets, e.g., `103.106.240.0/22`) and standard forward DNS resolution.

---

### 📋 Table of Contents
- [Architecture & Reverse Mapping Overview](#-architecture--reverse-mapping-overview)
- [Prerequisites](#-prerequisites)
- [Automated Deployment (`setup_dns.sh`)](#-automated-deployment-setup_dnssh)
- [Verification & APNIC Readiness (`test_dns.sh`)](#-verification--apnic-readiness-test_dnssh)
- [Configuration Backup & Rollback (`rollback.sh`)](#-configuration-backup--rollback-rollbacksh)
- [Manual Configuration Guide](#-manual-configuration-guide)
  - [1. Hardened Global Options (`named.conf.options`)](#1-hardened-global-options-namedconfoptions)
  - [2. Reverse Zone Declarations (`named.conf.local`)](#2-reverse-zone-declarations-namedconflocal)
  - [3. Zone Files & Automated `$GENERATE` PTR Records](#3-zone-files--automated-generate-ptr-records)
  - [4. Forward DNS Nameserver Records (Glue/A Records)](#4-forward-dns-nameserver-records-gluea-records)
- [Firewall Rules (UFW & Cloud Security Groups)](#-firewall-rules-ufw--cloud-security-groups)
- [MyAPNIC Delegation Workflow & Test All](#-myapnic-delegation-workflow--test-all)
- [Troubleshooting & Common Pitfalls](#-troubleshooting--common-pitfalls)

---

### 🗺 Architecture & Reverse Mapping Overview

APNIC delegates IPv4 reverse DNS on octet (`/24`) boundaries. If you hold a `/22` block (1,024 IPs), reverse delegation requires declaring **four `/24` reverse zones** in BIND9 and submitting each zone individually in the MyAPNIC portal.

Reverse DNS queries reverse the IP octets and append `.in-addr.arpa`:
- IP `103.106.240.2` queries `2.240.106.103.in-addr.arpa`

| IPv4 Range | BIND Zone Name | Zone File Location |
| :--- | :--- | :--- |
| `103.106.240.0/24` | `240.106.103.in-addr.arpa` | `/etc/bind/zones/db.240.106.103.in-addr.arpa` |
| `103.106.241.0/24` | `241.106.103.in-addr.arpa` | `/etc/bind/zones/db.241.106.103.in-addr.arpa` |
| `103.106.242.0/24` | `242.106.103.in-addr.arpa` | `/etc/bind/zones/db.242.106.103.in-addr.arpa` |
| `103.106.243.0/24` | `243.106.103.in-addr.arpa` | `/etc/bind/zones/db.243.106.103.in-addr.arpa` |

---

### 🛠 Prerequisites

- **Operating System:** Ubuntu 20.04 / 22.04 / 24.04 LTS or Debian 11 / 12.
- **Privileges:** `root` or `sudo` access.
- **IP Allocation:** Assigned APNIC IPv4 block (e.g., `103.106.240.0/22`).
- **Domain Name:** Registered parent domain for your authoritative nameservers (e.g., `asiannetworkbd.net`).
- **Port 53:** TCP and UDP port 53 open to the Internet.

---

### 🚀 Automated Deployment (`setup_dns.sh`)

The repository includes a production-grade setup script [`setup_dns.sh`](setup_dns.sh) that:
1. Backs up existing BIND configurations to `/root/bind-backup-<timestamp>`.
2. Installs required packages (`bind9`, `bind9-utils`, `dnsutils`).
3. Applies a hardened, authoritative-only `named.conf.options` (disabling open recursion).
4. Generates `/etc/bind/named.conf.local` with all four `/24` zone blocks.
5. Populates zone files with standard SOA, NS, and dynamic `$GENERATE` PTR records.
6. Opens UFW firewall ports 53 TCP/UDP.
7. Validates syntax via `named-checkconf` and `named-checkzone` before starting the service.

#### How to run:
```bash
git clone https://github.com/sohag-rana/Authoritative-DNS-Server-Setup-BIND9-for-APNIC-Reverse-Delegation.git
cd Authoritative-DNS-Server-Setup-BIND9-for-APNIC-Reverse-Delegation

# Review/edit variables inside setup_dns.sh (NS1, NS2, Subnets, etc.)
chmod +x setup_dns.sh test_dns.sh rollback.sh

# Execute installation
sudo ./setup_dns.sh
```

---

### 🔍 Verification & APNIC Readiness (`test_dns.sh`)

Before submitting your nameservers to MyAPNIC, execute [`test_dns.sh`](test_dns.sh) to confirm compliance:

```bash
# Test locally:
sudo ./test_dns.sh

# Or test against the public IP:
./test_dns.sh 103.106.243.111
```

The test script audits:
- [x] BIND9 system service is active and running
- [x] Port 53 listening on both UDP and TCP
- [x] Authoritative Answer flag (`aa`) returned in SOA responses
- [x] NS records match both `NS1` and `NS2` exactly
- [x] PTR generation pattern matches expected FQDN (e.g. `103-106-240-2-asiannetworkbd.net.`)
- [x] TCP Port 53 queries succeed (strictly required by APNIC Test All)
- [x] Open recursion is securely blocked (external queries return `REFUSED`)

---

### 🔄 Configuration Backup & Rollback (`rollback.sh`)

Whenever you run [`setup_dns.sh`](setup_dns.sh), a full configuration snapshot is preserved in `/root/bind-backup-YYYYMMDD-HHMMSS`. 

To immediately revert to the latest known-good configuration:
```bash
# Revert to the latest backup:
sudo ./rollback.sh

# Or revert to a specific backup directory:
sudo ./rollback.sh /root/bind-backup-20261007-080617
```

---

### ⚙️ Manual Configuration Guide

If configuring manually, adhere to the following configurations:

#### 1. Hardened Global Options (`named.conf.options`)
Edit `/etc/bind/named.conf.options`:

```text
options {
    directory "/var/cache/bind";

    // Authoritative Only: Disable recursion to prevent Open Resolver amplification attacks
    recursion no;
    allow-query-cache { none; };

    // Prevent unauthorized zone transfers (AXFR)
    allow-transfer { none; };

    // Allow public queries so APNIC checks and external resolvers can query PTRs
    allow-query { any; };

    dnssec-validation auto;

    listen-on { any; };
    listen-on-v6 { any; };
};
```

#### 2. Reverse Zone Declarations (`named.conf.local`)
Add the four zones to `/etc/bind/named.conf.local`:

```text
zone "240.106.103.in-addr.arpa" {
    type master;
    file "/etc/bind/zones/db.240.106.103.in-addr.arpa";
    allow-update { none; };
    allow-query { any; };
};

zone "241.106.103.in-addr.arpa" {
    type master;
    file "/etc/bind/zones/db.241.106.103.in-addr.arpa";
    allow-update { none; };
    allow-query { any; };
};

zone "242.106.103.in-addr.arpa" {
    type master;
    file "/etc/bind/zones/db.242.106.103.in-addr.arpa";
    allow-update { none; };
    allow-query { any; };
};

zone "243.106.103.in-addr.arpa" {
    type master;
    file "/etc/bind/zones/db.243.106.103.in-addr.arpa";
    allow-update { none; };
    allow-query { any; };
};
```

#### 3. Zone Files & Automated `$GENERATE` PTR Records
Create `/etc/bind/zones/db.240.106.103.in-addr.arpa`:

```text
$TTL 86400
@   IN  SOA dns1.asiannetworkbd.net. root.asiannetworkbd.net. (
            2026100703   ; Serial: YYYYMMDDNN (Must be incremented on changes)
            3600         ; Refresh (1 hour)
            240          ; Retry (4 minutes - RFC/APNIC recommended)
            1209600      ; Expire (2 weeks)
            86400 )      ; Minimum / Negative Cache TTL

; Authoritative Name Servers
@   IN  NS  dns1.asiannetworkbd.net.
@   IN  NS  dns2.asiannetworkbd.net.

; Automated PTR Generation
; Generates records for 0 through 255. Note the required trailing FQDN dot (.)
$GENERATE 0-255 $ PTR 103-106-240-$-asiannetworkbd.net.
```

> [!IMPORTANT]
> - Always append a trailing dot (`.`) to the target domain name in PTR records (e.g. `...asiannetworkbd.net.`). Otherwise, BIND will append the zone origin!
> - The SOA serial must increment on every modification (e.g. `YYYYMMDD01` -> `YYYYMMDD02`).
> - Repeat this for `db.241.106.103.in-addr.arpa`, `db.242.106.103.in-addr.arpa`, and `db.243.106.103.in-addr.arpa`.

#### 4. Forward DNS Nameserver Records (Glue/A Records)
At your authoritative domain DNS provider (e.g., Cloudflare, Route53, or cPanel):
- Create `A` record for `dns1.asiannetworkbd.net` pointing to `103.106.243.111`.
- Create `A` record for `dns2.asiannetworkbd.net` pointing to `103.106.243.111` (or your secondary server IP).
- **Cloudflare Warning:** Ensure the proxy is **DISABLED** (Set to **DNS Only / Gray Cloud**). APNIC cannot test nameservers through Cloudflare CDN HTTP proxy.
- **IPv6 Caution:** Do **not** add `AAAA` records unless native IPv6 connectivity is configured and working on port 53.

---

### 🛡 Firewall Rules (UFW & Cloud Security Groups)

APNIC and recursive resolvers validate nameservers over both **UDP and TCP Port 53**:

```bash
sudo ufw allow 53/tcp comment "DNS TCP"
sudo ufw allow 53/udp comment "DNS UDP"
sudo ufw reload
```

If hosted in AWS, Azure, DigitalOcean, or an upstream ISP data center, verify inbound Port 53 TCP and UDP are allowed in the external Security Group / edge firewall.

---

### 🌐 MyAPNIC Delegation Workflow & Test All

Once all local and public tests pass:

1. Log in to [MyAPNIC](https://myapnic.net/).
2. Navigate to: **Resource Manager** ➔ **Reverse DNS Delegations** ➔ **Add Reverse Delegations**.
3. For your `/22` block, submit **4 separate requests** corresponding to each `/24`:
   - `103.106.240.0/24`
   - `103.106.241.0/24`
   - `103.106.242.0/24`
   - `103.106.243.0/24`
4. In the nameserver fields, specify:
   - **Name Server 1:** `dns1.asiannetworkbd.net`
   - **Name Server 2:** `dns2.asiannetworkbd.net`
5. Click **Test All**.
6. If the test passes, click **Submit**.
7. Allow up to 2 hours for APNIC root nameservers (`ns.apnic.net`) to refresh.

---

### 🚨 Troubleshooting & Common Pitfalls

| Symptom | Primary Causes | Diagnostic & Fix |
| :--- | :--- | :--- |
| **SERVFAIL** | Syntax error in zone files or inaccessible forwarder | Run `named-checkconf -z` and check `journalctl -u bind9 -n 80 --no-pager`. Avoid upstream conditional forwarders without valid resolvers. |
| **No SOA RR** | Zone not loaded or missing authoritative answer | Test `dig @localhost <zone> SOA`. Ensure the `aa` (Authoritative Answer) flag is present. |
| **NS RR mismatch** | Zone file NS records do not match MyAPNIC NS entries | Verify that `@ IN NS` in all zone files exactly match the hostnames entered in MyAPNIC. |
| **Server Timeout** | Port 53 blocked by firewall or BIND not bound | Check `ss -lntup \| grep ':53'`. Check UFW status (`ufw status`) and hosting cloud provider security groups for UDP/TCP 53. |
| **PTR Name Missing / Bad Domain** | Missing trailing dot in `$GENERATE` directive | Ensure `$GENERATE` PTR record ends with a dot (`.`): `...asiannetworkbd.net.`. |
| **Local Query OK, but APNIC Test Fails** | Nameserver public A records unresolved or TCP 53 closed | Test `dig +tcp @<public_ip> <zone> SOA`. Check public glue records with `dig @1.1.1.1 dns1.yourdomain.com A`. |

---
---

## 🇧🇩 বাংলা সংস্করণ (Bengali Version)

এই গাইডটিতে Ubuntu/Debian সার্ভারে (Ubuntu 20.04 / 22.04 / 24.04 LTS) BIND9 ব্যবহার করে একটি সম্পূর্ণ সিকিউরড ও অথরিটেটিভ রিভার্স ডিএনএস (Reverse DNS - rDNS) সার্ভার সেটআপের অটোমেটেড ও ম্যানুয়াল পদ্ধতি বিস্তারিতভাবে উপস্থাপন করা হয়েছে।

এটি মূলত আইএসপি (ISP), টেলকো এবং নেটওয়ার্ক ইঞ্জিনিয়ারদের জন্য প্রস্তুতকৃত, যাদের APNIC থেকে প্রাপ্ত IPv4 ব্লকের (যেমন: `103.106.240.0/22`) জন্য রিভার্স ডেলিগেশন কনফিগার করতে হয়।

---

### 📋 সূচিপত্র
- [আর্কিটেকচার ও রিভার্স ম্যাপিং পরিচিতি](#-আর্কিটেকচার-ও-রিভার্স-ম্যাপিং-পরিচিতি)
- [পূর্বশর্ত (Prerequisites)](#-পূর্বশর্ত-prerequisites-1)
- [অটোমেটেড ইন্সটলেশন স্ক্রিপ্ট (`setup_dns.sh`)](#-অটোমেটেড-ইন্সটলেশন-স্ক্রিপ্ট-setup_dnssh)
- [যাচাইকরণ ও টেস্ট স্ক্রিপ্ট (`test_dns.sh`)](#-যাচাইকরণ-ও-টেস্ট-স্ক্রিপ্ট-test_dnssh)
- [কনফিগারেশন ব্যাকআপ ও রোলব্যাক (`rollback.sh`)](#-কনফিগারেশন-ব্যাকআপ-ও-রোলব্যাক-rollbacksh)
- [ম্যানুয়াল কনফিগারেশন গাইড](#-ম্যানুয়াল-কনফিগারেশন-গাইড-1)
  - [১. সিকিউর গ্লোবাল অপশনস (`named.conf.options`)](#১-সিকিউর-গ্লোবাল-অপশনস-namedconfoptions)
  - [২. জোন ডিক্লারেশন (`named.conf.local`)](#২-জোন-ডিক্লারেশন-namedconflocal)
  - [৩. জোন ফাইল ও `$GENERATE` দিয়ে অটো PTR রেকর্ড](#৩-জোন-ফাইল-ও-generate-দিয়ে-অটো-ptr-রেকর্ড)
  - [৪. ফরোয়ার্ড ডিএনএস নেমসার্ভার A রেকর্ডস](#৪-ফরোয়ার্ড-ডিএনএস-নেমসার্ভার-a-রেকর্ডস)
- [ফায়ারওয়াল রুলস (UFW & Cloud Security Group)](#-ফায়ারওয়াল-রুলস-ufw--cloud-security-group)
- [MyAPNIC ডেলিগেশন ও Test All সাবমিশন](#-myapnic-ডেলিগেশন-ও-test-all-সাবমিশন)
- [সাধারণ সমস্যা ও সমাধান (Troubleshooting)](#-সাধারণ-সমস্যা-ও-সমাধান-troubleshooting)

---

### 🗺 আর্কিটেকচার ও রিভার্স ম্যাপিং পরিচিতি

APNIC-এর রিভার্স ডিএনএস ডেলিগেশন অক্টেট সীমানায় (`/24`) কাজ করে। আপনার যদি একটি `/22` আইপি ব্লক (১০২৪টি আইপি) থাকে, তবে APNIC-এ সাবমিট করার জন্য BIND9-এ **চারটি `/24` রিভার্স জোন** তৈরি করতে হবে।

রিভার্স কোয়েরিতে আইপি অ্যাড্রেস উল্টোভাবে লেখা হয় এবং শেষে `.in-addr.arpa` যুক্ত হয়:
- `103.106.240.2` আইপির জন্য কোয়েরি নেম হবে: `2.240.106.103.in-addr.arpa`

| IPv4 রেঞ্জ | BIND জোন নাম | জোন ফাইল লোকেশন |
| :--- | :--- | :--- |
| `103.106.240.0/24` | `240.106.103.in-addr.arpa` | `/etc/bind/zones/db.240.106.103.in-addr.arpa` |
| `103.106.241.0/24` | `241.106.103.in-addr.arpa` | `/etc/bind/zones/db.241.106.103.in-addr.arpa` |
| `103.106.242.0/24` | `242.106.103.in-addr.arpa` | `/etc/bind/zones/db.242.106.103.in-addr.arpa` |
| `103.106.243.0/24` | `243.106.103.in-addr.arpa` | `/etc/bind/zones/db.243.106.103.in-addr.arpa` |

---

### 🛠 পূর্বশর্ত (Prerequisites)

- **অপারেটিং সিস্টেম:** Ubuntu 20.04 / 22.04 / 24.04 LTS অথবা Debian 11 / 12।
- **পারমিশন:** `root` অথবা `sudo` অ্যাক্সেস।
- **আইপি ব্লক:** APNIC বরাদ্দকৃত IPv4 ব্লক (যেমন: `103.106.240.0/22`)।
- **ডোমেন নেম:** নেমসার্ভারের জন্য রেজিস্টার্ড ডোমেন (যেমন: `asiannetworkbd.net`)।
- **পোর্ট ৫৩:** UDP এবং TCP উভয় প্রোটোকলে পোর্ট ৫৩ উন্মুক্ত থাকতে হবে।

---

### 🚀 অটোমেটেড ইন্সটলেশন স্ক্রিপ্ট (`setup_dns.sh`)

এই রিপোজিটরিতে সম্পূর্ণ অটোমেটেড এবং প্রোডাকশন-রেডি স্ক্রিপ্ট [`setup_dns.sh`](setup_dns.sh) যুক্ত করা হয়েছে:
1. সার্ভারের বর্তমান BIND কনফিগারেশন স্বয়ংক্রিয়ভাবে `/root/bind-backup-<timestamp>`-এ ব্যাকআপ নেয়।
2. প্রয়োজনীয় প্যাকেজ (`bind9`, `bind9-utils`, `dnsutils`) ইনস্টল করে।
3. ওপেন রিকার্সন বন্ধ করে সিকিউরড অথরিটেটিভ অপশন কনফিগার করে।
4. চারটি `/24` জোনের জন্য `named.conf.local` এবং জোন ফাইল তৈরি করে।
5. `$GENERATE` ব্যবহার করে ১ ক্লিকেই ২৫৬টি করে মোট ১০২৪টি PTR রেকর্ড তৈরি করে দেয়।
6. UFW ফায়ারওয়ালে পোর্ট ৫৩ (TCP ও UDP) অনুমোদন দেয়।
7. `named-checkconf` ও `named-checkzone` দিয়ে নির্ভুলতা যাচাইয়ের পর সার্ভিস রিস্টার্ট করে।

#### ব্যবহারের নিয়ম:
```bash
git clone https://github.com/sohag-rana/Authoritative-DNS-Server-Setup-BIND9-for-APNIC-Reverse-Delegation.git
cd Authoritative-DNS-Server-Setup-BIND9-for-APNIC-Reverse-Delegation

# প্রয়োজনে setup_dns.sh এডিটর দিয়ে খুলে ডোমেন ও আইপি ভেরিয়েবল চেক করুন
chmod +x setup_dns.sh test_dns.sh rollback.sh

# স্ক্রিপ্টটি চালান
sudo ./setup_dns.sh
```

---

### 🔍 যাচাইকরণ ও টেস্ট স্ক্রিপ্ট (`test_dns.sh`)

MyAPNIC-এ ডেলিগেশন সাবমিট করার পূর্বে সম্পূর্ণ সার্ভার কনফিগারেশন অডিট করতে [`test_dns.sh`](test_dns.sh) রান করুন:

```bash
# লোকাল সার্ভার টেস্ট:
sudo ./test_dns.sh

# অথবা পাবলিক আইপি দিয়ে টেস্ট:
./test_dns.sh 103.106.243.111
```

এই টেস্ট স্ক্রিপ্টটি যাচাই করে:
- [x] BIND9 সার্ভিস সচল আছে কিনা
- [x] UDP ও TCP উভয় পোর্ট ৫৩-তে লিসেন করছে কিনা
- [x] SOA রেসপন্সে Authoritative Answer (`aa` ফ্ল্যাগ) আছে কিনা
- [x] NS রেকর্ড সঠিক নেমসার্ভারের সাথে মিলছে কিনা
- [x] `$GENERATE` তৈরি করা PTR রেকর্ড সঠিক প্যাটার্নে আসছে কিনা
- [x] TCP পোর্ট ৫৩ কোয়েরি সফল হচ্ছে কিনা (APNIC-এর কঠোর শর্ত)
- [x] ওপেন রিকার্সন ব্লক করা আছে কিনা (বহিরাগত ডোমেন কোয়েরিতে `REFUSED` দিচ্ছে কিনা)

---

### 🔄 কনফিগারেশন ব্যাকআপ ও রোলব্যাক (`rollback.sh`)

[`setup_dns.sh`](setup_dns.sh) চালানোর সময় স্বয়ংক্রিয়ভাবে একটি ব্যাকআপ তৈরি হয়। কোনো কারণে আগের অবস্থায় ফিরে যেতে চাইলে ব্যবহার করুন:

```bash
# সর্বশেষ ব্যাকআপে ফিরে যেতে:
sudo ./rollback.sh

# অথবা নির্দিষ্ট ব্যাকআপ ফোল্ডার থেকে রিস্টোর করতে:
sudo ./rollback.sh /root/bind-backup-20261007-080617
```

---

### ⚙️ ম্যানুয়াল কনফিগারেশন গাইড

#### ১. সিকিউর গ্লোবাল অপশনস (`named.conf.options`)
`/etc/bind/named.conf.options` এডিট করুন:

```text
options {
    directory "/var/cache/bind";

    // অথরিটেটিভ সার্ভারে রিকার্সন বন্ধ রাখুন (DDoS ওপেন রিজলভার আক্রমণ প্রতিরোধে)
    recursion no;
    allow-query-cache { none; };

    // অননুমোদিত জোন ট্রান্সফার বন্ধ রাখুন
    allow-transfer { none; };

    // APNIC ও সাধারণ পাবলিক রিজলভারের জন্য কোয়েরি ওপেন রাখুন
    allow-query { any; };

    dnssec-validation auto;

    listen-on { any; };
    listen-on-v6 { any; };
};
```

#### ২. জোন ডিক্লারেশন (`named.conf.local`)
`/etc/bind/named.conf.local` ফাইলে ৪টি জোন যুক্ত করুন:

```text
zone "240.106.103.in-addr.arpa" {
    type master;
    file "/etc/bind/zones/db.240.106.103.in-addr.arpa";
    allow-update { none; };
    allow-query { any; };
};

zone "241.106.103.in-addr.arpa" {
    type master;
    file "/etc/bind/zones/db.241.106.103.in-addr.arpa";
    allow-update { none; };
    allow-query { any; };
};

zone "242.106.103.in-addr.arpa" {
    type master;
    file "/etc/bind/zones/db.242.106.103.in-addr.arpa";
    allow-update { none; };
    allow-query { any; };
};

zone "243.106.103.in-addr.arpa" {
    type master;
    file "/etc/bind/zones/db.243.106.103.in-addr.arpa";
    allow-update { none; };
    allow-query { any; };
};
```

#### ৩. জোন ফাইল ও `$GENERATE` দিয়ে অটো PTR রেকর্ড
`/etc/bind/zones/db.240.106.103.in-addr.arpa` ফাইলটি তৈরি করুন:

```text
$TTL 86400
@   IN  SOA dns1.asiannetworkbd.net. root.asiannetworkbd.net. (
            2026100703   ; Serial: YYYYMMDDNN (প্রতি আপডেটে মান বাড়াতে হবে)
            3600         ; Refresh (১ ঘণ্টা)
            240          ; Retry (৪ মিনিট - RFC/APNIC মান)
            1209600      ; Expire (২ সপ্তাহ)
            86400 )      ; Minimum / Negative Cache TTL

; নেমসার্ভার রেকর্ডস
@   IN  NS  dns1.asiannetworkbd.net.
@   IN  NS  dns2.asiannetworkbd.net.

; অটোমেটিক PTR জেনারেশন (০ থেকে ২৫৫ পর্যন্ত)
; লক্ষ্য করুন: FQDN-এর শেষে অবশ্যই ডট (.) দিতে হবে
$GENERATE 0-255 $ PTR 103-106-240-$-asiannetworkbd.net.
```

> [!WARNING]
> PTR রেকর্ডের শেষে অবশ্যই ডট (`.`) দিন (যেমন: `...asiannetworkbd.net.`)। ডট না দিলে BIND তার নিজের জোনের নাম শেষে যুক্ত করে ফেলবে এবং PTR নষ্ট হয়ে যাবে।

একইভাবে `db.241...`, `db.242...`, এবং `db.243...` ফাইলগুলো তৈরি করুন।

#### ৪. ফরোয়ার্ড ডিএনএস নেমসার্ভার A রেকর্ডস
আপনার মূল ডোমেনের DNS ম্যানেজমেন্টে (যেমন Cloudflare):
- `dns1.asiannetworkbd.net` এর `A` রেকর্ড দিন আপনার সার্ভারের পাবলিক আইপিতে (`103.106.243.111`)।
- `dns2.asiannetworkbd.net` এর `A` রেকর্ড দিন দ্বিতীয় নেমসার্ভার আইপিতে।
- **Cloudflare সতর্কতা:** প্রক্সি অবশ্যই **বন্ধ (DNS Only - Gray Cloud)** রাখতে হবে। প্রক্সি অন থাকলে APNIC নেমসার্ভার খুঁজে পাবে না।
- IPv6 রুট না থাকলে কোনো ভুয়া `AAAA` রেকর্ড দিবেন না।

---

### 🛡 ফায়ারওয়াল রুলস (UFW & Cloud Security Group)

```bash
sudo ufw allow 53/tcp comment "BIND9 TCP"
sudo ufw allow 53/udp comment "BIND9 UDP"
sudo ufw reload
```

হোস্টিং প্রোভাইডারের ক্লাউড ফায়ারওয়াল বা সিকিউরিটি গ্রুপেও পোর্ট ৫৩ TCP এবং UDP ইনবাউন্ড ওপেন থাকতে হবে।

---

### 🌐 MyAPNIC ডেলিগেশন ও Test All সাবমিশন

১. [MyAPNIC](https://myapnic.net/) পোর্টালে লগইন করুন।
2. মেন্যু থেকে: **Resource Manager** ➔ **Reverse DNS Delegations** ➔ **Add Reverse Delegations**-এ যান।
3. আপনার `/22` ব্লকের জন্য ৪টি আলাদা `/24` রিকোয়েস্ট দিন:
   - `103.106.240.0/24`
   - `103.106.241.0/24`
   - `103.106.242.0/24`
   - `103.106.243.0/24`
4. নেমসার্ভার ঘরে দিন:
   - **Name Server 1:** `dns1.asiannetworkbd.net`
   - **Name Server 2:** `dns2.asiannetworkbd.net`
5. **Test All** বাটনে ক্লিক করুন।
6. টেস্ট সবুজ হলে **Submit** করুন।
7. APNIC রুট সার্ভার রিফ্রেশ হতে প্রায় ১ থেকে ২ ঘণ্টা সময় লাগতে পারে।

---

### 🚨 সাধারণ সমস্যা ও সমাধান (Troubleshooting)

| লক্ষণ | মূল কারণ | সমাধান ও পরীক্ষা |
| :--- | :--- | :--- |
| **SERVFAIL** | জোন ফাইলে ভুল সিনট্যাক্স বা নষ্ট ফরওয়ার্ডার | `named-checkconf -z` এবং `journalctl -u bind9 -n 80` দেখুন। ডাউন থাকা কোনো সার্ভারকে ফরওয়ার্ডার বানাবেন না। |
| **No SOA RR** | জোন ফাইল লোড হয়নি বা অথরিটেটিভ অ্যান্সার নেই | `dig @localhost <zone> SOA` চেক করুন। রেসপন্সে `aa` ফ্ল্যাগ আছে কিনা দেখুন। |
| **NS RR mismatch** | জোন ফাইলের NS নামের সাথে MyAPNIC-এর নামের গরমিল | জোন ফাইলের `@ IN NS` এবং MyAPNIC-এ দেওয়া নাম হুবহু এক হতে হবে। |
| **Server Timeout** | ফায়ারওয়ালে পোর্ট ৫৩ বন্ধ | `ss -lntup \| grep ':53'` দিয়ে লিসেনার চেক করুন। UFW ও ক্লাউড সিকিউরিটি গ্রুপে UDP/TCP 53 চেক করুন। |
| **PTR নাম আসে না** | `$GENERATE` লাইনে ডট বাদ পড়েছে | নিশ্চিত করুন PTR-এর শেষে ডট আছে (`...asiannetworkbd.net.`)। |
| **লোকাল টেস্ট ওকে কিন্তু APNIC ফেইল** | নেমসার্ভার ডোমেনের A রেকর্ড নেই বা TCP 53 বন্ধ | `dig +tcp @<public_ip> <zone> SOA` দিয়ে TCP পোর্ট চেক করুন। `dig @1.1.1.1 dns1.example.com` দিয়ে ডোমেন রেজোলিউশন চেক করুন। |

---

*Created for Network Automation & DNS Administration.*

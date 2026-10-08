#!/bin/bash
# ==============================================================================
# Script Name: test_dns.sh
# Description: Authoritative DNS Verification & APNIC Readiness Test Script
# Usage      : ./test_dns.sh [SERVER_IP]
# ==============================================================================

set -uo pipefail

SERVER_IP="${1:-127.0.0.1}"
PUBLIC_SERVER_IP="103.106.243.111"
NS1="dns1.asiannetworkbd.net."
NS2="dns2.asiannetworkbd.net."
OCTETS=(240 241 242 243)
SAMPLE_PTR_IP="103.106.240.2"
EXPECTED_PTR="103-106-240-2-asiannetworkbd.net."

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=================================================================="
echo -e "${BLUE}  Authoritative BIND9 & APNIC Delegation Test Suite${NC}"
echo "=================================================================="
echo "Testing Target IP : $SERVER_IP"
echo "Public Server IP  : $PUBLIC_SERVER_IP"
echo "Expected Nameservers: $NS1 , $NS2"
echo "------------------------------------------------------------------"

PASS_COUNT=0
FAIL_COUNT=0

check_result() {
  local title="$1"
  local status="$2"
  local details="$3"

  if [ "$status" -eq 0 ]; then
    echo -e "[ ${GREEN}PASS${NC} ] $title"
    ((PASS_COUNT++))
  else
    echo -e "[ ${RED}FAIL${NC} ] $title"
    echo -e "       ${YELLOW}Reason/Output:${NC} $details"
    ((FAIL_COUNT++))
  fi
}

# 1. Check Service Status (if running locally)
if command -v systemctl >/dev/null 2>&1; then
  SERVICE="bind9"
  systemctl is-active --quiet bind9 || SERVICE="named"
  if systemctl is-active --quiet "$SERVICE"; then
    check_result "Local BIND Service ($SERVICE) is ACTIVE" 0 ""
  else
    check_result "Local BIND Service is ACTIVE" 1 "Service $SERVICE is not running"
  fi
fi

# 2. Check Port 53 Listening (UDP & TCP)
if command -v ss >/dev/null 2>&1; then
  UDP_LISTEN=$(ss -lntu | grep ':53 ' | grep -c 'udp' || true)
  TCP_LISTEN=$(ss -lntu | grep ':53 ' | grep -c 'tcp' || true)
  if [ "$UDP_LISTEN" -gt 0 ] && [ "$TCP_LISTEN" -gt 0 ]; then
    check_result "Port 53 listeners (Both UDP & TCP active)" 0 ""
  else
    check_result "Port 53 listeners (Both UDP & TCP active)" 1 "UDP: $UDP_LISTEN, TCP: $TCP_LISTEN"
  fi
fi

# 3. Test Local Authoritative Answer (aa flag) for each reverse zone
echo ""
echo -e "${BLUE}Testing Reverse Zones on Target IP ($SERVER_IP)...${NC}"

for octet in "${OCTETS[@]}"; do
  ZONE="${octet}.106.103.in-addr.arpa"
  RES=$(dig @"$SERVER_IP" +norecurse "$ZONE" SOA 2>&1)
  
  if echo "$RES" | grep -q "status: NOERROR" && echo "$RES" | grep -q "flags:.*aa.*"; then
    SOA_RECORD=$(echo "$RES" | awk '/;; ANSWER SECTION:/{getline; print}')
    check_result "Zone $ZONE SOA returned with Authoritative Answer (aa flag)" 0 ""
  else
    STATUS=$(echo "$RES" | awk -F', ' '/status:/{print $2}' || echo "No response")
    check_result "Zone $ZONE SOA query" 1 "Status: $STATUS (Missing aa flag or NOERROR)"
  fi
done

# 4. Test NS Records on Reverse Zone
ZONE="240.106.103.in-addr.arpa"
NS_RES=$(dig @"$SERVER_IP" +norecurse "$ZONE" NS +short)
if echo "$NS_RES" | grep -q "dns1.asiannetworkbd.net" && echo "$NS_RES" | grep -q "dns2.asiannetworkbd.net"; then
  check_result "Zone $ZONE NS records match both $NS1 and $NS2" 0 ""
else
  check_result "Zone $ZONE NS records match expected nameservers" 1 "Returned: $NS_RES"
fi

# 5. Test Reverse PTR Generation Pattern
echo ""
echo -e "${BLUE}Testing Reverse PTR Resolution Pattern...${NC}"
PTR_RES=$(dig @"$SERVER_IP" +norecurse -x "$SAMPLE_PTR_IP" +short | sed 's/\.$//')
CLEAN_EXPECTED=$(echo "$EXPECTED_PTR" | sed 's/\.$//')

if [ "$PTR_RES" = "$CLEAN_EXPECTED" ]; then
  check_result "PTR for $SAMPLE_PTR_IP matches pattern ($PTR_RES)" 0 ""
else
  check_result "PTR for $SAMPLE_PTR_IP matches pattern" 1 "Expected: $CLEAN_EXPECTED, Got: $PTR_RES"
fi

# 6. Test TCP Port 53 Query Support (Required by APNIC)
echo ""
echo -e "${BLUE}Testing TCP Port 53 Protocol Support...${NC}"
TCP_RES=$(dig +tcp @"$SERVER_IP" +norecurse "$ZONE" SOA 2>&1)
if echo "$TCP_RES" | grep -q "status: NOERROR"; then
  check_result "TCP Port 53 query succeeded (status: NOERROR)" 0 ""
else
  check_result "TCP Port 53 query succeeded" 1 "TCP query failed or timed out"
fi

# 7. Security Hardening Check: Recursion Prevention (Not an Open Resolver)
echo ""
echo -e "${BLUE}Testing Security: Recursion Hardening...${NC}"
REC_RES=$(dig @"$SERVER_IP" google.com A +time=2 +tries=1 2>&1)
if echo "$REC_RES" | grep -qE "status: REFUSED|status: SERVFAIL" || ! echo "$REC_RES" | grep -q "status: NOERROR"; then
  check_result "Open Recursion is securely blocked (Server refuses external domain recursion)" 0 ""
else
  check_result "Open Recursion check" 1 "WARNING: Server answered recursion query for google.com! Open resolver risk."
fi

# 8. External / Remote Public Test (if public IP is accessible)
if [ "$SERVER_IP" != "$PUBLIC_SERVER_IP" ] && [ "$SERVER_IP" = "127.0.0.1" ]; then
  echo ""
  echo -e "${BLUE}Testing Public IP Binding ($PUBLIC_SERVER_IP)...${NC}"
  PUB_RES=$(dig @"$PUBLIC_SERVER_IP" +norecurse "$ZONE" SOA +time=2 +tries=1 2>&1 || true)
  if echo "$PUB_RES" | grep -q "status: NOERROR"; then
    check_result "Public IP $PUBLIC_SERVER_IP is accessible and answering queries" 0 ""
  else
    echo -e "[ ${YELLOW}INFO${NC} ] Public IP test failed or blocked by external firewall. Make sure Port 53 UDP/TCP is open to WAN."
  fi
fi

echo ""
echo "=================================================================="
echo -e "Test Summary: ${GREEN}$PASS_COUNT Passed${NC}, ${RED}$FAIL_COUNT Failed${NC}"
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo -e "${GREEN}✓ All checks passed! The server is ready for APNIC Reverse Delegation submission.${NC}"
else
  echo -e "${RED}✗ Some tests failed. Please review the errors and check logs with 'journalctl -u bind9 -n 50'.${NC}"
fi
echo "=================================================================="

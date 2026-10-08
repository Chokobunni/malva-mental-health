#!/bin/bash
echo "=== MX malva.web.id ==="
for ip in $(dig +short A ns1.idwebhost.id | sort -u) $(dig +short A ns2.idwebhost.id | sort -u); do
  echo "--- $ip"
  dig @"$ip" MX malva.web.id +short +time=3 +tries=1 | tr '\n' ' '
  echo
done
echo "=== DKIM (zoho._domainkey) ==="
dig TXT zoho._domainkey.malva.web.id +short +time=3 +tries=1
echo "=== semua TXT root ==="
dig TXT malva.web.id +short +time=3 +tries=1
echo "=== A root & www ==="
dig A malva.web.id +short +time=3 +tries=1
dig A www.malva.web.id +short +time=3 +tries=1

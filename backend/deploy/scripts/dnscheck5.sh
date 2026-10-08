#!/bin/bash
echo "=== Selector zoho._domainkey ==="
dig TXT zoho._domainkey.malva.web.id +short +time=3 +tries=1
echo "=== Selector default (zmail/zoho) ==="
dig TXT zmail._domainkey.malva.web.id +short +time=3 +tries=1
echo "=== Coba selector zb36179906 (dari verifikasi) ==="
dig TXT zb36179906._domainkey.malva.web.id +short +time=3 +tries=1
echo "=== Semua TXT yang berakhiran _domainkey (scan 3 selector umum) ==="
for sel in default dkim1 zoho1 mail; do
  echo -n "$sel._domainkey: "
  dig TXT "$sel._domainkey.malva.web.id" +short +time=3 +tries=1 | head -c 100
  echo
done
echo "=== MX & SPF (regresi) ==="
dig MX malva.web.id +short +time=3 +tries=1
dig TXT malva.web.id +short +time=3 +tries=1

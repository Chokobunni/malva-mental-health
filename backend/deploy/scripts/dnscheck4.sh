#!/bin/bash
echo "=== SPF (TXT root) ==="
dig TXT malva.web.id +short +time=3 +tries=1
echo "=== MX ==="
dig MX malva.web.id +short +time=3 +tries=1
echo "=== DKIM zoho._domainkey ==="
dig TXT zoho._domainkey.malva.web.id +short +time=3 +tries=1
echo "=== DMARC _dmarc ==="
dig TXT _dmarc.malva.web.id +short +time=3 +tries=1

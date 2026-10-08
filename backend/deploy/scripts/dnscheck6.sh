#!/bin/bash
echo "=== DMARC _dmarc.malva.web.id ==="
dig TXT _dmarc.malva.web.id +short +time=3 +tries=1
echo "=== Ringkasan semua record email ==="
echo -n "MX : "; dig MX malva.web.id +short +time=3 +tries=1 | tr '\n' ' '; echo
echo -n "SPF: "; dig TXT malva.web.id +short +time=3 +tries=1 | grep spf1
echo -n "DKIM: "; dig TXT zmail._domainkey.malva.web.id +short +time=3 +tries=1 | head -c 60; echo "..."
echo -n "DMARC: "; dig TXT _dmarc.malva.web.id +short +time=3 +tries=1

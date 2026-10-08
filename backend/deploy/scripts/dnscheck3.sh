#!/bin/bash
echo "=== A api.malva.web.id per-IP ==="
for ip in 103.30.147.9 203.161.184.96 202.52.146.225 203.161.184.82; do
  echo -n "$ip: "
  dig @"$ip" A api.malva.web.id +short +time=3 +tries=1 | tr '\n' ' '
  echo
done
echo "=== A root & www (regresi) ==="
dig A malva.web.id +short +time=3 +tries=1
dig A www.malva.web.id +short +time=3 +tries=1
echo "=== MX (regresi) ==="
dig MX malva.web.id +short +time=3 +tries=1
echo "=== TXT root (regresi) ==="
dig TXT malva.web.id +short +time=3 +tries=1

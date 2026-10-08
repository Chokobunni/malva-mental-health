#!/bin/bash
echo "=== Per-IP check ns1 ==="
for ip in $(dig +short A ns1.idwebhost.id | sort -u); do
  echo "--- $ip"
  echo -n "SOA: "
  dig @"$ip" SOA malva.web.id +short | head -1
  echo -n "TXT: "
  dig @"$ip" TXT malva.web.id +short | tr '\n' ' '
  echo
  echo -n "A root: "
  dig @"$ip" A malva.web.id +short | tr '\n' ' '
  echo
  echo -n "A api: "
  dig @"$ip" A api.malva.web.id +short | tr '\n' ' '
  echo
done
echo "=== Per-IP check ns2 ==="
for ip in $(dig +short A ns2.idwebhost.id | sort -u); do
  echo "--- $ip"
  echo -n "SOA: "
  dig @"$ip" SOA malva.web.id +short | head -1
  echo -n "TXT: "
  dig @"$ip" TXT malva.web.id +short | tr '\n' ' '
  echo
done

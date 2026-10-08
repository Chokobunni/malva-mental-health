#!/bin/bash
echo "=== healthz via localhost (backend langsung) ==="
curl -s http://127.0.0.1:8080/healthz --max-time 10
echo
echo "=== healthz via https api.malva.web.id (dari VM) ==="
curl -sv https://api.malva.web.id/healthz --max-time 10 2>&1 | grep -E "HTTP|Connected|SSL|error" | head -8
echo "=== systemd malva-api ==="
systemctl status malva-api --no-pager -n 5 | head -12
echo "=== port listen ==="
ss -tlnp 2>/dev/null | grep -E ':8080|:443|:80 ' | head -5

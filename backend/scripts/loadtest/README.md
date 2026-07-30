# Load Testing Scripts

This directory contains k6 load testing scripts for the Malva API.

## Prerequisites

Install k6:
```bash
# Windows (Chocolatey)
choco install k6

# macOS
brew install k6

# Linux
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D68
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update && sudo apt-get install k6
```

## Scripts

### load-test.js
Basic load test with user registration, login, and CRUD operations.

```bash
k6 run scripts/loadtest/load-test.js
```

### api-load-test.js
Comprehensive API load test with multiple scenarios:
- Smoke test (5 VUs, 1 minute)
- Load test (50-100 VUs, 16 minutes)
- Stress test (50-100 requests/second, 16 minutes)

```bash
k6 run scripts/loadtest/api-load-test.js
```

### security-test.js
Security-focused tests including:
- Brute force attack simulation
- SQL injection attempts
- XSS attack attempts
- Path traversal attempts
- Rate limit testing

```bash
k6 run scripts/loadtest/security-test.js
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MALVA_API_BASE_URL` | `http://localhost:8080` | API base URL |

## Running with Custom Configuration

```bash
# Custom VUs and duration
k6 run --vus 50 --duration 5m scripts/loadtest/load-test.js

# Custom base URL
k6 run -e MALVA_API_BASE_URL=https://api.malva.app scripts/loadtest/load-test.js

# Output results to JSON
k6 run --out json=results.json scripts/loadtest/load-test.js

# Output results to InfluxDB
k6 run --out influxdb=http://localhost:8086/k6 scripts/loadtest/load-test.js
```

## Thresholds

All scripts include performance thresholds:
- `http_req_duration`: 95th percentile < 500ms
- `http_req_failed`: Error rate < 5%
- Security tests: Block rate > 90%

## Interpreting Results

Key metrics to monitor:
- `http_req_duration`: Request latency
- `http_req_failed`: Failed requests
- `iterations`: Number of test iterations
- `vus`: Virtual users active
- `data_received`: Data downloaded
- `data_sent`: Data uploaded

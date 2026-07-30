import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

const errorRate = new Rate('errors');
const apiDuration = new Trend('api_duration');
const requestCount = new Counter('total_requests');

const BASE_URL = __ENV.MALVA_API_BASE_URL || 'http://localhost:8080';

export const options = {
  scenarios: {
    smoke: {
      executor: 'constant-vus',
      vus: 5,
      duration: '1m',
    },
    load: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 50 },
        { duration: '5m', target: 50 },
        { duration: '2m', target: 100 },
        { duration: '5m', target: 100 },
        { duration: '2m', target: 0 },
      ],
      startTime: '2m',
    },
    stress: {
      executor: 'ramping-arrival-rate',
      startRate: 10,
      timeUnit: '1s',
      preAllocatedVUs: 50,
      maxVUs: 200,
      stages: [
        { duration: '2m', target: 50 },
        { duration: '5m', target: 50 },
        { duration: '2m', target: 100 },
        { duration: '5m', target: 100 },
        { duration: '2m', target: 0 },
      ],
      startTime: '16m',
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    http_req_failed: ['rate<0.05'],
    errors: ['rate<0.05'],
    api_duration: ['p(95)<300'],
  },
};

function makeRequest(method, path, body, token) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }

  const start = Date.now();
  let res;

  if (method === 'GET') {
    res = http.get(`${BASE_URL}${path}`, { headers });
  } else {
    res = http.post(`${BASE_URL}${path}`, JSON.stringify(body), { headers });
  }

  apiDuration.add(Date.now() - start);
  requestCount.add(1);

  return res;
}

export default function () {
  const email = `perf_${__VU}_${__ITER}@malva.app`;
  const password = 'PerfTest123!@#';

  const regRes = makeRequest('POST', '/v1/auth/register', {
    email: email,
    password: password,
    display_name: 'Performance Test',
    role: 'patient',
  });

  check(regRes, {
    'register success': (r) => r.status === 201 || r.status === 400,
  });

  const loginRes = makeRequest('POST', '/v1/auth/login', {
    email: email,
    password: password,
  });

  check(loginRes, {
    'login success': (r) => r.status === 200,
  }) || errorRate.add(1);

  if (loginRes.status !== 200) {
    sleep(1);
    return;
  }

  const token = JSON.parse(loginRes.body).access_token;

  const meRes = makeRequest('GET', '/v1/me', null, token);
  check(meRes, {
    'me success': (r) => r.status === 200,
  }) || errorRate.add(1);

  const screeningsRes = makeRequest('GET', '/v1/screenings?limit=5', null, token);
  check(screeningsRes, {
    'screenings success': (r) => r.status === 200,
  }) || errorRate.add(1);

  const moodsRes = makeRequest('GET', '/v1/mood-checkins?limit=10', null, token);
  check(moodsRes, {
    'moods success': (r) => r.status === 200,
  }) || errorRate.add(1);

  const diariesRes = makeRequest('GET', '/v1/diary-entries?limit=10', null, token);
  check(diariesRes, {
    'diaries success': (r) => r.status === 200,
  }) || errorRate.add(1);

  const medsRes = makeRequest('GET', '/v1/medications?limit=10', null, token);
  check(medsRes, {
    'medications success': (r) => r.status === 200,
  }) || errorRate.add(1);

  const notifsRes = makeRequest('GET', '/v1/notifications?limit=10', null, token);
  check(notifsRes, {
    'notifications success': (r) => r.status === 200,
  }) || errorRate.add(1);

  sleep(Math.random() * 2 + 1);
}

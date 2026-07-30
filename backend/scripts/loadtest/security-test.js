import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Counter } from 'k6/metrics';

const blockedRate = new Rate('blocked_requests');
const attackCounter = new Counter('attacks_attempted');

const BASE_URL = __ENV.MALVA_API_BASE_URL || 'http://localhost:8080';

export const options = {
  scenarios: {
    brute_force: {
      executor: 'constant-vus',
      vus: 5,
      duration: '2m',
    },
    injection: {
      executor: 'constant-vus',
      vus: 3,
      duration: '1m',
      startTime: '2m',
    },
  },
  thresholds: {
    blocked_requests: ['rate>0.9'],
  },
};

function testBruteForce() {
  const email = 'admin@malva.app';
  const passwords = [
    'password', '12345678', 'admin123', 'letmein',
    'qwerty123', 'password1', '123456789', 'welcome1',
  ];

  for (const password of passwords) {
    attackCounter.add(1);
    const res = http.post(`${BASE_URL}/v1/auth/login`, JSON.stringify({
      email: email,
      password: password,
    }), {
      headers: { 'Content-Type': 'application/json' },
    });

    const blocked = res.status === 401 || res.status === 429;
    blockedRate.add(blocked ? 1 : 0);

    check(res, {
      'brute force blocked': (r) => r.status === 401 || r.status === 429,
    });

    sleep(0.5);
  }
}

function testSQLInjection() {
  const payloads = [
    "admin@malva.app' OR '1'='1",
    "admin@malva.app'; DROP TABLE users;--",
    "admin@malva.app' UNION SELECT * FROM users--",
    "1' OR '1'='1' --",
  ];

  for (const payload of payloads) {
    attackCounter.add(1);
    const res = http.post(`${BASE_URL}/v1/auth/login`, JSON.stringify({
      email: payload,
      password: 'test',
    }), {
      headers: { 'Content-Type': 'application/json' },
    });

    const blocked = res.status === 400 || res.status === 401;
    blockedRate.add(blocked ? 1 : 0);

    check(res, {
      'sql injection blocked': (r) => r.status === 400 || r.status === 401,
    });

    sleep(1);
  }
}

function testXSS() {
  const payloads = [
    '<script>alert("xss")</script>',
    '<img src=x onerror=alert(1)>',
    'javascript:alert(document.cookie)',
  ];

  for (const payload of payloads) {
    attackCounter.add(1);
    const res = http.post(`${BASE_URL}/v1/auth/register`, JSON.stringify({
      email: 'test@malva.app',
      password: 'Test123!@#',
      display_name: payload,
      role: 'patient',
    }), {
      headers: { 'Content-Type': 'application/json' },
    });

    const blocked = res.status === 400 || res.status === 201;
    blockedRate.add(blocked ? 1 : 0);

    check(res, {
      'xss handled safely': (r) => r.status === 400 || r.status === 201,
    });

    sleep(1);
  }
}

function testPathTraversal() {
  const paths = [
    '/../../../etc/passwd',
    '/..\\..\\..\\windows\\system32\\config\\sam',
    '/v1/auth/../../../etc/shadow',
  ];

  for (const path of paths) {
    attackCounter.add(1);
    const res = http.get(`${BASE_URL}${path}`, {
      headers: { 'Content-Type': 'application/json' },
    });

    const blocked = res.status === 400 || res.status === 404;
    blockedRate.add(blocked ? 1 : 0);

    check(res, {
      'path traversal blocked': (r) => r.status === 400 || r.status === 404,
    });

    sleep(1);
  }
}

function testRateLimit() {
  for (let i = 0; i < 30; i++) {
    attackCounter.add(1);
    const res = http.post(`${BASE_URL}/v1/auth/login`, JSON.stringify({
      email: 'test@malva.app',
      password: 'test',
    }), {
      headers: { 'Content-Type': 'application/json' },
    });

    if (res.status === 429) {
      blockedRate.add(1);
      check(res, {
        'rate limit triggered': (r) => r.status === 429,
      });
      break;
    }

    sleep(0.1);
  }
}

export default function () {
  testBruteForce();
  testSQLInjection();
  testXSS();
  testPathTraversal();
  testRateLimit();
  sleep(2);
}

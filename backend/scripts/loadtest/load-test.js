import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const errorRate = new Rate('errors');
const loginDuration = new Trend('login_duration');
const apiDuration = new Trend('api_duration');

const BASE_URL = __ENV.MALVA_API_BASE_URL || 'http://localhost:8080';

export const options = {
  stages: [
    { duration: '30s', target: 10 },
    { duration: '1m', target: 10 },
    { duration: '30s', target: 20 },
    { duration: '1m', target: 20 },
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],
    http_req_failed: ['rate<0.1'],
    errors: ['rate<0.1'],
    login_duration: ['p(95)<300'],
    api_duration: ['p(95)<200'],
  },
};

function registerUser(email, password, role) {
  const payload = JSON.stringify({
    email: email,
    password: password,
    display_name: `Load Test ${role}`,
    role: role,
  });

  const res = http.post(`${BASE_URL}/v1/auth/register`, payload, {
    headers: { 'Content-Type': 'application/json' },
  });

  return res;
}

function loginUser(email, password) {
  const start = Date.now();
  const payload = JSON.stringify({
    email: email,
    password: password,
  });

  const res = http.post(`${BASE_URL}/v1/auth/login`, payload, {
    headers: { 'Content-Type': 'application/json' },
  });

  loginDuration.add(Date.now() - start);
  return res;
}

function getAuthToken(email, password) {
  const res = loginUser(email, password);
  if (res.status === 200) {
    const body = JSON.parse(res.body);
    return body.access_token;
  }
  return null;
}

export function setup() {
  const testEmail = `loadtest_${Date.now()}@malva.app`;
  const testPassword = 'LoadTest123!@#';

  const regRes = registerUser(testEmail, testPassword, 'patient');
  if (regRes.status === 201) {
    const body = JSON.parse(regRes.body);
    return {
      email: testEmail,
      password: testPassword,
      token: body.access_token,
      userId: body.user.id,
    };
  }

  return {
    email: testEmail,
    password: testPassword,
    token: null,
    userId: null,
  };
}

export default function (data) {
  let token = data.token;

  if (!token) {
    token = getAuthToken(data.email, data.password);
    if (!token) {
      errorRate.add(1);
      sleep(1);
      return;
    }
  }

  const headers = {
    'Content-Type': 'application/json',
    Authorization: `Bearer ${token}`,
  };

  const healthRes = http.get(`${BASE_URL}/healthz`);
  check(healthRes, {
    'healthz status is 200': (r) => r.status === 200,
  }) || errorRate.add(1);

  sleep(0.5);

  const meStart = Date.now();
  const meRes = http.get(`${BASE_URL}/v1/me`, { headers });
  apiDuration.add(Date.now() - meStart);
  check(meRes, {
    'me status is 200': (r) => r.status === 200,
  }) || errorRate.add(1);

  sleep(0.5);

  const moodPayload = JSON.stringify({
    mood: 'good',
    sleep_hours: 7.5,
    energy: 7,
    anxiety: 3,
    irritability: 2,
    note: 'Load test mood checkin',
  });

  const moodStart = Date.now();
  const moodRes = http.post(`${BASE_URL}/v1/mood-checkins`, moodPayload, { headers });
  apiDuration.add(Date.now() - moodStart);
  check(moodRes, {
    'mood checkin status is 201': (r) => r.status === 201,
  }) || errorRate.add(1);

  sleep(0.5);

  const moodsStart = Date.now();
  const moodsRes = http.get(`${BASE_URL}/v1/mood-checkins?limit=10`, { headers });
  apiDuration.add(Date.now() - moodsStart);
  check(moodsRes, {
    'list moods status is 200': (r) => r.status === 200,
  }) || errorRate.add(1);

  sleep(0.5);

  const diaryPayload = JSON.stringify({
    mood: 'okay',
    title: 'Load Test Diary',
    note: 'This is a load test diary entry',
    shared_with_professionals: false,
  });

  const diaryStart = Date.now();
  const diaryRes = http.post(`${BASE_URL}/v1/diary-entries`, diaryPayload, { headers });
  apiDuration.add(Date.now() - diaryStart);
  check(diaryRes, {
    'diary entry status is 201': (r) => r.status === 201,
  }) || errorRate.add(1);

  sleep(1);
}

export function teardown(data) {
  console.log(`Load test completed for user: ${data.email}`);
}

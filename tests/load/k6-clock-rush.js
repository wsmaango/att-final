// 부하 테스트: 9시 출근 몰림 모델 (출근 체크 85% / 관리자 현황 10% / 개인 기록 5%)
// 실행: k6 run -e BASE=https://<service_ip> tests/load/k6-clock-rush.js --summary-export evidence/k6-summary.json
// 데모 고객사 3곳 × 직원 20,000명 (DEMO_EMPLOYEES). 키는 데모용 더미 값이며, 교체했다면 -e KEYS=a,b,c 로 넘긴다.
import http from 'k6/http';
import { check } from 'k6';
import { Rate } from 'k6/metrics';

const BASE = __ENV.BASE || 'https://127.0.0.1';
const KEYS = (__ENV.KEYS || 'demo-key-tenant-1,demo-key-tenant-2,demo-key-tenant-3').split(',');
const EMPLOYEES = Number(__ENV.EMPLOYEES || 20000);
const errors = new Rate('att_errors');

export const options = {
  insecureSkipTLSVerify: true, // self-signed (W7 Part C)
  scenarios: {
    nine_am_rush: {
      executor: 'ramping-arrival-rate',
      startRate: 10,
      timeUnit: '1s',
      preAllocatedVUs: 100,
      maxVUs: 600,
      stages: [
        { target: 30, duration: '1m' },   // 08:40~08:55 평시 출근 (규모 가정과 맞출 것)
        { target: 250, duration: '30s' }, // 08:58 급증
        { target: 250, duration: '2m' },  // 08:58~09:00 피크
        { target: 10, duration: '30s' },  // 09:00 이후
      ],
    },
  },
  thresholds: {
    'http_req_duration{name:clock}': ['p(95)<500'], // SLO: 출근 체크 p95 500ms
    'http_req_duration{name:today}': ['p(95)<300'],
    att_errors: ['rate<0.001'],                      // SLO: 성공률 99.9%
  },
};

function pick(a) { return a[Math.floor(Math.random() * a.length)]; }

export default function () {
  const headers = { 'X-Api-Key': pick(KEYS), 'Content-Type': 'application/json' };
  const emp = `E${String(1 + Math.floor(Math.random() * EMPLOYEES)).padStart(4, '0')}`;
  const r0 = Math.random();
  let res;
  if (r0 < 0.85) {
    res = http.post(`${BASE}/api/clock`, JSON.stringify({ emp_no: emp, kind: 'in' }), { headers, tags: { name: 'clock' } });
    // 201 신규, 200 중복(재시도), 202 DB 장애 중 스풀 접수 → 모두 '기록 성공'
    errors.add(!check(res, { 'clock accepted': (x) => [200, 201, 202].includes(x.status) }));
  } else if (r0 < 0.95) {
    res = http.get(`${BASE}/api/attendance/today`, { headers, tags: { name: 'today' } });
    errors.add(!check(res, { 'today 200': (x) => x.status === 200 }));
  } else {
    res = http.get(`${BASE}/api/employees/${emp}/records`, { headers, tags: { name: 'records' } });
    errors.add(!check(res, { 'records 200': (x) => x.status === 200 }));
  }
}

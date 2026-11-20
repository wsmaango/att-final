# S4 보안 사고 - 고객사 API 키 유출과 비정상 호출

> 안전 규칙: **데모 키·더미 시크릿·모의 로그만** 사용한다. 실제 공격 도구, 타인 시스템 대상 시험 금지.

## 상황 설정과 대응 목표 (4)
- **상황:** 고객사 2(샘플물류)의 개발자가 API 키를 공개 저장소에 커밋했다(데모 키). 직후 해당 키로 평소의 수십 배 호출이 들어오고, 다른 직원 번호로 출근 체크가 시도된다(모의).
- **목표:** 15분 안에 (1) 비정상 호출 탐지 (2) 해당 고객사 키 교체·이전 키 차단 (3) 다른 고객사 영향 0 확인 (4) 위조 기록 식별 (5) 재발 방지

## 재현 방법
```bash
# 1) 유출: 연습 저장소에 데모 키 커밋 → gitleaks 로 탐지되는지 확인
echo 'ATT_API_KEY="demo-key-tenant-2"' > leak_demo.env && git add -f leak_demo.env && git commit -m "demo: leak"
gitleaks detect --source . --log-opts="--all" -v
# 2) 비정상 호출 (본인 서비스에만): 유출 키로 몰아치기
k6 run -e BASE=https://<service_ip> -e KEYS=demo-key-tenant-2 tests/load/k6-clock-rush.js
#    동시에 다른 고객사 정상 트래픽은 measure.sh 로 측정 (영향 0 확인)
API_KEY=demo-key-tenant-1 MODE=clock tests/failover/measure.sh https://<service_ip> 300 > evidence/s4-tenant1.log
# 3) 대응: 키 교체 (data01 에서) → 이전 키가 401 이 될 때까지 시간 측정
scp -P 2205 scripts/rotate-tenant-key.sh ubuntu@<mgmt_ip>:~ && ssh -p 2205 ubuntu@<mgmt_ip> "sudo bash ~/rotate-tenant-key.sh 2"
```

## 보여줄 통제
- 고객사별 `limit_req` → 유출 키 폭주가 429 로 막히고 다른 고객사는 정상 (Nginx 로그·429 수)
- 키 해시 저장 → DB 가 유출돼도 키 원문은 없음
- RLS → 유출 키로는 해당 고객사 데이터만 접근 가능 (피해 범위 한정)
- 교체 반영 지연 = 앱 고객사 캐시 30초 (`TENANT_CACHE_TTL`) → 측정값과 비교

## 타임라인 (6)
| 시각 | 본 것 | 한 것 |
|---|---|---|
| 00:00 | gitleaks / CI 실패 | |
| | 429 급증 (고객사 2) | |
| | | 키 교체 |
| | 이전 키 401 확인 | |
| | | 위조 의심 기록 조회 (해당 시간대 고객사 2, `source`, 호출 패턴) |

## 조치와 설계 변경 (6)
- 교체 절차와 소요: `TODO`
- 설계 변경 후보: 키 교체 즉시 반영(캐시 무효화 엔드포인트 또는 TTL 단축의 비용 비교), 고객사별 호출량 이상 알림 룰, pre-commit gitleaks
- 코드·Terraform diff: `TODO`

## 전후 수치 비교 (6)
| 지표 | 전 | 후 |
|---|---|---|
| 유출 → 탐지 | | |
| 교체 → 이전 키 차단 | | |
| 공격 중 다른 고객사 실패율 | | |
| gitleaks 탐지 건수 (이력 포함) | | 0 |

## 포스트모템 (4)
- 근본 원인:
- 재발 방지책:

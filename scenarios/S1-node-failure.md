# S1 장애 - 출근 피크 직전에 서버 일부가 멈춘다

## 상황 설정과 대응 목표 (4)
- **상황 A (이중화된 계층):** 08:57, app01 프로세스가 죽는다.
  - 목표: 실패 요청 < 0.1%, 1분 안에 알림(`InstanceDown`), 10분 안에 2대 상태 복구
- **상황 B (SPOF 계층):** 08:57, data01 의 PostgreSQL 이 멈춘다.
  - 목표: **출근 기록 유실 0건**(접수 = DB 적재), 출근 접수는 중단 없이 계속(202), DB RTO 30분
  - 이 상황이 1순위(가용성) 요구사항을 직접 검증한다.

## 재현 방법 (본인 환경에서만)
```bash
# 터미널 A - 측정 (출근 체크를 0.2초마다)
MODE=clock tests/failover/measure.sh https://<service_ip> 300 > evidence/s1-b.log
# 터미널 B - 피크 부하 (선택)
k6 run -e BASE=https://<service_ip> tests/load/k6-clock-rush.js
# 터미널 C - 주입
ssh -p 2205 ubuntu@<mgmt_ip> 'sudo systemctl stop postgresql'   # 상황 B
#   (상황 A: ssh -p 2203 ... 'sudo systemctl stop att-app')
# 몇 분 뒤 복구
ssh -p 2205 ubuntu@<mgmt_ip> 'sudo systemctl start postgresql'
```

## 유실 0 검증 방법 (상황 B 의 핵심 증거)
1. 복구 후 Grafana 에서 `sum(att_spool_pending)` 이 0 이 될 때까지 기다린다.
2. `tests/failover/verify-no-loss.sh evidence/s1-b.log <mgmt_ip>` → measure.sh 로그에서 접수 성공(200·201·202)한 사원번호와 DB 기록을 비교해 "유실: 0건" 을 출력한다.
3. data01 에서 `source = 'spool'` 행의 `ts` 가 DB 적재 시각이 아니라 **접수 시각**인지 확인한다 (지각 판정 정확성):
   `sudo -u postgres psql -d att -c "SELECT emp_no, ts, source FROM attendance WHERE source='spool' ORDER BY ts DESC LIMIT 5;"`

## 타임라인 (분 단위, 본인 기록) (6)
| 시각 | 본 것 (대시보드·알림·로그) | 한 것 |
|---|---|---|
| 08:57:00 | | 장애 주입 |
| | 응답 202 비율 증가, `att_spool_pending` 증가 | |
| | `ClockSpoolBacklog` PENDING → FIRING | |
| | | 원인 확인 (`systemctl status postgresql`, 로그) |
| | | 복구 |
| | `att_spool_pending` → 0 | 유실 검증 |

## 조치와 설계 변경 (Terraform·코드 변경 포함) (6)
- 즉시 조치: `TODO`
- 설계 변경 후보 (실제로 한 것만 쓰고 커밋 링크):
  - 개선 전 기준선을 남기려면: app 노드의 `/etc/att/app.env` 에 `SPOOL_ENABLED=false` 를 넣고 재시작한 상태로 한 번 측정 → 503 실패 건수가 "유실" 이 된다
  - data02 스트리밍 복제 추가 (`nodes` 에 data02)
  - `ClockSpoolBacklog` 임계값·`for` 조정
- Terraform diff: `TODO`

## 전후 수치 비교 (6)
| 지표 | 개선 전 (스풀 없음) | 개선 후 (스풀) |
|---|---|---|
| DB 장애 중 출근 실패 응답 | | 0 기대 |
| 유실된 출근 기록 | | 0 기대 |
| 복구 후 재적재 완료까지 | - | |
| 탐지까지 | | |

## 포스트모템 (4)
- 근본 원인:
- 잘된 점 / 아쉬운 점:
- 재발 방지책 (담당·기한):

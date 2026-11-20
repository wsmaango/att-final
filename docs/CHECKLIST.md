# 배점별 체크리스트와 진행 순서

마감: **14주차 수업일 12:00 (LMS 게시물 날짜 확인)**. 당일 23:59 까지 지각 제출 가능하나 총점 20% 감점.

## 진행 순서 (권장)
1. **환경 확인** (COURSE-MAP 의 "첫 apply 전에" 5개) → tfvars 작성 → `terraform test` → `plan`
2. **apply → smoke-test 통과** → destroy → apply 재생성 캡처 (③ 12점 전부가 여기)
3. **k6 9시 몰림 기준선 → 개선 단계별 3회** (④ 부하 5점)
4. **장애 주입 3종 + measure.sh** (④ 페일오버 4점, S1 재료)
5. **백업 복구 리허설** (④ RPO·RTO 3점)
6. **S1·S4 시나리오** (⑧ 20점 - 배점이 가장 큼. S1 은 `SPOOL_ENABLED=false` 기준선 → 스풀 켠 상태로 전후 비교)
7. GitHub 저장소 push → Actions 통과 캡처 (⑤ 2점) → 공개 시 +2점
8. REPORT 작성 → PDF 변환 → `scripts/pre-submit-check.sh 학번 이름`

## 배점별 확인
| 항목 | 체크 | 근거 파일 |
|---|---|---|
| ① 문제·사용자 (2) | ☐ | REPORT 1.1 |
| ① 우선순위·수치 목표 (3) | ☐ | REPORT 1.2 |
| ① 규모 가정·산정 근거 (3) | ☐ | REPORT 1.3 |
| ② 도식과 구현 일치 (4) | ☐ | 구성도 + 콘솔/terraform output 캡처 |
| ② 이중화·SPOF (5) | ☐ | REPORT 2.3 + 페일오버 수치 |
| ② 부하 분산·확장·캐시 (5) | ☐ | X-Cache 캡처, 429 동작, Nginx 공유 캐시를 뺀 이유 |
| ② 네트워크·접근 경로 (3) | ☐ | 포트 표 + nc -vz 결과 |
| ② 대안 비교 (3) | ☐ | REPORT 2.6 |
| ③ 서비스 동작 (4) | ☐ | smoke-test 캡처 |
| ③ destroy 후 재생성 (5) | ☐ | 두 번의 apply 캡처 |
| ③ fmt·validate·변수 분리 (3) | ☐ | 출력 캡처 |
| ④ 부하·병목 (5) | ☐ | k6 summary 3회 + Grafana |
| ④ 장애 주입·페일오버 (4) | ☐ | measure.sh 로그 |
| ④ SLI·SLO (3) | ☐ | Prometheus 쿼리 캡처 |
| ④ 백업·복구 RPO·RTO (3) | ☐ | restore-test 출력 |
| ⑤ 접근 제어 (3) | ☐ | ufw status, sshd -T |
| ⑤ 정적 분석·조치 (3) | ☐ | checkov/tflint 결과 + 조치표 |
| ⑤ PaC 또는 파이프라인 (2) | ☐ | Actions 캡처 (terraform test·checkov·위반 코드 자체시험) |
| ⑤ 시크릿·라이선스 (2) | ☐ | gitleaks 결과, THIRD_PARTY |
| ⑥ 사전 설계·지침 (2) | ☐ | CLAUDE.md |
| ⑥ AI 결과 확인 방법 (3) | ☐ | ai-log 2절 |
| ⑥ AI 틀린 사례 2건+ (3) | ☐ | ai-log 3절 |
| ⑦ 차별점 (2) / 비용 (3) / 확장 위험 (2) | ☐ | REPORT 8 |
| ⑧ S1 (목표·증거·전후·포스트모템) | ☐ | scenarios/S1 |
| ⑧ S4 | ☐ | scenarios/S4 |

## 감점 방지
- [ ] zip 에 `.terraform/`, `*.tfstate`, 실제 `terraform.tfvars`, `.env`, 키 파일 없음
- [ ] 캡처에 IP·키·계정 가림
- [ ] 공개 저장소 **커밋 이력**에도 시크릿 없음 (gitleaks `--log-opts=--all`)
- [ ] REPORT.md 와 REPORT.pdf 내용 동일
- [ ] 파일명 `학번_이름_최종과제.zip`

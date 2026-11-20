# 기업용 근태 기록 SaaS 인프라 (인프라 설계 및 구축 최종 과제)

> 학번 `TODO` · 이름 `TODO` · 공개 저장소: `TODO` (README 에 적으면 +2점)

여러 기업(고객사)이 함께 쓰는 출퇴근 기록 서비스를 Solid Cloud(CloudStack) 위에 Terraform 으로 구축했다.
09:00 직전 출근 체크가 몰리고, 기록이 빠지면 급여 분쟁이 생기는 서비스다.
**우선순위: 1순위 가용성(출근 기록 유실 0), 2순위 성능·확장.** 자세한 내용은 [docs/REPORT.md](docs/REPORT.md).

## 구성
- 격리 네트워크 192.168.0.0/24, 공인 IP 2개 (서비스 / 관리 분리)
- 가상 라우터 LB(L4) → **lb01·lb02** Nginx (TLS 종료, L7 분산, 고객사별 요청 제한)
- → **app01·app02** Flask API (멱등 출근 체크, DB 장애 시 로컬 스풀 후 재적재)
- → **data01** PostgreSQL(Row Level Security 로 고객사 분리) + Redis, **mon01** Prometheus·Grafana·15분 백업

1~7주차 실습과 이 저장소의 대응 관계: [docs/COURSE-MAP.md](docs/COURSE-MAP.md)

## 주요 수치 (측정 후 채움)
| 지표 | 목표 | 측정 |
|---|---|---|
| 출근 기록 유실 (DB 장애 중) | 0건 | `TODO` |
| 피크 RPS | 250 | `TODO` |
| 출근 체크 p95 | < 500ms | `TODO` |
| app 1대 장애 시 실패 요청 | < 0.1% | `TODO` |
| RPO / RTO (출근 외 데이터) | 15분 / 30분 | `TODO` |
| 월 비용 / 고객사당 비용 (공용 클라우드 환산) | - | `TODO` |

## 실행 방법
모든 명령은 Solid Cloud 안의 작업용 Ubuntu VM 에서 실행한다 (`bash scripts/workvm-setup.sh` 로 도구 설치). 실행 결과는 `scripts/ev.sh <이름> '<명령>'` 으로 `evidence/` 에 남기며, 공인 IP 는 자동으로 가려진다.

사전 조건: VPN 연결, Terraform ≥ 1.7(테스트용 mock provider), Solid Cloud API Key.
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars        # 값 수정 (커밋 금지)
export CLOUDSTACK_API_URL="https://<콘솔 주소>/client/api"
export CLOUDSTACK_API_KEY="..." CLOUDSTACK_SECRET_KEY="..."
export TF_VAR_redis_password="..." TF_VAR_db_password="..."   # 영문·숫자만
terraform init
terraform fmt -check && terraform validate && terraform test
checkov -d . --external-checks-dir policies --skip-path policies/tests
terraform plan -out plan.out      # 사람이 확인
terraform apply plan.out
# cloud-init 완료까지 수 분 기다린 뒤
../scripts/smoke-test.sh "$(terraform output -raw service_ip)"
```
데모 고객사 3곳(API 키 `demo-key-tenant-1~3`, 직원 각 20,000명)이 자동으로 만들어진다. 테스트용 더미 데이터이며, 실제 운영이라면 `scripts/rotate-tenant-key.sh` 로 키를 교체한다.
정리: `terraform destroy`

## 디렉터리
```
├─ README.md
├─ CLAUDE.md                 # AI 작업 지침 (규칙·통과 조건)
├─ ai-log.md                 # AI 활용 기록
├─ THIRD_PARTY.md            # 오픈소스·라이선스
├─ docs/                     # REPORT.md, REPORT.pdf, COURSE-MAP.md
├─ terraform/                # IaC, templates/cloud-init, policies/(Checkov 사용자 정의 정책), tests/(terraform test)
├─ app/                      # Flask API, systemd 유닛
├─ config/                   # bootstrap/<role>.sh, prometheus/alerts.yml
├─ tests/                    # load(k6 9시 몰림), failover(측정), backup(복구 리허설)
├─ scenarios/                # S1 출근 피크 DB 장애, S4 고객사 API 키 유출
├─ evidence/                 # 캡처 (IP·키·계정 가리기)
├─ scripts/                  # workvm-setup(작업 VM 도구 설치), ev(실행 결과 저장), promq, smoke-test, rotate-tenant-key, pre-submit-check
└─ .github/workflows/        # fmt·validate·terraform test·tflint·checkov·정책 자체시험·gitleaks
```

# AI 작업 지침 (이 저장소에서 AI 도구가 따를 규칙)

## 목표
기업용 멀티테넌트 근태 기록 SaaS 인프라. 1순위 가용성(출근 기록 유실 0), 2순위 성능·확장. 수치 목표는 docs/REPORT.md 1.2 를 따른다.

## 규칙
- 인프라 자원은 전부 `terraform/` 에서만 만든다. 콘솔 수동 생성 금지.
- 새 변수는 `variables.tf`, 출력은 `outputs.tf`. 실제 값은 `terraform.tfvars`(커밋 금지), 예시는 `terraform.tfvars.example`.
- 시크릿·키·IP 를 코드·문서·로그에 쓰지 않는다. 비밀번호는 `TF_VAR_*`, API 키는 `CLOUDSTACK_*` 환경변수.
- 0.0.0.0/0 에는 80·443 만 연다. SSH·관측 포트는 `admin_cidrs` 만.
- VM 오퍼링은 Small·Medium 까지.
- 서버 설정은 `config/bootstrap/<role>.sh` 에 쓰고 cloud-init 은 실행만 한다.
- 고객사 데이터에 닿는 모든 쿼리는 같은 트랜잭션에서 `as_tenant()` 를 먼저 호출한다 (RLS). 캐시 키에는 tenant_id 를 넣는다. Nginx 공유 캐시는 쓰지 않는다.
- 출근 체크는 멱등이어야 한다 (재시도·LB 재전송 안전).
- 실행(apply·destroy·ssh)은 사람이 한다. AI 는 코드와 명령을 제안만 한다.

## 통과 조건 (변경마다)
1. `terraform fmt -check -recursive` / `terraform validate` / `terraform test`
2. `checkov -d terraform --external-checks-dir terraform/policies --skip-path policies/tests`
3. `bash -n config/bootstrap/*.sh`, `python3 -m py_compile app/app.py`
4. gitleaks 0건

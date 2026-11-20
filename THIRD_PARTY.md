# 사용한 오픈소스

버전은 배포 후 VM 에서 확인한 값으로 채운다 (`dpkg -l | grep ...`, `pip freeze`).

| 이름 | 버전 | 라이선스 | 출처 | 용도 |
|---|---|---|---|---|
| Nginx | `TODO` | BSD-2-Clause | Ubuntu 패키지 | LB·TLS·캐시 |
| PostgreSQL | `TODO` | PostgreSQL License | Ubuntu 패키지 | DB |
| Redis | `TODO` (7.x) | BSD-3-Clause (7.4 미만) | Ubuntu 패키지 | 캐시 |
| Prometheus / node_exporter / nginx-exporter | `TODO` | Apache-2.0 | Ubuntu 패키지 | 관측 |
| Grafana | `TODO` | **AGPL-3.0** | apt.grafana.com | 대시보드 (수정·재배포하지 않고 내부 사용만) |
| Flask | 3.0.3 | BSD-3-Clause | PyPI | API |
| gunicorn | 23.0.0 | MIT | PyPI | WSGI |
| redis-py | 5.0.8 | MIT | PyPI | Redis 클라이언트 |
| psycopg | 3.2.3 | LGPL-3.0 | PyPI | PostgreSQL 클라이언트 (수정 없이 동적 사용) |
| prometheus-client | 0.21.0 | Apache-2.0 | PyPI | 앱 메트릭 |
| Terraform CloudStack provider | `TODO` | Apache-2.0 | registry.terraform.io/providers/cloudstack/cloudstack | IaC |
| k6 | `TODO` | AGPL-3.0 | grafana/k6 | 부하 테스트 (로컬 도구로만 사용) |
| Checkov | `TODO` | Apache-2.0 | PyPI | 정적 분석 |

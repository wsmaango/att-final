# 1~7주차 실습 → 최종 과제 매핑

과제 안내의 조건: "어떤 방식이든 1~7주차 내용(이중화, 부하 분산, 캐시, 네트워크, 모니터링, 보안)이 설계에 드러나야 합니다."
아래 표는 각 주차에서 손으로 한 것이 이 저장소의 어디에 코드로 들어갔는지, 그리고 어떤 배점과 연결되는지 정리한 것이다.

| 주차 | 실습에서 한 것 | 이 과제에서의 위치 | 연결 배점 |
|---|---|---|---|
| W1 Solid Cloud·첫 VM | 격리 네트워크, Egress, 포트포워딩, 방화벽(VPN 대역 10.8.0.0/24만), 가상 라우터 = 공인IP·NAT·방화벽·GW | `terraform/main.tf` 1)·4)·6) - `cloudstack_network`, `cloudstack_egress_firewall`(필요 포트만), `cloudstack_port_forward`, `cloudstack_firewall` | ② 네트워크·접근 경로 분리(3), ⑤ 접근 제어(3) |
| W2 리눅스·웹서버 | 스펙 읽기(lscpu·free·df), 사용자·패키지·서비스, systemd 자동시작, 리스닝 포트 점검 | `config/bootstrap/*.sh`(cloud-init), `app/att-app.service` | ③ 서비스 동작(4), ⑦ 적정 사이징 근거 |
| W3 Keepalived VIP | VRRP MASTER/BACKUP, priority 110/100, failover·failback, **포트포워딩은 VIP를 따라가지 않음** | 대안 비교: lb 이중화를 VIP 대신 가상 라우터 LB 규칙(`entry_mode = "vr_lb"`)으로. 이유는 W3에서 확인한 포트포워딩 한계 | ② 이중화·SPOF(5), 대안 비교(3) |
| W4 로드밸런싱 | Nginx upstream, least_conn, `max_fails=2 fail_timeout=5s` passive 헬스체크, L4 vs L7 | 2단 분산: L4(가상 라우터 → lb01·lb02) + L7(Nginx → app01·app02). 출근 API 가 멱등이라 POST 도 다른 app 으로 재시도(`non_idempotent`). `config/bootstrap/lb.sh` | ② 부하 분산(5), ④ 장애 주입·페일오버(4) |
| W5 캐시 | Redis(bind·requirepass), Cache-Aside, Nginx proxy_cache, `X-Cache-Status`, `time`으로 효과 측정 | 현황 조회만 Redis Cache-Aside(키에 tenant_id). **Nginx 공유 캐시는 고객사 간 데이터 노출 위험 때문에 일부러 빼고**, 그 판단을 리포트 2.4 에 씀. `data.sh` Redis 보안 | ② 캐시(5), ② 대안 비교(3) |
| W6 관측성 | node_exporter, Prometheus, Grafana, stub_status, `up == 0 for 1m` 알림, 장애 주입, 롤링·카나리 | `config/bootstrap/mon.sh`, `config/prometheus/alerts.yml`(SLO 기록 룰 포함), app `/metrics` | ④ SLI·SLO(3), ⑧ 타임라인 증거(6) |
| W7 보안 | ss·nc로 공격 표면 확인, ufw 출처 제한, SSH 하드닝, TLS 종료·HTTP→HTTPS, 시크릿 분리(chmod 600) | `common.sh`(SSH·ufw), `lb.sh`(TLS·고객사별 요청 제한), `app.sh`(`/etc/att/app.env` 640), 고객사 키 해시 저장 + PostgreSQL RLS, `rotate-tenant-key.sh`(S4) | ⑤ 전체(10), ⑧ S4 보안 사고 |

## 이 저장소의 기본 설계 한눈에

```
                         VPN(10.8.0.0/24) / 교내망
                                  │
            ┌─────────────────────┴──────────────────────┐
     서비스 공인 IP :80/:443                      관리 공인 IP :2201~2206, :3000, :9090
     (가상 라우터 LB 규칙, L4)                    (포트포워딩, VPN 대역만 허용)
            │                                            │
   ┌────────┴────────┐                                   │
 lb01 .20         lb02 .21    Nginx: TLS 종료, L7 분산, 고객사별 요청 제한
   └────────┬────────┘
   ┌────────┴────────┐
 app01 .10        app02 .11   Flask :5000 (lb·mon 에서만), DB 장애 시 출근 스풀
   └────────┬────────┘
         data01 .30           PostgreSQL(RLS) :5432 + Redis :6379 (app 에서만)   ← 남은 SPOF (S1 에서 다룸)
         mon01  .40           Prometheus·Grafana·pg_dump 15분 백업
             격리 네트워크 192.168.0.0/24 (W1·W3·W7 관례 그대로)
```

## 실습 환경에서 미리 확인할 것 (첫 apply 전에)

1. **네트워크 오퍼링에 Load Balancer 서비스가 있는지.** W1 문서에는 오퍼링 서비스가 "Source NAT·방화벽·포트포워딩·VPN"으로만 적혀 있다. LB가 없으면 `entry_mode = "port_forward"`로 바꾸고, lb 단일 진입점을 SPOF로 리포트에 명시한다(lb02로 바꿔 apply 하는 수동 전환 시간을 RTO로 측정).
2. **API 키 발급 위치와 API URL.** 콘솔 계정 메뉴에서 API Key/Secret Key를 발급하고, URL은 보통 `https://<콘솔 주소>/client/api` 형식이다.
3. **템플릿·오퍼링 정확한 이름.** `Ubuntu_24.04`, `Medium`은 콘솔 표시 이름과 다를 수 있다. `terraform plan`에서 "not found" 오류가 나면 이 값부터 본다.
4. **VM 개수 한도.** 기본 6대(lb 2, app 2, data 1, mon 1). 한도가 부족하면 `nodes`에서 mon01을 빼고 lb01에 관측을 합치거나, 슬랙 #민원상담에 요청한다.
5. **user_data 크기.** 앱 코드를 gzip+base64로 넣는다. 거부되면 앱은 공개 GitHub 저장소에서 `git clone` 하는 방식으로 바꾼다.

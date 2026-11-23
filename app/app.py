"""멀티테넌트 근태 기록 SaaS API (코드명 att)

고객사(기업)마다 API 키를 받아 직원 출퇴근을 기록한다.

- 쓰기: POST /api/clock                 {emp_no, kind: in|out}  - 9시 직전 몰림의 대상
- 읽기: GET  /api/attendance/today      고객사 관리자 현황 (Redis 캐시, 키에 tenant_id 포함)
        GET  /api/employees/<emp_no>/records?month=YYYY-MM
- 운영: GET  /healthz, /readyz, /metrics

설계 포인트
- 고객사 분리: PostgreSQL Row Level Security(FORCE) 로 앱 버그가 있어도 다른 고객사 행이 보이지 않게 한다.
- 멱등성: (tenant, emp_no, 날짜, in/out) 유일 → 재시도·LB 재전송이 와도 기록은 한 번.
- 출근 기록 유실 0: DB 장애 시 앱 노드 디스크에 fsync 로 스풀하고 202 를 돌려준 뒤, DB 가 돌아오면 재적재한다.
  기록 시각은 '접수 시각'이라 지각 판정이 틀어지지 않는다.

설정은 전부 환경변수. 비밀번호를 코드에 쓰지 않는다 (W7 Part D).
"""
import glob
import hashlib
import json
import os
import threading
import time
from contextlib import contextmanager
from datetime import datetime, time as dtime
from zoneinfo import ZoneInfo

import psycopg
from psycopg_pool import ConnectionPool
import redis
from flask import Flask, Response, g, has_request_context, jsonify, request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest

KST = ZoneInfo("Asia/Seoul")
WORK_START = dtime(9, 0)

DB_DSN = (
    f"host={os.environ.get('DB_HOST', '127.0.0.1')} "
    f"port={os.environ.get('DB_PORT', '5432')} "
    f"dbname={os.environ.get('DB_NAME', 'att')} "
    f"user={os.environ.get('DB_USER', 'att')} "
    f"password={os.environ.get('DB_PASSWORD', '')} "
    "connect_timeout=2"
)
CACHE_TTL = int(os.environ.get("CACHE_TTL", "10"))
TENANT_CACHE_TTL = int(os.environ.get("TENANT_CACHE_TTL", "30"))  # 키 교체가 반영되는 최대 지연
SPOOL_DIR = os.environ.get("SPOOL_DIR", "/var/lib/att")
# S1 개선 전후 비교용 스위치: false 면 DB 장애 시 503 (스풀 없는 기준선)
SPOOL_ENABLED = os.environ.get("SPOOL_ENABLED", "true").lower() == "true"
NODE = os.environ.get("NODE_NAME", os.uname().nodename)

app = Flask(__name__)

rds = redis.Redis(
    host=os.environ.get("REDIS_HOST", "127.0.0.1"),
    port=int(os.environ.get("REDIS_PORT", "6379")),
    password=os.environ.get("REDIS_PASSWORD") or None,
    socket_timeout=0.5,
    socket_connect_timeout=0.5,
    decode_responses=True,
)

REQS = Counter("att_http_requests_total", "HTTP requests", ["method", "endpoint", "status"])
# S4: 고객사별 호출량 (유출 키 폭주 탐지용). 고객사 수만큼만 라벨이 생긴다.
TENANT_REQS = Counter("att_tenant_requests_total", "Authenticated requests per tenant", ["tenant"])
LAT = Histogram(
    "att_http_request_duration_seconds",
    "HTTP latency",
    ["endpoint"],
    buckets=(0.01, 0.025, 0.05, 0.1, 0.2, 0.3, 0.5, 1, 2, 5),
)
CLOCK = Counter("att_clock_total", "Clock requests", ["result"])  # created|duplicate|spooled|not_found
CACHE = Counter("att_cache_total", "Cache lookups", ["result"])  # hit|miss|error
SPOOL_PENDING = Gauge("att_spool_pending", "Clock events waiting in local spool")
DB_UP = Gauge("att_db_up", "1 if this app node can reach PostgreSQL (checked every 3s)")
SPOOL_REPLAYED = Counter("att_spool_replayed_total", "Spooled events written to DB", ["result"])


# ---------------------------------------------------------------- DB
# 4단계 3회차 개선: 요청마다 새로 접속(TCP + SCRAM 인증 + PostgreSQL 프로세스 fork)하던 것을
# 연결 풀로 재사용한다. DB_POOL=false 로 끄면 개선 전(요청마다 접속)과 비교할 수 있다.
# - 정상 종료 시 commit, 예외 시 rollback 후 반환 (psycopg.connect 의 with 와 같은 의미)
# - as_tenant 는 set_config(..., true) 로 트랜잭션 범위라 연결을 재사용해도 다른 고객사로 새지 않는다
# - check_connection: 꺼낸 연결이 죽어 있으면(DB 재시작 후) 버리고 새로 맺는다
# - DB 장애 시: 풀은 연결을 기다리느라 timeout 만큼 막히므로, 한 번 실패하면 차단기를 연다.
#   차단기가 열려 있는 동안 사용자 요청은 DB 를 기다리지 않고 곧바로 스풀(202)로 간다.
#   차단기를 닫는(복구 판단) 일은 사용자 요청이 아니라 백그라운드 확인(_probe_db, 3초마다)만 한다.
#   (5단계 재측정: 1초마다 사용자 요청이 시험 삼아 DB 를 기다리게 했더니 장애 중 17% 가 0.5초를 넘었다)
DB_POOL = os.environ.get("DB_POOL", "true").lower() == "true"
_pool = None
_db_breaker_open = False
if DB_POOL:
    _pool = ConnectionPool(
        DB_DSN,
        min_size=2,
        max_size=int(os.environ.get("DB_POOL_MAX", "10")),  # gunicorn 스레드 8 + 스풀 재처리 1 + 여유
        timeout=1,
        check=ConnectionPool.check_connection,
        kwargs={"autocommit": False},
        open=False,
        name="att",
    )
    _pool.open(wait=False)  # DB 가 아직 안 떠 있어도 앱은 기동 (백그라운드에서 재시도)


@contextmanager
def db():
    global _db_breaker_open
    if _pool is None:
        with psycopg.connect(DB_DSN, autocommit=False) as conn:
            yield conn
        return
    if _db_breaker_open:
        raise psycopg.OperationalError("DB 연결 차단 중 (백그라운드 확인이 복구를 확인할 때까지)")
    try:
        with _pool.connection() as conn:
            yield conn
    except psycopg.OperationalError:
        _db_breaker_open = True
        raise


def as_tenant(cur, tenant_id: int):
    """이 트랜잭션 동안 RLS 정책이 보는 고객사 ID."""
    cur.execute("SELECT set_config('app.tenant_id', %s, true)", (str(tenant_id),))


def key_hash(api_key: str) -> str:
    return hashlib.sha256(api_key.encode()).hexdigest()


SCHEMA = """
CREATE TABLE IF NOT EXISTS tenants (
  id           SERIAL PRIMARY KEY,
  name         TEXT NOT NULL,
  api_key_hash TEXT NOT NULL UNIQUE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS employees (
  tenant_id INT  NOT NULL REFERENCES tenants(id),
  emp_no    TEXT NOT NULL,
  name      TEXT NOT NULL,
  PRIMARY KEY (tenant_id, emp_no)
);
CREATE TABLE IF NOT EXISTS attendance (
  id        BIGSERIAL PRIMARY KEY,
  tenant_id INT  NOT NULL,
  emp_no    TEXT NOT NULL,
  kind      TEXT NOT NULL CHECK (kind IN ('in', 'out')),
  work_date DATE NOT NULL,
  ts        TIMESTAMPTZ NOT NULL,
  source    TEXT NOT NULL DEFAULT 'api',
  FOREIGN KEY (tenant_id, emp_no) REFERENCES employees(tenant_id, emp_no),
  UNIQUE (tenant_id, emp_no, work_date, kind)
);
ALTER TABLE employees  ENABLE ROW LEVEL SECURITY;
ALTER TABLE employees  FORCE  ROW LEVEL SECURITY;
ALTER TABLE attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance FORCE  ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'tenant_isolation_emp') THEN
    CREATE POLICY tenant_isolation_emp ON employees
      USING (tenant_id = current_setting('app.tenant_id', true)::int)
      WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::int);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'tenant_isolation_att') THEN
    CREATE POLICY tenant_isolation_att ON attendance
      USING (tenant_id = current_setting('app.tenant_id', true)::int)
      WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::int);
  END IF;
END $$;
"""

# 테스트용 더미 고객사와 키. 실제 기업·개인정보가 아니다. 배포 후 키는 scripts/rotate-tenant-key.sh 로 교체한다.
DEMO_TENANTS = [("데모상사", "demo-key-tenant-1"), ("샘플물류", "demo-key-tenant-2"), ("가상제조", "demo-key-tenant-3")]
DEMO_EMPLOYEES_PER_TENANT = int(os.environ.get("DEMO_EMPLOYEES", "200"))


def init_schema():
    with db() as conn, conn.cursor() as cur:
        cur.execute(SCHEMA)
        cur.execute("SELECT count(*) FROM tenants")
        if cur.fetchone()[0] == 0:
            for name, key in DEMO_TENANTS:
                cur.execute(
                    "INSERT INTO tenants (name, api_key_hash) VALUES (%s, %s) RETURNING id", (name, key_hash(key))
                )
                tid = cur.fetchone()[0]
                as_tenant(cur, tid)
                cur.executemany(
                    "INSERT INTO employees (tenant_id, emp_no, name) VALUES (%s, %s, %s)",
                    [(tid, f"E{i:04d}", f"직원{i:04d}") for i in range(1, DEMO_EMPLOYEES_PER_TENANT + 1)],
                )
        conn.commit()


# ---------------------------------------------------------------- 고객사 인증
_tenant_cache: dict[str, tuple[int, float]] = {}
_tenant_lock = threading.Lock()


class AuthError(Exception):
    pass


def resolve_tenant(api_key: str | None) -> int:
    tid = _resolve_tenant(api_key)
    if has_request_context():
        g.tenant_id = tid  # 고객사별 호출량 지표 (_record 에서 센다)
    return tid


def _resolve_tenant(api_key: str | None) -> int:
    """API 키 → tenant_id. 30초 캐시. DB 장애 중에는 이전에 확인된 키를 그대로 인정한다(출근 접수 유지)."""
    if not api_key:
        raise AuthError
    h = key_hash(api_key)
    now = time.time()
    with _tenant_lock:
        hit = _tenant_cache.get(h)
    if hit and now - hit[1] < TENANT_CACHE_TTL:
        return hit[0]
    try:
        with db() as conn, conn.cursor() as cur:
            cur.execute("SELECT id FROM tenants WHERE api_key_hash = %s", (h,))
            row = cur.fetchone()
    except psycopg.OperationalError:
        if hit:  # stale 허용: DB 장애 중 알려진 고객사의 출근은 받는다
            return hit[0]
        raise
    with _tenant_lock:
        if row is None:
            _tenant_cache.pop(h, None)
            raise AuthError
        _tenant_cache[h] = (row[0], now)
    return row[0]


# ---------------------------------------------------------------- 스풀 (DB 장애 시 출근 기록 보존)
_spool_lock = threading.Lock()


def _spool_file() -> str:
    return os.path.join(SPOOL_DIR, "spool.jsonl")


def spool_append(event: dict):
    with _spool_lock:
        with open(_spool_file(), "a", encoding="utf-8") as f:
            f.write(json.dumps(event, ensure_ascii=False) + "\n")
            f.flush()
            os.fsync(f.fileno())  # 202 를 돌려주기 전에 디스크에 확실히 쓴다
        SPOOL_PENDING.inc()


def _insert_clock(cur, ev: dict, source: str):
    as_tenant(cur, ev["tenant_id"])
    cur.execute(
        """
        INSERT INTO attendance (tenant_id, emp_no, kind, work_date, ts, source)
        SELECT %(tenant_id)s::int, emp_no, %(kind)s, %(work_date)s::date, %(ts)s::timestamptz, %(source)s
          FROM employees WHERE tenant_id = %(tenant_id)s AND emp_no = %(emp_no)s
        ON CONFLICT (tenant_id, emp_no, work_date, kind) DO NOTHING
        RETURNING id
        """,
        {**ev, "source": source},
    )
    if cur.fetchone():
        return "created"
    cur.execute("SELECT 1 FROM employees WHERE tenant_id = %s AND emp_no = %s", (ev["tenant_id"], ev["emp_no"]))
    return "duplicate" if cur.fetchone() else "not_found"


def replay_spool_once() -> int:
    """스풀을 .processing 으로 옮긴 뒤 DB 에 적재. 적재는 멱등이라 중간 실패 후 다시 돌려도 안전."""
    with _spool_lock:
        if os.path.exists(_spool_file()) and os.path.getsize(_spool_file()) > 0:
            os.rename(_spool_file(), os.path.join(SPOOL_DIR, f"spool.{time.time_ns()}.processing"))
    done = 0
    for path in sorted(glob.glob(os.path.join(SPOOL_DIR, "spool.*.processing"))):
        with open(path, encoding="utf-8") as f:
            events = [json.loads(line) for line in f if line.strip()]
        with db() as conn, conn.cursor() as cur:  # DB 가 아직 죽어 있으면 예외 → 파일 유지, 다음 주기에 재시도
            for ev in events:
                SPOOL_REPLAYED.labels(_insert_clock(cur, ev, "spool")).inc()
            conn.commit()
        os.remove(path)
        SPOOL_PENDING.dec(len(events))
        done += len(events)
    return done


def _probe_db():
    """풀과 별개로 매번 새로 접속해 본다. 탐지 지표(att_db_up)이자 차단기의 유일한 복구 판단."""
    global _db_breaker_open
    try:
        with psycopg.connect(DB_DSN) as c:
            c.execute("SELECT 1")
        DB_UP.set(1)
        _db_breaker_open = False
    except Exception:  # noqa: BLE001
        DB_UP.set(0)
        _db_breaker_open = True


def _replayer():
    while True:
        _probe_db()
        try:
            replay_spool_once()
        except Exception:  # noqa: BLE001 - DB 복구 전에는 계속 실패하는 것이 정상
            pass
        time.sleep(3)


def _count_pending() -> int:
    n = 0
    for p in glob.glob(os.path.join(SPOOL_DIR, "spool*")):
        with open(p, encoding="utf-8") as f:
            n += sum(1 for line in f if line.strip())
    return n


# ---------------------------------------------------------------- 요청 공통
@app.before_request
def _start():
    g.t0 = time.perf_counter()


@app.after_request
def _record(resp):
    ep = request.url_rule.rule if request.url_rule else "unknown"
    if ep != "/metrics":
        LAT.labels(ep).observe(time.perf_counter() - g.t0)
        REQS.labels(request.method, ep, resp.status_code).inc()
        tid = g.get("tenant_id")
        if tid is not None:
            TENANT_REQS.labels(str(tid)).inc()
    resp.headers["X-Served-By"] = NODE
    return resp


@app.errorhandler(AuthError)
def _auth_error(_):
    return {"error": "invalid api key"}, 401


@app.errorhandler(psycopg.OperationalError)
def _db_down(_):
    return {"error": "database unavailable"}, 503


# ---------------------------------------------------------------- API
@app.get("/healthz")
def healthz():
    return {"status": "ok", "node": NODE}


@app.get("/readyz")
def readyz():
    status = {"node": NODE, "db": "ok", "redis": "ok", "spool_pending": int(SPOOL_PENDING._value.get())}
    code = 200
    try:
        with db() as conn, conn.cursor() as cur:
            cur.execute("SELECT 1")
    except Exception as e:  # noqa: BLE001
        status["db"] = f"fail: {type(e).__name__}"
        code = 503  # 출근 접수는 스풀로 계속되지만, 정상 상태는 아니다
    try:
        rds.ping()
    except Exception as e:  # noqa: BLE001
        status["redis"] = f"degraded: {type(e).__name__}"
    return status, code


@app.post("/api/clock")
def clock():
    tid = resolve_tenant(request.headers.get("X-Api-Key"))
    body = request.get_json(silent=True) or {}
    emp_no = str(body.get("emp_no", "")).strip()
    kind = body.get("kind", "in")
    if not emp_no or kind not in ("in", "out"):
        return {"error": "emp_no and kind(in|out) required"}, 400

    now = datetime.now(KST)
    ev = {"tenant_id": tid, "emp_no": emp_no, "kind": kind, "work_date": now.date().isoformat(), "ts": now.isoformat()}
    try:
        with db() as conn, conn.cursor() as cur:
            result = _insert_clock(cur, ev, "api")
            conn.commit()
    except psycopg.OperationalError:
        if not SPOOL_ENABLED:
            raise
        spool_append(ev)
        CLOCK.labels("spooled").inc()
        return {"status": "accepted", "spooled": True, "ts": ev["ts"]}, 202

    CLOCK.labels(result).inc()
    if result == "not_found":
        return {"error": "unknown employee"}, 404
    if result == "created":
        try:
            rds.delete(f"t:{tid}:today")
        except redis.RedisError:
            pass
    return {"status": result, "ts": ev["ts"]}, 201 if result == "created" else 200


@app.get("/api/attendance/today")
def today():
    tid = resolve_tenant(request.headers.get("X-Api-Key"))
    key = f"t:{tid}:today"  # 캐시 키에 고객사 ID 를 반드시 넣는다
    try:
        cached = rds.get(key)
    except redis.RedisError:
        cached = None
        CACHE.labels("error").inc()
    if cached:
        CACHE.labels("hit").inc()
        resp = jsonify(json.loads(cached))
        resp.headers["X-Cache"] = "HIT"
        return resp

    CACHE.labels("miss").inc()
    d = datetime.now(KST).date()
    late_after = datetime.combine(d, WORK_START, KST)
    with db() as conn, conn.cursor() as cur:
        as_tenant(cur, tid)
        cur.execute("SELECT count(*) FROM employees")
        total = cur.fetchone()[0]
        cur.execute(
            "SELECT count(*), count(*) FILTER (WHERE ts > %s) FROM attendance WHERE work_date = %s AND kind = 'in'",
            (late_after, d),
        )
        clocked_in, late = cur.fetchone()
    data = {"date": d.isoformat(), "employees": total, "clocked_in": clocked_in, "late": late,
            "not_yet": total - clocked_in}
    try:
        rds.setex(key, CACHE_TTL, json.dumps(data))
    except redis.RedisError:
        pass
    resp = jsonify(data)
    resp.headers["X-Cache"] = "MISS"
    return resp


@app.get("/api/employees/<emp_no>/records")
def records(emp_no: str):
    tid = resolve_tenant(request.headers.get("X-Api-Key"))
    month = request.args.get("month") or datetime.now(KST).strftime("%Y-%m")
    with db() as conn, conn.cursor() as cur:
        as_tenant(cur, tid)
        cur.execute(
            "SELECT work_date, kind, ts, source FROM attendance "
            "WHERE emp_no = %s AND to_char(work_date, 'YYYY-MM') = %s ORDER BY ts",
            (emp_no, month),
        )
        rows = [{"date": r[0].isoformat(), "kind": r[1], "ts": r[2].isoformat(), "source": r[3]} for r in cur.fetchall()]
    return jsonify(rows)


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


# ---------------------------------------------------------------- 시작
os.makedirs(SPOOL_DIR, exist_ok=True)
SPOOL_PENDING.set(_count_pending())  # 재시작 전에 남은 스풀도 이어서 처리
for _ in range(30):
    try:
        init_schema()
        break
    except psycopg.OperationalError:
        time.sleep(2)
threading.Thread(target=_replayer, daemon=True, name="spool-replayer").start()

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000)

# Injection plan — Unit 07 Resilience Engineering

**Student:** Michael Thompson · **Course:** CPS 5981 · **Unit:** 07
**Environment:** Docker Desktop 29.8.2 on Windows 11 (WSL 2 backend); `probe.sh` run from
the bash shell on the Windows host against `http://127.0.0.1:8080`.
**Lab target:** `labs/unit07/` — two Juice Shop v20.0.0 replicas (172.28.7.11, 172.28.7.12)
behind one nginx edge (172.28.7.2), with a shared token-introspection service `idp`
(172.28.7.20) consulted on every `/api/` and `/rest/` call.

> This plan was written and committed **before the first fault was injected.** The
> predictions below are what I expected from reading `edge/nginx.conf`, not what I
> later measured. Where a prediction turned out wrong, the gap is reported as a
> finding in `blast-radius.md`.

---

## Steady state (measured at station 3, before any fault)

Source: `results/probe-baseline.csv` — 30 s probe, 4 endpoints at 1 req/s,
window `2026-11-11T19:50:11Z` → `2026-11-11T19:50:40Z`.

| Endpoint | Requests | HTTP 200 | Mean | Worst |
|---|---|---|---|---|
| `/edge-health` | 24 | 100.0% | 0.035 s | 0.097 s |
| `/` | 24 | 100.0% | 0.036 s | 0.101 s |
| `/rest/admin/application-configuration` | 24 | 100.0% | 0.052 s | 0.143 s |
| `/api/Products` | 24 | 100.0% | 0.159 s | 0.404 s |
| **All** | **96** | **100.0%** | — | **0.404 s** |

**Steady state as one number:** *96 of 96 probe requests return HTTP 200, worst
observed latency 0.404 s.* Load is balanced — `served_by` is `172.28.7.11:3000`
on 36 requests and `172.28.7.12:3000` on 36, and `/edge-health` reports no
upstream at all (24 rows of `-`), because `location = /edge-health` returns a
static 200 inside the edge.

Anything below 100% on `/`, `/api/Products` or
`/rest/admin/application-configuration`, or a latency above roughly 0.5 s, is a
departure from steady state.

## What I read in `edge/nginx.conf` before predicting

1. `upstream juice { server juice-a:3000 max_fails=1 fail_timeout=10s; server juice-b:3000 max_fails=1 fail_timeout=10s; }`
   — two replicas, each ejected after a single failure for 10 s.
2. `proxy_next_upstream error timeout http_502 http_503;` — a failed attempt is
   retried against the other replica, but only for those four conditions.
3. `proxy_connect_timeout 2s; proxy_read_timeout 15s;` — upstream budgets.
4. `location /api/ { auth_request /_auth; ... }` and `location /rest/ { auth_request /_auth; ... }`
   — these two route families are gated on the identity provider. `location / { proxy_pass http://juice; }`
   is **not** gated.
5. `location = /_auth { proxy_pass http://idp:8081/validate; proxy_connect_timeout 2s; proxy_read_timeout 10s; }`
   — one unreplicated dependency, with a 10 s read budget and no `proxy_next_upstream`
   fallback because `idp` is a bare host, not an upstream group.
6. `location = /edge-health { access_log off; return 200 "edge ok\n"; }` — the health
   endpoint a monitor would poll **tests nothing**. It never touches a replica and never
   touches `idp`, and it is excluded from `access.log`.
7. `restart: "no"` on every service in `docker-compose.yml` — a stopped container stays
   stopped until I restore it, so the fault window is the one I choose.

## Scope and safety statement

Every container binds inside the `u07` compose project on the private
`172.28.7.0/24` network; the only published port is `127.0.0.1:8080:80`, so nothing
is reachable off this host. Juice Shop is deliberately vulnerable and is never
exposed beyond loopback. No production system, no cloud account and no third-party
service is touched. Each experiment changes the state of exactly one container,
for 60 seconds, and is followed by its restore command. Faults are injected one at
a time; the stack is confirmed back at steady state before the next one begins.
Total cost: $0.

---

## E1 · Replica loss

**Fault:** `docker compose stop juice-a` for 60 s · **Restore:** `docker compose start juice-a`
**Question:** does redundancy hold when one replica disappears?

**Hypothesis.** If `juice-a` is stopped, then every endpoint keeps returning HTTP 200
and all traffic shifts to `172.28.7.12`, because a stopped container refuses TCP
connections, `proxy_next_upstream error` (nginx.conf line 3 above) treats a refused
connection as `error`, and the request is retried against `juice-b` inside the same
client request. I expect the retry to be cheap rather than slow: `ECONNREFUSED` returns
immediately and does not consume the 2 s `proxy_connect_timeout`.

**Endpoints I predict will NOT return 200 during the fault:** none.

**Predicted worst latency and user-visible effect:** worst case roughly 0.6 s (one extra
connect attempt on top of the 0.404 s baseline worst). A user should see nothing — the
shop stays usable. I do expect a small periodic latency blip roughly every 10 s, because
`max_fails=1 fail_timeout=10s` re-admits `juice-a` to the pool after each 10 s window and
nginx pays one refused connection to discover it is still down.

**What will detect it, and how fast:** the `served_by` column of the probe, within one
tick (1 s), by going all-`172.28.7.12`. `error.log` should carry
`connect() failed (111: Connection refused) while connecting to upstream`. `/edge-health`
will **not** detect it and will stay 200 throughout — it never touches a replica.

**Abort condition:** stop and restore if any container outside the `u07` project changes
state, if the probe shows non-200 on `/edge-health`, if the host becomes unresponsive, or
if I see traffic on any interface other than 127.0.0.1.
**Restore:** `docker compose start juice-a`, then confirm `served_by` alternates again.

## E2 · Shared identity provider down

**Fault:** `docker compose stop idp` for 60 s · **Restore:** `docker compose start idp`
**Question:** what depends on `idp` that I did not expect?

**Hypothesis.** If `idp` is stopped, then `/api/Products` and
`/rest/admin/application-configuration` return HTTP 500 within one tick, while `/` and
`/edge-health` stay 200, because `auth_request /_auth` runs before `proxy_pass` on those
two location blocks and the `/_auth` subrequest will get a refused connection. nginx's
`auth_request` only accepts 2xx, 401 and 403 from the subrequest; any other outcome —
including a failed upstream — is turned into a 500 for the client. There is no second
`idp`, and `proxy_next_upstream` cannot help because `/_auth` points at a single host
rather than an upstream group. The redundancy I have is in the wrong layer: two replicas
of the thing that was not going to fail, one copy of the thing that was.

**Endpoints I predict will NOT return 200 during the fault:** `/api/Products`,
`/rest/admin/application-configuration`.

**Predicted worst latency and user-visible effect:** fast failure, under 0.2 s, because a
refused connection does not wait for `proxy_connect_timeout`. In the browser the Angular
shell should still load (it is served by `location /`), but the product list and the
application-configuration call behind it should fail, so the user sees an empty or
broken shop rather than an error page. Both replicas are healthy the whole time.

**What will detect it, and how fast:** the probe, within one tick, as 500s on the two
gated endpoints. `error.log` should carry an `auth request unexpected status` or
`connect() failed` line for `/_auth`. The thing that will **not** detect it is
`/edge-health`, which stays 200 — so an uptime monitor polling only that endpoint would
report the service healthy for the entire outage. I expect that to be the finding.

**Abort condition:** stop and restore if a container outside `u07` changes state, if the
host becomes unresponsive, if the failure persists more than 30 s after the restore
command, or if traffic appears off 127.0.0.1.
**Restore:** `docker compose start idp`, then confirm both gated endpoints return 200.

## E3 · Shared identity provider hung

**Fault:** `docker compose pause idp` for 60 s · **Restore:** `docker compose unpause idp`
**Question:** is a hung dependency the same as a dead one?

**Hypothesis.** If `idp` is paused rather than stopped, then `/api/Products` and
`/rest/admin/application-configuration` will **hang for about 10 s each and then fail**,
because `docker compose pause` freezes the nginx process inside the container with
SIGSTOP but leaves its listening socket in the kernel. The TCP handshake still completes,
so `proxy_connect_timeout 2s` is satisfied and the request instead burns the full
`proxy_read_timeout 10s` on `/_auth` waiting for a response that never arrives. The
outcome for the client should be the same 500 as E2, reached roughly fifty times more
slowly. I predict this is **worse** than E2, not equal to it: the same two endpoints are
lost, but each loss now occupies an edge worker connection for 10 s, so the failure
consumes capacity as well as availability, and a user is made to wait before being told
no.

**Endpoints I predict will NOT return 200 during the fault:** `/api/Products`,
`/rest/admin/application-configuration`.

**Predicted worst latency and user-visible effect:** about 10.0 s on both gated
endpoints, bounded by `proxy_read_timeout 10s` on `/_auth`. A user clicking through the
shop sees it apparently loading, with a spinner, for ten seconds per call before
anything fails — the state most likely to be mistaken for a slow network rather than an
outage. `/` and `/edge-health` should stay 200 and fast.

**What will detect it, and how fast:** the `seconds` column of the probe, within one
tick, by jumping from ~0.16 s to ~10 s. `error.log` should carry
`upstream timed out (110: Connection timed out) while reading response header from upstream`
for `/_auth`. Again `/edge-health` will not detect it. A latency alert would catch this
one where a status-code alert might not, which is the opposite of E2.

**Abort condition:** stop and restore if a container outside `u07` changes state, if the
host becomes unresponsive, if edge worker connections exhaust and `/` also starts
failing, or if the paused container does not resume within 30 s of `unpause`.
**Restore:** `docker compose unpause idp`, then confirm both gated endpoints return 200
at baseline latency.

---

## Order and discipline

1. Start `docker events` recorder.
2. E1, restore, confirm steady state.
3. E2, restore, confirm steady state.
4. E3, restore, confirm steady state.
5. Stop recorder, copy `access.log` and `error.log` into `results/`.

One fault at a time. Each 150 s block is 30 s steady, 60 s fault, 60 s recovery, so that
both the onset and the recovery of every fault are inside the same measurement window.

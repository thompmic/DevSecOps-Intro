# Control map — Unit 07 Resilience Engineering

**Student:** Michael Thompson · **Course:** CPS 5981 · **Unit:** 07

Every row traces one measured behaviour to the specific line of configuration that
produced it. Line references are to `labs/unit07/edge/nginx.conf` as committed before
Task 4 (`git show HEAD:labs/unit07/edge/nginx.conf`), except where noted.

---

## Observed behaviour → control

| # | Observed behaviour (evidence) | Control that produced it | Layer | Depends on | Logged? |
|---|---|---|---|---|---|
| 1 | All traffic moved to `172.28.7.12` when `juice-a` stopped; 52/52 requests per endpoint stayed 200 (`probe-E1.csv`, 19:53:45–19:54:55) | `proxy_next_upstream error timeout http_502 http_503;` with `upstream juice { server juice-a:3000 …; server juice-b:3000 …; }` | Availability | edge only — the retry is internal to nginx | Yes — `access.log` shows two addresses in `upstream=` on retried requests |
| 2 | `juice-a` ejected from the pool rather than retried on every request | `max_fails=1 fail_timeout=10s` on each `server` line | Availability | edge only | Yes — `error.log` 19:53:46 `upstream server temporarily disabled while connecting to upstream` |
| 3 | Four requests of ~2.0–2.1 s during E1, spaced ~13 s apart (19:53:56, 19:54:10, 19:54:23, 19:54:36) | `fail_timeout=10s` re-admitting `juice-a` every 10 s, each re-probe paying the full `proxy_connect_timeout 2s` | Availability | edge + Docker network behaviour | Yes — `error.log` `(110: Operation timed out) while connecting to upstream` |
| 4 | A stopped container cost 2 s rather than failing instantly | `proxy_connect_timeout 2s;` — a stopped container's address stops answering instead of sending RST | Availability | Docker networking, not nginx | Yes — `error.log` 19:58:15 `connect() failed (113: Host is unreachable)` |
| 5 | All `/api/` and `/rest/` returned 500 when `idp` stopped — 0.0 % success over 104 requests (`probe-E2.csv`) | `auth_request /_auth;` on `location /api/` and `location /rest/` | Authentication | **`idp` — shared by both replicas** | Yes — `error.log` 19:57:45 `auth request unexpected status: 502` |
| 6 | Those 500s took up to 2.3 s, not milliseconds | `proxy_connect_timeout 2s;` inside `location = /_auth` | Authentication | `idp` + Docker networking | Yes — `error.log` 19:57:48 onward, `unexpected status: 504` |
| 7 | A *paused* `idp` produced 500s after ~10 s instead of ~2 s — mean 9.298 s (`probe-E3.csv`) | `proxy_read_timeout 10s;` inside `location = /_auth` | Containment (failed) | `idp` | Yes — `error.log` `auth request unexpected status: 504` through 20:02:15 |
| 8 | `/` stayed 100 % 200 in E1, E2 and E3 | `location / { proxy_pass http://juice; }` — **no** `auth_request` on this block | Availability | replicas only | Yes |
| 9 | `/edge-health` returned 200 on 52/52 (E1), 52/52 (E2), 46/46 (E3) and 54/54 (E2b) while real endpoints sat at 0 % | `location = /edge-health { … return 200 "edge ok"; }` — a string constant | Detection (failed) | nothing, and that is the defect | **No** — `access_log off` on that location |
| 10 | No record anywhere of what the health monitor saw | `access_log off;` in the `/edge-health` block | Detection (failed) | — | **No** |
| 11 | The fault window was exactly the window I chose; nothing self-healed | `restart: "no"` on every service in `docker-compose.yml` | Containment | Docker daemon | Yes — `docker-events.csv` shows no unsolicited `start` |
| 12 | Nothing was reachable off the host | `ports: - "127.0.0.1:8080:80"` in `docker-compose.yml` | Containment | Docker daemon | n/a |
| 13 | Recovery from a hung dependency drained over ~12 s instead of switching back (20:02:05 → 20:02:16) | `proxy_read_timeout 10s` again — in-flight subrequests had to expire or complete | Recovery | `idp` | Yes — `access.log` `rt=` falling 11.3 → 0.3 |
| 14 | After Task 4, `/api/Products` and `/rest/admin/application-configuration` stayed 100 % 200 under the same pause (`probe-E2b.csv`, 54/54 each) | New `location ^~ /api/Products` and `location = /rest/admin/application-configuration`, neither carrying `auth_request` (`task4.diff`) | Availability | replicas only | Yes |
| 15 | `/rest/user/whoami` and `/rest/basket/1` still returned 500 after 10.01 s under the same fault (`E2b-gated-routes.csv`, 20:21:33) | `location /rest/ { auth_request /_auth; … }` still gating everything not carved out | Authentication | `idp` | Yes |

---

## A control that could not express the policy I wanted

Before settling on the route-scoped carve-out in row 14, I tried to make the exemption
**method-aware**, so that `GET` and `HEAD` on the public routes would skip introspection
while `POST`, `PUT` and `DELETE` on the same paths stayed gated:

```nginx
map $request_method $auth_public { default /_auth; GET off; HEAD off; }
location ^~ /api/Products { auth_request $auth_public; proxy_pass http://juice; }
```

`nginx -t` accepted it and the reload succeeded, but **every** `GET /api/Products` then
returned 500 *with `idp` perfectly healthy*. `auth_request` takes `uri | off` as a
literal directive argument; when the value arrives through a variable, the string `off`
is treated as a URI to fetch, that subrequest fails, and the client gets a 500. The
directive cannot be switched off per request. I reverted to the path-scoped carve-out.

This is a finding about the control, not about my configuration. The only exemption
`auth_request` can express is *by route*, never *by method*. Any fail-open policy built
on this control is therefore coarser than the policy a security reviewer would want to
approve — "this path is public" rather than "reading this path is public" — and the gap
has to be closed in the application or not at all.

---

## Independence verdict

**Vendor.** Rows 1–10 and 13–15 are all nginx, and rows 5–7 and 13 are the *same nginx
process*: the edge is one binary reading one file. Rows 11–12 are Docker. Fifteen rows
resolve to two vendors, and the one carrying failover, identity enforcement, health
reporting and logging is a single process. A defect in nginx — or one bad reload — takes
out row 1, row 5, row 9 and the logging in rows 1–8 together. I saw this directly: the
`nginx -s reload` at 20:17:37 changed rows 5, 14 and 15 in one action.

**Failure mode.** Rows 4, 6 and 7 share one failure mode — *waiting on a TCP peer that
will not answer* — differing only in which timeout bounds the wait (2 s connect, 10 s
read). All three encode the same assumption: that an unreachable dependency announces
itself. E1 and E2 disproved it. A stopped container is unreachable, not refusing, so
each of these controls degrades to "pay the timeout" rather than "fail fast". Row 1 is
not independent of row 4 either: a retry is only cheap when the failure is cheap to
detect, and here it was not — the measured cost was 2.1 s per re-probe.

**Operator.** Every control here is edited by one person in two files, applied by one
`docker compose` command, and watched by that same person in one terminal. Nothing
separates the operator who sets the auth policy from the operator who writes the health
check — which is how row 9 came to exist. The health endpoint and the thing it claims to
report on were written by the same hand and never reconciled.

**Verdict: not independent.** Two vendors, one dominant process, one shared failure
mode, one operator. Worse, the redundancy that *is* genuinely independent — two replicas
on two addresses, row 1 — protects the component that was never the problem, while the
component with no redundancy at all, `idp`, is consulted on every gated request by both
replicas. Counting controls overstates the protection: fifteen rows here buy
substantially fewer than fifteen independent ways to survive.

## Which control made recovery slower or less safe than it needed to be?

`proxy_read_timeout 10s` in `location = /_auth` (row 7), with `proxy_connect_timeout 2s`
in the same block a close second.

Ten seconds is a reasonable budget for a user-facing upstream. For a subrequest to an
introspection service on the same host network — where the healthy response arrived in
well under 0.2 s throughout the baseline — it is roughly fifty times longer than the
operation ever legitimately takes. The cost is in `probe-E3.csv`: mean 9.298 s per gated
request, worst 11.327 s, against 2.208 s for the same logical failure when the provider
was merely dead. The outage was identical. The timeout chose how long each user waited
to be told about it.

It also made recovery slower *and the recovery signal less trustworthy*. Because each
in-flight subrequest held its full budget, service did not resume at `unpause`; it
drained from 11.3 s back to 0.3 s over about twelve seconds (row 13), and for eleven of
those seconds the system returned HTTP 200 while being unusable. A status-code alert
would have declared the incident resolved at 20:02:05 — eleven seconds early, with every
user still waiting.

Shortening that single value to roughly 1 s would have converted E3 into E2: the same
loss, declared honestly and quickly, with no other control touched.

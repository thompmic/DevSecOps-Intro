# Observed timeline — Unit 07 Resilience Engineering

**Student:** Michael Thompson · **Course:** CPS 5981 · **Unit:** 07
**Evidence:** `results/probe-baseline.csv`, `probe-E1.csv`, `probe-E2.csv`, `probe-E3.csv`,
`probe-E2b.csv`, `docker-events.csv`, `access.log`, `error.log`, `E2-browser.png`,
`E3-browser.png`, `E2b-gated-routes.csv`, `task4.diff`.
All times are UTC on 2026-11-11. Container event times are taken from
`docker-events.csv` (Docker epoch seconds, converted); request outcomes are taken from
the probe CSVs; log quotes are from `error.log`.

**Plan-first:** `injection-plan.md` was committed at **19:52:41Z**
(`git log -1 --format=%cI` → `2026-11-11T14:52:41-05:00`). The first fault event in
`docker-events.csv` is **19:53:45Z**. The plan predates the first fault by 64 seconds.

---

## Master timeline

| Time (UTC) | Source | Event |
|---|---|---|
| 19:50:11–19:50:40 | probe-baseline.csv | Steady state: 96/96 HTTP 200, worst 0.404 s, `served_by` 36×`.11` / 36×`.12` |
| 19:52:41 | git | `injection-plan.md` committed — **before any fault** |
| 19:53:13 | probe-E1.csv | E1 probe window opens |
| 19:53:43 | shell | `docker compose stop juice-a` issued |
| 19:53:45 | docker-events | `kill u07-juice-a-1` |
| 19:53:46 | error.log | `upstream server temporarily disabled while connecting to upstream` (first) |
| 19:53:50 | docker-events | `die` then `stop u07-juice-a-1` |
| 19:53:56 | probe-E1.csv | First 2 s request: `/api/Products` 200 in **2.115 s** |
| 19:54:10 / 19:54:23 / 19:54:36 | probe-E1.csv | Three more ~2 s requests, ~13 s apart, all 200 |
| 19:54:50 | shell | `docker compose start juice-a` issued |
| 19:54:55 | docker-events | `start u07-juice-a-1` |
| 19:55:03 | error.log | `connect() failed (111: Connection refused)` — replica booting |
| 19:55:44 | probe-E1.csv | E1 window closes. **444/444 = 100 % HTTP 200** |
| 19:56:53 | shell | Steady state re-confirmed, all four endpoints 200 |
| 19:57:11 | probe-E2.csv | E2 probe window opens |
| 19:57:42 | shell | `docker compose stop idp` issued |
| 19:57:44 | docker-events + probe-E2 | `kill u07-idp-1`; **first HTTP 500** on `/api/Products` and `/rest/admin/application-configuration` |
| 19:57:45 | error.log | `auth request unexpected status: 502 while sending to client` (first) |
| 19:57:46 | docker-events | `stop` and `die u07-idp-1` |
| 19:57:48 | error.log | `auth request unexpected status: 504` — the subrequest is now timing out, not being refused |
| 19:58:15 | error.log | `connect() failed (113: Host is unreachable) ... subrequest: "/_auth"` |
| 19:58:51 | shell | `docker compose start idp` issued |
| 19:58:54 | docker-events + probe-E2 | `start u07-idp-1`; **last HTTP 500** |
| 19:59:42 | probe-E2.csv | E2 window closes |
| 20:00:42 | probe-E3.csv | E3 probe window opens |
| 20:01:12 | shell | `docker compose pause idp` issued |
| 20:01:13 | docker-events + probe-E3 | `pause u07-idp-1`; first 500, **after 10.042 s** |
| 20:02:14 | shell | `docker compose unpause idp` issued |
| 20:02:16 | docker-events | `unpause u07-idp-1` |
| 20:03:13 | probe-E3.csv | E3 window closes |
| 20:06:37–20:10:13 | docker-events | Short repeat of the E2 and E3 fault conditions to capture `E2-browser.png` and `E3-browser.png` |
| 20:17:37 | docker-events | `nginx -t` then `nginx -s reload` — Task 4 change applied (`task4.diff`) |
| 20:18:01 | probe-E2b.csv | E2b probe window opens |
| 20:18:31 | shell | `docker compose pause idp` issued (E3 repeated against the changed config) |
| 20:18:32 | docker-events | `pause u07-idp-1` |
| 20:19:38 | shell | `docker compose unpause idp` issued |
| 20:19:39 | docker-events | `unpause u07-idp-1` |
| 20:20:31 | probe-E2b.csv | E2b window closes. **480/480 = 100 % HTTP 200** |
| 20:21:31–20:21:54 | E2b-gated-routes.csv | Gated routes re-checked under the same fault: still fail closed at 10 s |

---

## Per-endpoint results, fault windows only

Each row covers only the 60-second fault window, not the surrounding steady and
recovery periods.

### E1 · `juice-a` stopped (19:53:45 → 19:54:55)

| Endpoint | Requests | HTTP 200 | Worst |
|---|---|---|---|
| `/edge-health` | 52 | 100.0 % | 0.143 s |
| `/` | 52 | 100.0 % | 0.122 s |
| `/api/Products` | 52 | 100.0 % | 2.115 s |
| `/rest/admin/application-configuration` | 52 | 100.0 % | 2.389 s |

`served_by` during the window: 156 requests on `172.28.7.12:3000`, **zero** on
`172.28.7.11:3000`, 52 rows of `-` (`/edge-health`, which never reaches a replica).

### E2 · `idp` stopped (19:57:44 → 19:58:54)

| Endpoint | Requests | HTTP 200 | Worst |
|---|---|---|---|
| `/edge-health` | 52 | 100.0 % | 0.152 s |
| `/` | 52 | 100.0 % | 0.180 s |
| `/api/Products` | 52 | **0.0 %** | 2.208 s |
| `/rest/admin/application-configuration` | 52 | **0.0 %** | 2.299 s |

### E3 · `idp` paused (20:01:13 → 20:02:16)

| Endpoint | Requests | HTTP 200 | Mean | Worst |
|---|---|---|---|---|
| `/edge-health` | 46 | 100.0 % | 0.071 s | 0.339 s |
| `/` | 46 | 100.0 % | 0.066 s | 0.316 s |
| `/api/Products` | 46 | **19.6 %** | **9.298 s** | 11.327 s |
| `/rest/admin/application-configuration` | 46 | **19.6 %** | **9.095 s** | 10.306 s |

The 19.6 % that succeeded were not healthy requests. They are the drain: requests issued
during the pause that were still inside their 10 s budget when `unpause` landed at
20:02:16, so the long-blocked `/_auth` subrequest finally got its 204 and the request
completed late rather than failing. Every request that began and ended inside the pause
waited the full `proxy_read_timeout 10s` and then returned 500.

---

## What alerted, what did not, and after how long

**The probe alerted, in about one tick.** For E2 the stop command was issued at
19:57:42 and the first HTTP 500 is stamped 19:57:44 in `probe-E2.csv` — detection in
**2 seconds**, and the signal was unambiguous because the success rate went to zero
rather than degrading. For E3 the probe caught it just as fast, but on a different
column: the status code stayed 500 only after a ten-second wait, so the *first* signal
available was latency jumping from 0.16 s to 10.04 s at 20:01:13.

**`/edge-health` never alerted, in any experiment.** It returned HTTP 200 on
**47/47 requests during E1, 48/48 during E2, 42/42 during E3 and 50/50 during E2b** —
100 % availability reported while two of four endpoints were at 0 %. This is the
central detection finding. `location = /edge-health { access_log off; return 200 "edge ok\n"; }`
returns a string constant from inside the edge. It does not touch a replica, it does not
touch `idp`, and it cannot fail while nginx itself is running. An uptime monitor polling
only that URL — the normal arrangement — would have reported the service healthy through
every outage in this lab, including the one that took the entire product catalogue
offline for 70 seconds.

**`error.log` alerted, accurately and immediately, but only to someone reading it.**
It carried the right message within 1–3 seconds of each fault and it distinguished the
two identity failures from each other, which nothing else did:

- E1: `upstream server temporarily disabled while connecting to upstream` at 19:53:46,
  and `connect() failed (111: Connection refused)`.
- E2: `auth request unexpected status: 502` at 19:57:45, becoming
  `auth request unexpected status: 504` at 19:57:48, and then
  `connect() failed (113: Host is unreachable) ... subrequest: "/_auth"` at 19:58:15.
- E3: `auth request unexpected status: 504` throughout, to 20:02:15.

Nothing polled or forwarded this file. It is evidence after the fact, not detection.

**`access.log` recorded the user-visible failures but not the health checks.** Every 500
appears there with its `status=` and `rt=` fields. `/edge-health` appears **nowhere**,
because `access_log off` is set on that location. The one endpoint a monitor watches is
the one endpoint that leaves no trace, so after an incident there is no record of what
the monitor saw.

**Timing summary**

| Signal | E1 | E2 | E3 |
|---|---|---|---|
| Probe status code | no change (correctly) | 2 s | 10 s (after the hang) |
| Probe latency | 11 s (first 2 s request) | 2 s | 0 s (first request hung) |
| `/edge-health` | never | never | never |
| `error.log` | 1 s | 3 s | ~2 s |
| Recovery (restore → baseline latency) | n/a | 3 s | ~12 s (drain, below) |

## What a user saw in the browser during E2 and E3

Screenshots: `results/E2-browser.png`, `results/E3-browser.png`, both captured on a hard
reload (Ctrl+Shift+R) with the fault active.

In **E2** the Angular shell loaded normally — header, hamburger, "All Products" banner,
search icon, basket — because `location /` is not gated and both replicas were healthy
the whole time. Inside that intact shell the product grid was **empty**, the paginator
read **"0 of 0"**, and the language selector had fallen back to the literal string
**"placeholder"** because `/rest/admin/application-configuration` returned 500. The shop
displayed **no error message of any kind**. A customer would see a working site that
happens to sell nothing.

In **E3** the end state was the same. The two capture files are in fact **byte-identical
(MD5 `fe6536cabc4b8c2978395674edc9d11d` before PNG conversion)** — the rendered pixels
during a dead identity provider and a hung one are the same image. That identity is the
finding: from the user's side a hung dependency and a dead one are indistinguishable,
and the only difference, the ten seconds spent waiting per call, is precisely the part a
screenshot cannot show. It is visible only in the `seconds` column of `probe-E3.csv`
(mean 9.298 s against E2's 2.208 s worst). During E3 the page sat apparently loading
before arriving at the same empty shop — the state most easily mistaken for a slow
connection rather than an outage.

## Recovery was not instantaneous — E3 drained

Restoring a *stopped* dependency was clean: in E2 the last HTTP 500 is stamped 19:58:54,
three seconds after the `start` command, and the next request was already at baseline
latency. Restoring a *hung* one was not. `probe-E3.csv` shows `/api/Products` recovering
through a visible queue drain rather than a step change:

| Time (UTC) | Status | Latency |
|---|---|---|
| 20:02:04 | 500 | 10.121 s |
| 20:02:05 | 200 | 11.327 s |
| 20:02:07 | 200 | 10.219 s |
| 20:02:08 | 200 | 9.037 s |
| 20:02:09 | 200 | 7.859 s |
| 20:02:10 | 200 | 6.691 s |
| 20:02:12 | 200 | 4.784 s |
| 20:02:14 | 200 | 3.258 s |
| 20:02:15 | 200 | 2.043 s |
| 20:02:16 | 200 | 0.293 s |
| 20:02:18 | 200 | 0.162 s |

Success returned at 20:02:05, but *correct* service did not return until 20:02:16, when
latency fell back under 0.3 s — about twelve seconds after the first 200 and two seconds
after the `unpause` command at 20:02:14. For roughly eleven of those seconds the service
was returning HTTP 200 while taking between four and eleven seconds to do it. Any
status-code-based definition of "recovered" would have declared the incident over at
20:02:05, eleven seconds early, with every user still waiting. This matters for the
Unit 08 distinction between restoring a service and verifying it: 200 is not the same as
recovered.

## Was each failure recorded in access.log / error.log?

| Experiment | In `access.log`? | In `error.log`? | Distinguishable from the others? |
|---|---|---|---|
| E1 | Yes — 200s with `upstream=` showing retries and elevated `rt=` | Yes — `temporarily disabled`, `111: Connection refused` | Yes |
| E2 | Yes — 500s on `/api/` and `/rest/` | Yes — `unexpected status: 502` → `504`, `113: Host is unreachable` | Yes |
| E3 | Yes — 500s with `rt=10.0` | Yes — `unexpected status: 504` only | Yes, by `rt=` and by the absence of a 502 phase |
| `/edge-health` during all three | **No** — suppressed by `access_log off` | No | — |

Both logs are complete and internally consistent with `docker-events.csv` and the probe
CSVs. The gap is not in recording; it is that the one signal anybody was watching was the
one signal that was not recording and could not fail.

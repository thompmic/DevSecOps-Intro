# Blast radius — Unit 07 Resilience Engineering

**Student:** Michael Thompson · **Course:** CPS 5981 · **Unit:** 07

Predictions are quoted from `injection-plan.md`, committed 19:52:41Z, 64 seconds before
the first fault event at 19:53:45Z. Measurements are from the probe CSVs, windowed to
the container events in `docker-events.csv`.

---

## Predicted vs measured

| | Predicted (19:52:41Z) | Measured | Verdict |
|---|---|---|---|
| **E1** endpoints failing | none | none — 52/52 per endpoint at 200 | **Right** |
| **E1** traffic shift | all to `172.28.7.12` | 156 requests on `.12`, zero on `.11` | **Right** |
| **E1** worst latency | "roughly 0.6 s … `ECONNREFUSED` returns immediately" | **2.389 s** | **Wrong** |
| **E1** periodic blip | "roughly every 10 s" from `fail_timeout` | 4 slow requests, ~13 s apart | **Right** |
| **E2** endpoints failing | `/api/Products`, `/rest/admin/application-configuration` | exactly those two, 0.0 % success | **Right** |
| **E2** unaffected | `/`, `/edge-health` | both 100 % | **Right** |
| **E2** worst latency | "fast failure, under 0.2 s" | **2.299 s** | **Wrong** |
| **E2** detection | probe within one tick; `/edge-health` blind | first 500 at 19:57:44, 2 s after the command; `/edge-health` 52/52 at 200 | **Right** |
| **E3** endpoints failing | the same two | the same two, 19.6 % success | **Right** |
| **E3** worst latency | "about 10.0 s, bounded by `proxy_read_timeout 10s`" | mean 9.298 s, worst 11.327 s | **Right** |
| **E3** vs E2 | "worse, not equal" | 9.298 s mean vs 2.208 s worst — 4× slower for the same loss | **Right** |
| **E3** recovery | not predicted | 12-second drain, 11 s of it returning 200 while unusable | **Missed entirely** |

### The gap, stated as the finding

I predicted the *shape* of every failure correctly and the *cost* of two of them wrongly,
in the same direction and for the same reason.

I assumed a stopped container would **refuse** connections — that `ECONNREFUSED` would
come back instantly and the retry in E1 and the failure in E2 would both be nearly free.
Both predictions said "fast". Both measured about 2.3 s. `error.log` names the mechanism
at 19:58:15:

```
connect() failed (113: Host is unreachable) while connecting to upstream,
  ... subrequest: "/_auth", upstream: "http://172.28.7.20:8081/validate"
```

`113` is `EHOSTUNREACH`, not `111 ECONNREFUSED`. When Docker stops a container it tears
down the container's network namespace, so its address stops answering altogether
instead of sending a TCP reset. Nothing refuses the connection, so every path through
that address pays the full `proxy_connect_timeout 2s`. Both `111` and `113` appear in
`error.log` — `111` only in the brief moment at 19:55:03 while a replica was booting and
the namespace existed but nginx inside it did not.

**The finding: in this system there is no such thing as a cheap failure.** Every failure
mode I measured is a *timeout* rather than a *rejection*, so the system's slowest
behaviour is not the pathological case, it is the normal case. The design assumption
behind `proxy_next_upstream` — that a dead replica is discovered quickly and retried
cheaply — does not hold against a container that has been stopped, which is exactly how
containers die in production. E1 looked like a success (100 % availability) and was: but
it bought that availability by paying 2.1 s four times, and a system with a one-second
client timeout would have recorded E1 as an outage while my probe recorded it as perfect.

The second gap is that I predicted nothing about recovery, and recovery turned out to be
where the most dangerous behaviour lives — see *For how long* below.

---

## Who was affected (users, roles)

**E1: nobody.** Availability and correctness were untouched; the only victims were four
requests that took two seconds.

**E2 and E3: every anonymous shopper — that is, every user in the acquisition funnel.**
The two endpoints lost are `/api/Products` (the catalogue) and
`/rest/admin/application-configuration` (the client bootstrap). Losing them removes the
product grid and the application's own configuration, which is the entire browsing
experience. `E2-browser.png` shows the result: the shell renders, the paginator reads
**"0 of 0"**, and the language selector degrades to the literal string **"placeholder"**.

Three things make the user impact worse than the endpoint count suggests:

1. **No error is shown.** The shop does not report a fault. It presents a working store
   with nothing in it. A user concludes the shop is empty or broken, not that it is
   down — and a user who concludes that does not retry later.
2. **Signed-in and anonymous users are affected identically.** The failure is at the
   edge, before any session is considered.
3. **The operator is not affected at all,** which is the real asymmetry. `/edge-health`
   returned 200 on every one of 150 requests across the three experiments (52 + 52 + 46). The people
   watching the dashboard saw a green service for the entire outage.

**Who was *not* affected:** anyone already holding a rendered page. A hash-route change
during the fault still displayed the cached catalogue — I confirmed this before forcing
a hard reload. Impact lands on new sessions and refreshes, which hides it further from
anyone spot-checking an already-open tab.

## Which services and data

| | E1 | E2 / E3 |
|---|---|---|
| Services lost | none | the gated route families `/api/` and `/rest/` |
| Services retained | all | `/` (SPA shell), `/edge-health` |
| Replica health | `juice-b` fully healthy | **both replicas fully healthy throughout** |
| Data lost | none | none |
| Data at risk | none | none |

The critical line is the third one. In E2 and E3 **nothing that stores or serves data
was broken.** Both Juice Shop replicas were up, responding, and fully capable of serving
`/api/Products` — `probe-E2b.csv` proves it, because after Task 4 the identical fault
left those endpoints at 100 %. The outage was manufactured entirely by a control: the
edge refused to *ask* a healthy replica, because a third service that only ever answers
`204` could not be reached. Redundancy was in place and did not help, because it was
redundancy of the thing that was not going to fail.

No data was lost or corrupted in any experiment, and no write path was exercised. This
is an availability blast radius, not an integrity one.

## For how long (time)

| Experiment | Fault window (events) | Time to detect | Time to recover after restore | Period of user-visible failure |
|---|---|---|---|---|
| E1 | 19:53:45 → 19:54:55 (70 s) | n/a — no failure | immediate | 0 s |
| E2 | 19:57:44 → 19:58:54 (70 s) | 2 s (probe) | 3 s | **70 s** |
| E3 | 20:01:13 → 20:02:16 (63 s) | ~1 s (latency) | **~12 s drain** | **~75 s** |

The duration was bounded by me, not by the system. Nothing self-healed — `restart: "no"`
guaranteed that — and nothing alerted, so in a real deployment the duration would have
been bounded by the first user complaint, not by a monitor.

The E3 recovery is the part I did not predict and the part that matters most. Service
did not resume when `idp` was unpaused; it drained:

| 20:02:04 | 20:02:05 | 20:02:08 | 20:02:10 | 20:02:14 | 20:02:16 |
|---|---|---|---|---|---|
| 500 @ 10.12 s | 200 @ 11.33 s | 200 @ 9.04 s | 200 @ 6.69 s | 200 @ 3.26 s | 200 @ 0.29 s |

For eleven seconds the service returned **HTTP 200 while taking four to eleven seconds
to do it**. Any status-code definition of "recovered" would have closed the incident at
20:02:05, eleven seconds early, with every user still waiting. The window in which a
system is *reporting success and delivering failure* is the window in which an operator
stops looking — and it is the direct rehearsal for the Unit 08 problem of proving
recovery rather than declaring it.

## What a larger system would lose (scale it up)

This target is four containers on one host. Hold the topology and change only the scale:

- **The ratio is the problem, and it gets worse with size.** Two replicas depend on one
  identity provider. At two hundred replicas behind the same provider, the same
  `docker compose stop` removes the gated surface of all two hundred. Replica count
  buys nothing against this failure, and the instinct it creates — "we are redundant" —
  is actively misleading. Adding replicas *increases* load on the single provider while
  leaving the single point of failure untouched.
- **The timeout cost compounds into capacity loss.** At 4 requests/second the 10 s hang
  of E3 was an inconvenience. At 1,000 requests/second, 10,000 requests sit in flight
  holding worker connections; `worker_connections 1024` on this edge would be exhausted
  in about one second, at which point `/` — the one route that stayed healthy in every
  experiment here — fails too. **At scale, E3 stops being a partial outage and becomes a
  total one,** through resource exhaustion rather than through the auth gate. My probe
  was far too light to show this, and that is a limit of this measurement, not evidence
  of safety.
- **Blind monitoring scales with the fleet.** One lying health check is a local defect;
  the same check templated across a fleet is a fleet-wide blind spot. Every instance
  reports green by construction, so the aggregate dashboard is green with maximum
  confidence precisely when it is most wrong.
- **Silent failure becomes revenue loss nobody attributes.** Seventy seconds of an empty
  catalogue with no error message, repeated across sessions, appears in business metrics
  as a conversion dip and in engineering metrics as nothing at all — because the
  engineering metric was `/edge-health`, and it was 200 the whole time.

---

## Task 4 — the change, and what it did and did not do

### The decision and its trade-off

**The change** (`task4.diff`, applied and reloaded at 20:17:37): route the two public
read endpoints around the identity gate entirely.

```nginx
location ^~ /api/Products                        { proxy_pass http://juice; }
location = /rest/admin/application-configuration { proxy_pass http://juice; }
```

These sit above `location /api/` and `location /rest/`, so nginx's `^~` and `=` matches
win and those two routes never evaluate `auth_request`. Everything else under `/api/`
and `/rest/` is untouched and still gated.

**Fail open, and for which routes.** These two routes now **fail open**; every other
gated route still **fails closed**. The justification is that the gate on these two was
never doing access-control work: `idp` returns `204` for every request it is asked
about, and the Juice Shop catalogue and bootstrap config are anonymous-readable by
design. The control was costing the entire shopping experience and buying nothing.

**The trade-off, stated honestly.** Fail-open means that if `idp` is ever changed from a
rubber stamp into a real introspection service that can *deny*, these two routes will no
longer honour a denial — a revoked or expired token will still read the catalogue. I am
accepting that in exchange for the catalogue surviving an identity outage, on the
grounds that the data is public. That bargain is only valid while the data stays public;
it is a decision with an expiry date, and it belongs in a review when `idp` becomes
real.

**The second trade-off, which I could not avoid.** The exemption is **by route, not by
method.** `POST /api/Products` now also bypasses introspection at the edge. I tried to
scope it to `GET`/`HEAD` with `map $request_method` and `auth_request $auth_public`;
nginx accepted the config and then returned 500 on every `GET` with `idp` healthy,
because `auth_request` treats a variable value of `off` as a URI to fetch rather than as
a switch (`control-map.md`). The control cannot express the policy. The write path is
currently protected only by Juice Shop's own authorization, not by the edge — acceptable
in a deliberately vulnerable lab target, **not** acceptable in production without moving
this decision into the application.

### Re-measured (E2b)

Same fault as E3 — `docker compose pause idp`, 20:18:32 → 20:19:39 — against the changed
configuration.

| Endpoint | 200 rate before (E3) | 200 rate after (E2b) | Mean before | Mean after | Worst after |
|---|---|---|---|---|---|
| `/edge-health` | 100 % | 100 % | 0.071 s | 0.035 s | 0.087 s |
| `/` | 100 % | 100 % | 0.066 s | 0.033 s | 0.140 s |
| `/api/Products` | **19.6 %** | **100 %** | **9.298 s** | **0.146 s** | 0.378 s |
| `/rest/admin/application-configuration` | **19.6 %** | **100 %** | **9.095 s** | **0.045 s** | 0.124 s |

Across the whole 150-second E2b run: **480 of 480 requests returned HTTP 200.** Mean
latency on `/api/Products` during the fault, 0.146 s, is indistinguishable from the
pre-fault baseline of 0.159 s. The identity provider was frozen for 67 seconds and the
probe cannot tell.

**Blast radius reduction, measured:** availability on the gated public reads went from
19.6 % to 100 %, and mean latency from 9.298 s to 0.146 s — a 64-fold improvement — for
a six-line configuration change requiring no new component, no new dependency and no
restart.

### What the change did not fix

1. **The identity provider is still a single point of failure for everything else.**
   Verified under the same fault at 20:21:33 (`E2b-gated-routes.csv`):
   `/rest/user/whoami` → **500 after 10.013 s**, `/rest/basket/1` → **500 after
   10.011 s**. Sign-in, baskets and checkout — every route that actually needs identity —
   still fail, and still fail slowly. I moved the catalogue out of the blast radius; I
   did not shrink the blast radius for anything that was genuinely gated.
2. **`proxy_read_timeout 10s` on `/_auth` is unchanged**, so every still-gated route
   keeps the 10-second hang and the 12-second drain. The failure is now narrower but
   exactly as slow, and the dishonest "200 while unusable" recovery window still exists.
3. **`/edge-health` still lies.** It returned 200 on 54/54 requests during E2b, as it did
   in every other experiment. Detection is no better than before; I reduced the damage
   while leaving the blindness in place.
4. **`access_log off` on the health route is unchanged,** so there is still no record of
   what a monitor saw during an incident.
5. **The carve-out is path-scoped, not method-scoped** — see the trade-off above.

### Residual risk

**The residual risk I am accepting is that `idp` remains an unreplicated, unmonitored,
slow-failing dependency for every authenticated route, and that the system's only health
signal is still incapable of reporting its failure.** An `idp` outage no longer empties
the shop, but it still prevents every user from signing in, viewing a basket or
checking out, after a 10-second wait each, with the dashboard green throughout. I have
moved the failure from "nobody can shop" to "nobody can buy", which is a smaller radius
but not a smaller consequence for the business.

Ranked next steps, in the order I would actually do them:

1. **Make `/edge-health` tell the truth** — have it exercise `/_auth` and one upstream
   and return non-200 when either fails. This is the highest-value change remaining,
   because it converts every failure in this report from silent to visible, and it costs
   three lines.
2. **Cut `proxy_read_timeout` on `/_auth` from 10 s to ~1 s**, measured against a healthy
   baseline of under 0.2 s. This converts E3 into E2 — the same loss, declared quickly —
   and eliminates both the worker-connection exhaustion risk at scale and the dishonest
   recovery window.
3. **Give `idp` a second instance and an `upstream` block,** so `proxy_next_upstream` can
   do for identity what it already does for the replicas.
4. **Move the public/private read decision into the application,** where it can be
   expressed per method and per object rather than per path prefix.

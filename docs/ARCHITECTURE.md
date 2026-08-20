# Architecture decision record

Written 2026-08-21, from a three-round research pass plus one
cross-model adversarial review. Read the "Still unverified" section
before building on anything here.

**Constraints this was optimised against**, in the owner's stated order:
security first, low operator burden second, room to grow third — with a
US$10/month ceiling that includes the domain and a mailbox, an
amd64-only development fleet, and users in Taiwan.

## The shape

The provisional platform is **Northflank's free Sandbox tier**, in its
Japan region, with its managed Postgres addon. Provisional is the
operative word: that choice is contingent on the first two items under
"Still unverified" below, and Northflank's own documentation states the
free tier "should not be used for production applications" — which is
why the first graduation trigger fires before the first real user, not
when personal data arrives. Every layer below is written so that
swapping the platform is a Dockerfile and a `pg_dump`.

| Layer | Choice | $/mo | Cost to leave |
|---|---|---|---|
| Region | one region for app **and** database, never split | 0 | **high** — irreversible |
| Compute | one managed container, `SOLID_QUEUE_IN_PUMA=true` | 0 | low — a Dockerfile |
| Database | managed Postgres addon, same region | 0 | low — `pg_dump`, ~1h under 10 GB |
| Jobs / cache / cable | Solid Queue + Solid Cache + Solid Cable on the primary Postgres; cache capped ~256 MB | 0 | near-zero toward Sidekiq |
| Auth | `bin/rails generate authentication`; `rodauth-rails` before MFA/passkeys | 0 | **zero** — our own schema |
| Edge | Cloudflare Free: DNS, CDN, managed WAF, Turnstile | 0 | hours — a DNS change |
| CI | GitHub Actions, public repo, hosted runners only | 0 | low |
| Registry | ghcr.io, public package | 0 | hours |
| Backups | encrypted `pg_dump` → object storage with an immutable retention lock | 0 | none |
| Restore drill | weekly, **outside this repo**, alerting on NOT-RUN | 0 | none |
| Errors / analytics | one product-analytics free tier, not an error-only one | 0 | low |
| Domain + mailbox | registrar at cost + a paid mailbox | ~2.45 | low |

**Recurring: about US$2.45/month, all of it the domain and the mailbox.**
Infrastructure is $0 and roughly $7.50 of the ceiling is unspent.

## Why there is no Redis

An **idle** Sidekiq process at default settings issues roughly 9.6–10.1
million Redis commands per month before running a single job:

| Source | commands/month | tunable? |
|---|---:|---|
| `BRPOP` (`TIMEOUT = 2` is a constant in `fetch.rb`, × concurrency 5) | 6,480,000 | only via a custom fetch class |
| Heartbeat (`BEAT_PAUSE = 10`, ~8–10 commands each) | 2.1–2.6M | **no knob at all** |
| Scheduled poller | 1,040,000 | yes |

On per-command pricing that is roughly US$20/month — twice the entire
budget — and tuning everything to the floor still lands near $7 because
the heartbeat cannot be turned down. The vendor's own Sidekiq integration
guide concedes the problem and recommends a fixed plan.

So the conclusion is **not** "Sidekiq is bad". It is that per-command
metered Redis is incompatible with a blocking-poll worker. Solid Queue
keeps the queue in the Postgres we already run, at loopback latency, with
no second service to pay for or patch.

## What was rejected, and the single fact that killed each

- **Render** — no background-worker instance type on the free tier at
  all, free Postgres is deleted 30 days after *creation*, and no Japan
  region.
- **Fly.io** — real Tokyo region, but managed Postgres starts around 5×
  the whole budget, and the affordable shape is a database the vendor's
  own pricing page files under "Unsupported Products".
- **Railway** — the only hard spend-capped platform that fits the budget,
  but its only Asian region is ~60 ms further away than Tokyo. The
  safest-by-billing host and the safest-by-latency host are different
  vendors, and latency is paid on every request.
- **Oracle Always Free** — genuinely $0 and mechanically uncharg­eable
  while the tenancy is never upgraded, but the free tier is **arm64**,
  which manufactures a cross-architecture gap against an all-amd64 dev
  fleet. Compounded by an unannounced halving of the allowance in June
  2026, chronic capacity shortages, and a documented policy of reclaiming
  instances whose CPU stays under 20% — the exact profile of a
  low-traffic prototype. Keep as a free disaster-recovery target only.
- **Supabase** — has the right region and a self-executing DPA on the
  free tier, but its spend cap only exists on the $25/month plan and
  there is nothing between $0 and $25; the free tier pauses after a week
  of inactivity.
- **Heroku** — no Asian region outside an enterprise product, and its
  cheapest plan sleeps after 30 minutes and grants fewer hours than an
  always-on process needs.
- **SQLite + Litestream** — rejected, not dismissed. A serious prototype
  database that would remove this line item entirely, but it welds the
  app and the database to one machine and makes the database the thing
  you migrate at the worst possible moment. Postgres costs nothing extra
  here.
- **A self-managed VM** — maximally portable and the conclusion of the
  first two research rounds, before the objective was corrected. It costs
  *more* than the free tier while adding monthly patching and a backup
  story nobody has rehearsed. See "Practice" below; the operator
  experience is bought as a drill instead of a subscription.
- **Hosted auth (Clerk et al.)** — MFA and passkeys are excluded from the
  free tier, so with security ranked first the real entry price is the
  paid plan on day one; and leaving is the single most expensive
  reversal in the stack.

## Practice, deliberately

This project exists partly to learn on, so operator experience is not
purely a cost. It is bought as a **timed exit drill** rather than a
monthly tax: deploy the whole app onto a small VPS from scratch — own
Dockerfile, restore the database from the backup bucket — record the wall
clock, write it into `docs/RUNBOOK.md`, then shut the machine down.

That yields three things at once: the vendor-independent escape route
becomes *tested* rather than asserted, the hands-on VM experience gets
learned, and the project gains a real recovery-time number. Assume **zero
notice** from any free tier; the platform's terms permit discontinuation
without any.

## Still unverified — do not build on these

- **The free tier's exact vCPU/RAM.** The vendor publishes every paid
  plan's specs and leaves the free row blank; several documentation URLs
  404. Read it in the dashboard and, better, run a real soak test — cold
  boot, migrations, peak RSS, queue lag — before committing. If the
  container is 256 MB-class, Rails will not fit.
- **Whether a paid web service keeps a free database addon.** The
  cheapest upgrade path assumes it does. Nothing documents that. If it is
  false, the realistic bill is roughly double the assumed step.
- **Which city each region identifier actually is.** The regions
  documentation lists identifiers and continental groupings, no cities and
  no cloud provider. Region is irreversible, so do not act on an
  inference from a naming convention.
- **Real RSS for this app.** The 300–500 MB working figure is an
  engineering estimate. Measure it with `docker stats` against the
  generated app.
- **Latency to the actual endpoint.** Measurements so far are ICMP to a
  different vendor's object storage in each region — a proxy, not an
  HTTP/TLS p95 against the real origin.
- **Free-tier WAF and rate-limit specifics at the edge.** What *is*
  confirmed: one IP-only rate-limit rule with a ten-second maximum block,
  and 24 hours of security-event retention. That is a perimeter, not a
  rate limiter and not an audit trail — so rate limiting uses Rails 8's
  built-in `rate_limit`, and the audit log lives in our own database.
- **The vendor's DPA, sub-processor list, and backup residency**, which
  matter before any real personal data.
- **The local breach-notification deadline in hours.** The statutory duty
  and penalty bands are confirmed; the hour count lives in a sector
  regulation that was not read. Do not assume 72 hours.

## Graduation triggers

Named events that force a change, so the decision is made in advance
rather than during an incident.

- **Before the first real external user** — the free tier is documented
  by its own vendor as not for production use. Move to a paid plan or a
  tested alternative *then*, not when personal data arrives.
- Free container too small under a real soak test → step up one compute
  plan; do not retreat to SQLite.
- More than ~3 app instances → add a connection pooler **before** scaling
  horizontally, not during the incident.
- Real users with personal data → obtain the DPA in writing, turn on an
  in-application audit log, and read the local notification duty.
- MFA or passkeys on the roadmap → migrate to `rodauth-rails` first.
- Transactional email approaching **100 messages in any single day** —
  the daily cap bites long before the monthly one and fails silently.
- Monthly egress past ~50 GB → check the cache-hit ratio before paying,
  and move user-uploaded blobs to zero-egress object storage.
- The CI job that restores a dump onto vanilla Postgres stops passing →
  the database is no longer portable; that is the signal to move to a
  managed Postgres you have chosen deliberately.

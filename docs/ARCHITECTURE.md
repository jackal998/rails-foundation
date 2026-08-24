# Architecture decision record

Written 2026-08-21, from a three-round research pass plus one
cross-model adversarial review. Read the "Still unverified" section
before building on anything here.

**Constraints this was optimised against**, in the owner's stated order:
security first, low operator burden second, room to grow third — with a
US$10/month ceiling that includes the domain and a mailbox, an
amd64-only development fleet, and users in Taiwan.

## The shape

The provisional platform is **Northflank**, with its managed Postgres
addon. Provisional is the operative word: Northflank's own documentation
states the free tier "should not be used for production applications" —
which is why the first graduation trigger fires before the first real
user, not when personal data arrives. Every layer below is written so
that swapping the platform is a Dockerfile and a `pg_dump`.

> **Correction, 2026-08-23 — this said "free Sandbox tier, in its Japan
> region". That combination does not exist.** Read in the live product:
> the free tier can deploy to exactly two regions, `us-central`
> (Council Bluffs, Iowa) and `europe-west` (London). All fifteen others,
> `asia-northeast` (Tokyo) included, are marked *Upgrade to pay as you
> go to use this region*. Evidence and the full region table:
> [`pre-build-research/2026-08-23-northflank-free-tier.md`](pre-build-research/2026-08-23-northflank-free-tier.md).
>
> So the tier and the region are now a choice, not a given: **free but
> far** (Iowa/London), or **near but paid** (Tokyo, from $5.40/month for
> the app container alone, before the database). That choice is the
> owner's and has not been made. It is deliberately *not* being made now
> — see "What this correction disturbs" below.

The `$/mo` column below was written assuming the free tier. Since the
free tier turns out to be Iowa/London-only, the three rows marked † are
`0` **only if the latency of those two regions is acceptable**; in Tokyo
they are metered.

| Layer | Choice | $/mo | Cost to leave |
|---|---|---|---|
| Region | one region for app **and** database, never split | 0 † | **high** — irreversible |
| Compute | one managed container, `SOLID_QUEUE_IN_PUMA=true` | 0 † | low — a Dockerfile |
| Database | managed Postgres addon, same region | 0 † | low — `pg_dump`, ~1h under 10 GB |
| Jobs / cache / cable | Solid Queue + Solid Cache + Solid Cable on the primary Postgres; cache capped ~256 MB | 0 | near-zero toward Sidekiq |
| Auth | `bin/rails generate authentication`; `rodauth-rails` before MFA/passkeys | 0 | **zero** — our own schema |
| Edge | Cloudflare Free: DNS, CDN, managed WAF, Turnstile | 0 | hours — a DNS change |
| CI | GitHub Actions, public repo, hosted runners only | 0 | low |
| Registry | ghcr.io, public package | 0 | hours |
| Backups | encrypted `pg_dump` → object storage with an immutable retention lock | 0 | none |
| Restore drill | weekly, **outside this repo**, alerting on NOT-RUN | 0 | none |
| Errors / analytics | one product-analytics free tier, not an error-only one | 0 | low |
| Domain + mailbox | registrar at cost + a paid mailbox | ~2.45 | low |

**Recurring: about US$2.45/month, all of it the domain and the mailbox** —
*if* the free tier is used, which now means Iowa or London. Infrastructure
is then $0 and roughly $7.50 of the ceiling is unspent.

In Tokyo the same shape is metered. Observed unit prices, 2026-08-23:
CPU $0.01667/vCPU/hr, memory $0.00833/GB/hr, egress $0.06/GB, disk
$0.15/GB/month. The smallest plan a Rails 8.1 container actually fits in
is `nf-compute-20` — 0.2 shared vCPU, 512 MB, **$5.40/month** — and that
is the app alone, before the Postgres addon. See the measured RSS under
"Still unverified" below: the foundation already uses 269.1 MiB of that
512 MB with no features in it. With the domain and mailbox
at $2.45, the US$10 ceiling has roughly $2.15 left to cover a database.
That is arithmetic over observed prices, not a quote: the addon's price
has not been looked up.

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
  vendors, and latency is paid on every request. *(2026-08-23: this
  rejection is the one most disturbed by the region correction — see
  below.)*
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

## What this correction disturbs — and why it is not being re-decided now

Northflank won this comparison on a specific conjunction: **a Japan
region, always-on, a free Postgres that is neither deleted nor paused,
amd64, at $0.** Render and Heroku were rejected partly for having no
Asian region; Railway was rejected for being ~60 ms further than Tokyo.
Latency was doing real work in that argument.

The correction splits that conjunction in two, and each half weakens a
different part of the case:

- **Free tier → Iowa or London.** Northflank then fails the very
  criterion it beat Render, Heroku and Railway on. A free container in
  Council Bluffs is not 60 ms further than Tokyo; it is a different
  order of distance. Whatever else is true, "free *and* near" is off
  the table.
- **Tokyo → pay-as-you-go, and a card on file.** That is the branch
  where Railway's hard spend cap stops being a nicety. With security
  ranked first, "the free tier is the mechanical guarantee the card
  cannot be charged" was load-bearing, and this branch removes it.
  Northflank shows a *$50 billing limit*, but the observed wording is
  "$50.00 until your next invoice, or at the end of the month —
  whichever comes first", which reads as an **invoicing threshold, not a
  spend cap**. **Unverified — do not treat Northflank as spend-capped
  until someone confirms it in writing.**

So the honest status is: the platform decision is **reopened, not
reversed**. Northflank may still win; the argument that put it first
just lost a leg.

It is deliberately not being re-run right now, for one reason: **the
first bake-off was decided from documentation, and documentation is
exactly what was wrong here.** Re-running it on paper would repeat the
mistake at higher confidence. This document already prescribes the
remedy in the two sections below — a real soak test and a timed exit
drill — and both need an application that does not yet exist.

The dependency therefore runs the opposite way to how it was assumed:
**the foundation is not blocked by the platform; the platform decision
is blocked by the foundation.** Nothing in the layer table is
platform-specific — a Dockerfile, plain Postgres, Solid Queue on that
Postgres, our own `users` table, Cloudflare, GitHub Actions, ghcr.io,
`pg_dump` to object storage. Build that, measure it, then choose with
numbers instead of vendor pages.

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

- ~~**The free tier's exact vCPU/RAM.**~~ **Settled 2026-08-24** by
  creating a throwaway free project and reading the compute-plan
  selector. Free projects may select exactly two plans:

  | Plan | vCPU | Memory |
  |---|---|---|
  | `nf-compute-10` | 0.1 shared | 256 MB |
  | **`nf-compute-20`** | **0.2 shared** | **512 MB** |

  Every larger plan, from `nf-compute-50` through `nf-compute-800-32`,
  is greyed out and labelled *"Not available due to free project
  limits"*. Autoscaling is likewise *"not available on free projects"*.

  So the free ceiling is **0.2 shared vCPU / 512 MB**, and the measured
  269.1 MiB footprint **fits**, at roughly 53% at rest. The earlier fear
  that the free tier was 256 MB-class — which would have ruled Rails out
  entirely — was wrong.

  **The CPU half was settled the same night** by rebuilding that exact box
  locally — this repo's production image and `postgres:17-alpine`, each in
  `--cpus=0.2 --memory=512m`. It boots and serves: first HTTP 200 at 19.2 s
  including `db:prepare`, then 100 requests at concurrency 10 all returning
  200 at 21.4 req/s, p90 556 ms, settling at 273.7 MiB of the 512 MB with
  no OOM kill and no restart. Solid Queue really runs inside Puma — its
  four processes register themselves in the queue database.

  One caveat belongs with that number: `--cpus` is a hard quota while
  Northflank's share is *shared* and may burst, so this was the stricter
  test of the two. Full method and figures:
  [`pre-build-research/2026-08-24-free-tier-box-test.md`](pre-build-research/2026-08-24-free-tier-box-test.md).
- **Whether a paid web service keeps a free database addon.** The
  cheapest upgrade path assumes it does. Nothing documents that. If it is
  false, the realistic bill is roughly double the assumed step.
- ~~**Which city each region identifier actually is.**~~ **Settled
  2026-08-23.** The *documentation* still omits cities, but the
  create-project UI shows `identifier · City` on every row —
  `asia-northeast · Tokyo`, `us-central · Council Bluffs`,
  `asia-east · Hong Kong`. The irreversible choice can be made with the
  physical location in view. The old guess that `asia-east` meant Taiwan
  was wrong: it is Hong Kong.
- **Real RSS for this app.** **Settled 2026-08-23**, measured against
  the actual production image of this repository — built from the
  committed Dockerfile, booted with `SOLID_QUEUE_IN_PUMA=true` against a
  real Postgres, migrations applied by the entrypoint:

  | Configuration | Container memory |
  |---|---|
  | web only, Solid Queue off | 109.7 MiB |
  | web + Solid Queue in Puma, idle after boot | 232.8 MiB |
  | same, after 200 requests, settled | **269.1 MiB** |

  Those figures are after two deliberate trims. Before them the settled
  number was 287.6 MiB: the image shipped the test group's gems, and
  `ruby-vips` was loaded at boot by `Bundler.require`, which dlopens
  libvips in every process. Excluding the test group and making the vips
  binding load on demand took 18.5 MiB off the runtime and 76 MB off the
  image (529 MB to 453 MB). Recorded because it shows how much of a small
  plan is spent on things the app never asked for.

  Solid Queue inside Puma therefore costs about **127 MiB** — more than
  half the footprint, and the true price of having no Redis and no second
  container. Verified rather than inferred from the flag: with it on,
  four processes register in `solid_queue_processes` (Dispatcher,
  Scheduler, Supervisor(fork), Worker); with it off, zero.

  This supersedes both the 300–500 MB estimate and the earlier 205.2 MiB
  figure, which was a blank generated app. 287.6 MiB is a foundation with
  **no features yet**, so against `nf-compute-20` (512 MB) it sits at
  roughly 53% at rest before a single line of product code. A 256 MB plan
  is out. Whether 512 MB survives real code and real traffic is what a
  soak test still has to answer — and if it does not, the next rung is
  `nf-compute-50` at $12/month, which exceeds the entire budget on
  compute alone.
- ~~**Latency to the actual endpoint.**~~ **Settled 2026-08-24**, against
  this application's own deployed origin rather than a proxy for it: 30 of
  30 requests from Taiwan to `us-central` returned 200, median **693 ms**,
  p90 782 ms. The same page served from the local box was 82 ms, so the
  difference is the Pacific crossing and TLS, not the app. Whether 693 ms
  is acceptable is a judgement rather than a measurement — the graduation
  trigger below is where that call gets made.
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

## The free tier is not card-free — found 2026-08-24

Creating the managed Postgres addon in a free project raises a modal
titled **"Add a payment method"**, with fields for card number, expiry
and CVC. Its own text:

> We require a payment method to verify legitimate users and deter from
> hosting content that goes against our terms of service.
> **You will not be charged for any usage while on the Developer
> Sandbox.** Once a valid card is added, you will be able to create the
> following: One free project with limited resources.

Creating the *project* did not ask for a card. Creating the *addon* did.

This matters more than the plan sizes, because the billing-safety
argument in this document rested on a property that turns out not to
exist: **"no payment method on file, therefore the card cannot be
charged" is not available on Northflank's free tier.** Using the free
tier at all means putting a card on the account.

That does not make Northflank wrong — the vendor states usage on the
Sandbox is not charged, and a stored card is normal industry practice.
It does mean the choice is no longer "free tier = mechanically safe" vs
"paid = card exposed". Both branches now involve a stored card, so the
protection has to be bought some other way: a hard spend cap, a billing
alert, or a card whose limit is small enough that the worst case is
survivable. `CLAUDE.md` bans clicking *Upgrade to Pay As You Go*; that
ban is unaffected, but it is no longer sufficient on its own.

**Not verified:** whether the card is required to create a free project
from scratch on a fresh account, or only to create resources within one.
The project here was created before the prompt appeared, so the two
cannot be separated from this evidence alone.

### There is no hard spend cap — read from the docs, 2026-08-24

Evidence tier: the vendor's own documentation, not something observed in
an account. Weaker than the measurements elsewhere in this file, and it
should be re-checked inside the billing UI before anyone relies on it.

- The card requirement is policy, not an accident of the flow this repo
  happened to walk: *"All users must add a payment method to start
  creating resources on Northflank, regardless of plan selection."*
- **The control named like a limit is a charge trigger.** *"Billing
  thresholds trigger automatic billing when your usage reaches predefined
  spending limits."* Reaching one raises an invoice and **charges the
  card**; it does not stop the resources. New accounts default to **$50**,
  the selectable values are $50 / $100 / $250 / $500, **there is no zero**,
  and turning it off requires contacting support.
- **Billing alerts only send email.** *"you will be notified on the
  registered email address"* — no suspension, no block.
- Suspension happens *after* a charge fails, not instead of one: services
  are suspended when a threshold invoice cannot be paid.

So the honest position is that **Northflank offers no mechanism that
mechanically prevents a charge.** What protection exists is of three
kinds, and only the first is mechanical:

1. **The platform itself refuses non-free plans on a free project** —
   observed directly: every plan above `nf-compute-20` is greyed out and
   labelled *"Not available due to free project limits"*, and autoscaling
   is off. Leaving the free tier therefore takes a deliberate upgrade
   action, which `CLAUDE.md` already bans.
2. **A free project accrues $0**, so a $50 threshold is never approached
   while the ban above holds.
3. **The card's own limit** is the only backstop that does not depend on
   the platform behaving as documented.

That is a defensible position, but it is a different one from the
argument this document originally made, and it should be stated as what
it is: risk that is *bounded and managed*, not risk that is *impossible*.

## One database is enough — found 2026-08-24

The free Postgres addon provisions a single database, named once at
creation and immutable afterwards, and a stock Rails 8.1 production
`database.yml` declares four (primary, cache, queue, cable). Whether the
addon's user may `CREATE DATABASE` was the last open blocker, and it could
not be tested without putting a card on the account.

It no longer needs testing. All four roles were pointed at one physical
database locally, inside the free-tier box, and the result runs — and runs
**better** than the four-database layout: 26.3 req/s against 21.4, and
about 14 MiB less memory, because it maintains one connection pool instead
of four.

It does need one provisioning step that is not obvious. Rails 8.1 ships
the Solid databases as schema files with **no migration directories**, so
`db:prepare` populates them only along the path it takes when a database
does not exist, and `db:migrate:cache` has nothing to run. Against the
addon's empty database, once, before any data exists:

```sh
DISABLE_DATABASE_ENVIRONMENT_CHECK=1 \
  bin/rails db:prepare db:schema:load:cache \
            db:schema:load:queue db:schema:load:cable
```

That override is a provisioning step for an empty database and nothing
else. Rails refuses `db:schema:load` in production because it is
destructive, and it is right to; anything that automates this must assert
the database is empty in the same command, not in a comment above it.

Worth recording separately, because it nearly went into this document as a
success: the first attempt at this configuration **served HTTP 200 and was
dead a minute later**, and its container exited with **code 0**. Thruster
answers on port 80 before Puma's forked Solid Queue plugin finishes
failing, and an unhandled exception in that fork exits cleanly. Liveness at
one instant is not liveness, and an exit code is not a verdict.

## Graduation triggers

Named events that force a change, so the decision is made in advance
rather than during an incident.

- **Before the first real external user** — the free tier is documented
  by its own vendor as not for production use. Move to a paid plan or a
  tested alternative *then*, not when personal data arrives.
- **Before any card is attached to any platform** — re-run the
  Northflank-vs-Railway comparison with the spend-cap question settled
  in writing. Attaching a card removes the one mechanical guarantee that
  the budget cannot be exceeded, so it is the moment the billing-safety
  property has to be bought back some other way.
- **The measured p95 from Taiwan to the chosen free region exceeds what
  the app can live with** — then "free" has been paid for in latency,
  and the choice is Tokyo-with-a-card or a different vendor. Measure
  before assuming; the only latency numbers on record are ICMP to a
  different vendor's endpoints.
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

# Does this app run inside the free tier's box? — 2026-08-24

**Every number here was measured on this machine.** Nothing is quoted from
a vendor page, and nothing is inferred from a similar app.

The free tier's ceiling was read directly from the product the night
before: `nf-compute-20`, **0.2 shared vCPU / 512 MB**, for both a service
and the Postgres addon, with nothing larger selectable and autoscaling
switched off. Memory had been measured before that (269.1 MiB) and fit.
**CPU had never been tested at all.**

That gap mattered more than the billing question it was sitting behind.
If Rails cannot boot in 0.2 of a vCPU, no amount of card-and-billing
reasoning is worth having, so it was settled first — locally, for free,
touching no account.

## Method

Two containers, each capped at exactly the free-tier plan, on their own
network and their own throwaway volume:

```sh
docker run --cpus=0.2 --memory=512m …   # the Rails production image
docker run --cpus=0.2 --memory=512m …   # postgres:17-alpine
```

The Rails image is the production stage of this repo's committed
Dockerfile, built locally, running `RAILS_ENV=production` with
`SOLID_QUEUE_IN_PUMA=true`, behind Thruster, with the entrypoint
performing its own `db:prepare`.

(This said "the same artifact CI builds". On the day it was written CI
built no image at all — every job ran on the runner with
`ruby/setup-ruby`. A `production-image` job was added 2026-08-25 and does
build it; the sentence was corrected rather than quietly made true,
because the measurements below were taken before that job existed.)

**Honest limit, stated up front:** `docker --cpus=0.2` is a hard CFS
quota. Northflank says *shared* vCPU, which may permit bursting above the
share when the host is idle. So a pass here is strong evidence — we were
stricter than production is likely to be — while a failure here would
have been weaker, since production might burst where this throttled.

## Result 1 — the stock four-database configuration fits

| Measurement | Value |
|---|---|
| Postgres time to `pg_isready` | 9.8 s |
| Container start → first HTTP 200 (incl. `db:prepare`) | 19.2 s |
| Databases created by the entrypoint | `app_production`, `_cache`, `_queue`, `_cable` |
| Latency, 20 sequential requests | median 82 ms, p90 366 ms, max 563 ms |
| 100 requests at concurrency 10 | **100/100 → 200**, 21.4 req/s, median 331 ms, p90 556 ms, max 1.081 s |
| App memory after that load | **273.7 MiB / 512 MiB (53%)** |
| Postgres memory | 105.5 MiB / 512 MiB (21%) |
| OOM kills / restarts | 0 / 0 |

The page served was verified to be the real one — this repo's layout, its
`<title>App</title>`, a CSRF token — not an error page rendered with a
200. Solid Queue was verified live the same way: the queue database held
13 `solid_queue_*` tables and four registered processes (`dispatcher`,
`worker`, `scheduler`, `supervisor(fork)`). The image has no `ps`, so the
database's own process registry is the evidence, which is better anyway.

**Verdict: the free-tier box is not the constraint it was feared to be.**
Roughly half the memory and most of the CPU are still unspent.

## Result 2 — the single-database fallback works, but not the obvious way

The free Postgres addon provisions **one** database, named once at
creation and immutable afterwards. Whether its user may `CREATE DATABASE`
is still unknown and cannot be tested without a card on the account. So
the more useful question is whether that even matters: can Rails run all
four of its production databases inside one physical database?

It can. The first two attempts said otherwise, and both were wrong in an
instructive way.

### Attempt 1 — the false pass

All four `*_DATABASE_URL` variables pointed at one database. The app
served **HTTP 200 after 13.5 s**. Reported at that point, this would have
gone into the architecture record as "the fallback works".

It did not work. The database held `users` and `sessions` and **zero**
`solid_queue`, `solid_cache` or `solid_cable` tables, and the container
was dead within a minute — Puma forks the Solid Queue supervisor, which
queries `solid_queue_recurring_tasks`, raises `PG::UndefinedTable`, and
takes the process down.

Two things about that failure are worth keeping:

- **A 200 arrived before the crash.** Thruster binds port 80 and starts
  answering before Puma's forked plugin has finished failing. Liveness at
  one instant is not liveness.
- **The exit code was 0.** A container that died from an unhandled
  exception in a forked plugin reports a clean exit. Any check reading
  exit codes would have called it a success.

Every later attempt therefore carries an explicit *still alive 45 seconds
later, still serving* assertion. That single check is what separated the
working configuration from two convincing failures.

### Attempt 2 — the wrong tool, and a guard doing its job

`db:prepare` had skipped the three Solid databases because it deduplicates
by database name: same name, already handled. The obvious repair was to
migrate them explicitly.

```
rails db:migrate:cache db:migrate:queue db:migrate:cable   # exit 0, no effect
```

Exit 0, nothing created. Reaching for `db:schema:load:*` instead produced:

```
ActiveRecord::ProtectedEnvironmentError: You are attempting to run a
destructive action against your 'production' database.
```

That guard was **not** disabled to get past it. The cause was found first.

### The cause

Rails 8.1 ships the Solid databases as schema files and nothing else:

```
db/cache_schema.rb   db/queue_schema.rb   db/cable_schema.rb
db/cache_migrate/    db/queue_migrate/    db/cable_migrate/   ← none exist
```

So `db:migrate:cache` has zero migrations to run — hence exit 0 and no
effect — and `db:prepare` populates those databases only along the path it
takes when the database **does not exist**, which is to load the schema
file. Point four roles at one existing database and that path is never
taken for three of them.

The only route into an already-existing database is `db:schema:load:<name>`,
and that is a destructive task by definition.

### The working recipe

Provision once, against the empty database the addon hands over, before
any data exists:

```sh
DISABLE_DATABASE_ENVIRONMENT_CHECK=1 \
  bin/rails db:prepare \
            db:schema:load:cache \
            db:schema:load:queue \
            db:schema:load:cable
```

**The override is bounded and must stay bounded.** It is a provisioning
step for a database that has never held a row — verified empty
(`count(*) from information_schema.tables` = 0) immediately before it ran.
It is never correct to run this against a database with data in it; that
is precisely what the guard exists to prevent, and the guard is right.
Anything automating this must assert emptiness first, and the check
belongs in the same command as the override, not in a comment above it.

Measured afterwards, all four roles on one database:

| Measurement | Value |
|---|---|
| Tables created | 13 `solid_queue_*`, 1 `solid_cache_*`, 1 `solid_cable_*` |
| `users` + `sessions` after the three schema loads | **still present** — the loads are additive |
| Container start → HTTP 200 | 15.7 s |
| **Alive and serving 200 at 45 s** | **yes** — the check both failures failed |
| Solid Queue processes registered | `dispatcher`, `worker`, `scheduler`, `supervisor(fork)` |
| `Rails.cache` write → read | returned `"ok"` |
| 100 requests at concurrency 10 | **100/100 → 200**, **26.3 req/s**, median 281 ms, p90 481 ms |
| App memory after load | **259.9 MiB / 512 MiB (51%)** |
| OOM kills / restarts | 0 / 0 |

The single-database configuration is **faster and lighter** than the
four-database one — 26.3 req/s against 21.4, and about 14 MiB less
memory — because it maintains one connection pool instead of four. On a
0.2 vCPU plan that is not a rounding error.

## What this changes

**N2 is no longer a blocker.** The open question was whether the free
addon's user may `CREATE DATABASE`; the answer no longer gates anything,
because a configuration that never needs a second database has been shown
to work. If the privilege turns out to exist, the stock four-database
layout is available; if it does not, the single-database layout is, and it
performs better. Either way this does not require putting a card on the
account to find out.

## Still untested

- **Bursting.** Whether Northflank's *shared* 0.2 vCPU behaves better or
  worse than a hard local quota under a noisy neighbour. Not knowable
  without deploying.
- **This is a foundation with no features.** 51% of the memory budget is
  spent before any product code exists. The measurement to repeat is the
  same one, later, with real features in it.
- **Cold-start behaviour on the platform**, including whether a free
  service is suspended when idle.
- **The addon's actual throughput** on its own 0.2 vCPU under real load,
  as opposed to a local Postgres serving one client.

## Reproducing

The scripts are not committed — they read `.env` and `config/master.key`
and build connection URLs containing the password, which is exactly the
shape this repo's gitleaks rule exists to catch. The commands above are
the whole method; recreating them takes minutes and is safer than storing
a script that must be handled carefully forever.

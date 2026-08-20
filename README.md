# rails-foundation

A Rails 8 foundation with the boring parts already decided: one always-on
container, Postgres, CI/CD, backups that have actually been restored.

**Status: scaffolding.** The application does not exist yet. This repo
currently holds the guard rails that have to be in place *before* the
first line of app code, because several of them stop being useful the
moment a secret has already been committed.

## Shape

| | |
|---|---|
| Framework | Rails 8, Postgres |
| Background jobs | Solid Queue, running **inside** the Puma process |
| Cache / cable | Solid Cache + Solid Cable, on the same Postgres |
| Redis | none — deliberately |
| Container | one, not three |
| CI | GitHub Actions on GitHub-hosted runners only |
| Backups | encrypted `pg_dump` to object storage with an immutable retention lock, plus a scheduled restore drill that asserts row counts |

No Redis and one container are the same decision: Solid Queue keeps the
queue in the database the app already has, and Rails 8's generated
`puma.rb` collapses web and worker into a single process behind one
environment variable. An idle Sidekiq worker issues roughly 10 million
Redis commands a month before running a single job — on per-command
pricing that is more than this entire stack costs.

All four job backends (Solid Queue, GoodJob, Sidekiq, delayed_job) are
Active Job adapters, so this is a cost decision, not a lock-in one.
Solid Queue → Sidekiq is a config line; the reverse is a weekend. Hence
starting here.

## Repository conventions

- `CLAUDE.md` — standing rules, including three decisions that cannot be
  cheaply undone and a list of operational bans that each have a specific
  failure behind them. Read it before changing infrastructure.
- `.claude/rules/portable-core.md` — baseline working rules for any agent
  or contributor; written to travel between repos.
- `docs/ARCHITECTURE.md` — why this shape, what was rejected and on which
  single disqualifying fact, and **what is still unverified**.

## Licensing

There is no LICENSE file, which means all rights are reserved. This
repository is public so the project can use the free tier that comes with
public repositories — branch rulesets, unlimited Actions minutes, code
scanning — not as an invitation to reuse the code.

## Local setup

Not yet written — it lands with the application in the next commit. It
will be a single `docker compose up`, with the repository living on a
Linux filesystem (inside WSL on Windows, never under `/mnt/c`, where
containers receive no file-change events and hot reload silently stops
working).

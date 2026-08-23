# rails-foundation

A Rails 8 foundation with the boring parts already decided: one always-on
container, Postgres, CI/CD, backups that have actually been restored.

**Status: the application exists.** Rails 8.1 with the built-in
authentication generator, Solid Queue / Cache / Cable on Postgres, a
public landing page, and CI that runs tests, RuboCop, Brakeman,
bundler-audit and importmap audit. Not yet deployed anywhere — the
hosting decision is open, see `docs/ARCHITECTURE.md`.

## Shape

| | |
|---|---|
| Framework | Rails 8.1, Postgres |
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

## Local setup

Requires Docker. Everything runs in containers; nothing is installed on
the host.

```sh
cp .env.example .env
# put a generated value in POSTGRES_PASSWORD, e.g.
#   ruby -rsecurerandom -e 'puts SecureRandom.alphanumeric(24)'

docker compose run --rm app bin/rails db:prepare
docker compose up
```

Then <http://127.0.0.1:3000>. The health endpoint is `/up`.

```sh
docker compose run --rm -e RAILS_ENV=test app bin/rails db:test:prepare test
docker compose run --rm app bin/rubocop
docker compose run --rm app bin/brakeman --no-pager
```

`compose.yaml` builds the **`dev` stage of the same Dockerfile** that
produces the production image, so local, CI and production cannot drift
onto different base images or Ruby versions. `docker build` with no
`--target` still builds the production stage — the dev stage
deliberately sits above it in the file, because Docker builds the *last*
stage by default.

### On where the repository lives

Keep the working copy where your **git hooks actually run**. The
pre-commit secret scan is configured globally via `core.hooksPath`, and
if that path is not reachable from the environment you commit in, the
hook **fail-opens**: it prints a line to stderr and exits 0, so a commit
that should have been blocked simply succeeds. On Windows that means
committing from the Windows side rather than from a Linux filesystem
that cannot see the hook.

An earlier version of this file claimed the repository had to live on a
Linux filesystem because containers receive no file-change events
otherwise. That is not true for this app: Rails 8.1 ships no `listen`
gem and falls back to `ActiveSupport::FileUpdateChecker`, which polls,
and polling works across the mount. The cost is speed, not correctness —
and speed is the cheaper thing to lose.

## What CI enforces

Beyond the usual test/lint/scan jobs, one job exists purely as an
enforcement mechanism rather than a test:

**`database-portability`** dumps the schema, restores it onto a stock
Postgres image with no vendor extensions, and boots the app against the
restored copy — reading back a sentinel row written before the dump, so
an empty restore fails the job instead of passing it. `CLAUDE.md` lists
"Postgres stays plain Postgres" as one of three decisions that cannot be
cheaply undone; this job is the only thing checking it. If it is deleted
or allowed to fail, that constraint stops existing.

## Repository conventions

- `CLAUDE.md` — standing rules, including three decisions that cannot be
  cheaply undone and a list of operational bans that each have a specific
  failure behind them. Read it before changing infrastructure.
- `.claude/rules/portable-core.md` — baseline working rules for any agent
  or contributor; written to travel between repos.
- `docs/ARCHITECTURE.md` — why this shape, what was rejected and on which
  single disqualifying fact, and **what is still unverified**.
- `docs/pre-build-research/` — findings gathered before the app existed,
  including several that contradict vendor documentation.

## Licensing

There is no LICENSE file, which means all rights are reserved. This
repository is public so the project can use the free tier that comes with
public repositories — branch rulesets, unlimited Actions minutes, code
scanning — not as an invitation to reuse the code.

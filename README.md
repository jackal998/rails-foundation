# rails-foundation

A Rails 8 foundation with the boring parts already decided: one always-on
container, Postgres, CI/CD, backups that have actually been restored.

**Status: deployed, on a free tier, with no users.** Rails 8.1 with the
built-in authentication generator, Solid Queue / Cache / Cable on
Postgres, a public landing page, and CI that runs tests, RuboCop,
Brakeman, bundler-audit, importmap audit, a secret scan, a dump/restore
portability check, and a build-and-boot of the production image.

Running since 2026-08-24 on Northflank's free tier in `us-central`
(Iowa), 0.2 shared vCPU and 512 MB, one managed Postgres addon serving
all four Rails database roles. Measured from Taiwan: 30 of 30 requests
returned 200, median 693 ms. There is no domain, no mail provider and no
off-machine backup yet — see the gaps listed further down before
treating any of this as production. `docs/ARCHITECTURE.md` has the
reasoning and the decisions that cannot be cheaply undone.

## Shape

| | |
|---|---|
| Framework | Rails 8.1, Postgres |
| Background jobs | Solid Queue, running **inside** the Puma process |
| Cache / cable | Solid Cache + Solid Cable, on the same Postgres |
| Redis | none — deliberately |
| Container | one, not three |
| CI | GitHub Actions on GitHub-hosted runners only |
| Backups | **intended:** encrypted `pg_dump` to object storage under an immutable retention lock, drilled on a schedule. **Today:** `bin/ops dump` writes a plaintext copy to one laptop, and `bin/ops restore-drill` rehearses restoring it. Everything after "one laptop" is unbuilt. |

No Redis and one container are the same decision: Solid Queue keeps the
queue in the database the app already has, and Rails 8's generated
`puma.rb` collapses web and worker into a single process behind one
environment variable. An idle Sidekiq worker issues roughly 10 million
Redis commands a month before running a single job — on per-command
pricing that is more than this entire stack costs.

All four job backends (Solid Queue, GoodJob, Sidekiq, delayed_job) are
Active Job adapters, so this is a cost decision, not a lock-in one. The
application code does not change. Moving to Sidekiq is still an
afternoon rather than a config line — a gem, a Redis to pay for and run,
a second process to deploy and supervise, and the Puma plugin removed —
but nothing written against Active Job has to be rewritten, which is the
part that would have been expensive. The reverse move is the same
afternoon. Hence starting here.

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
produces the production image, so local and production cannot drift onto
different base images or Ruby versions. CI could, until 2026-08-25: every
job ran on the runner with `ruby/setup-ruby` and nothing built the
Dockerfile at all, so this sentence was two thirds true and read as
three. The `production-image` job now builds and boots it. `docker build` with no
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

Beyond the usual test/lint/scan jobs, three jobs exist as enforcement
mechanisms rather than tests.

**`database-portability`** dumps the schema, restores it onto a stock
Postgres image with no vendor extensions, and boots the app against the
restored copy — reading back a sentinel row written before the dump, so
an empty restore fails the job instead of passing it. `CLAUDE.md` lists
"Postgres stays plain Postgres" as one of three decisions that cannot be
cheaply undone; this job is what checks it. If it is deleted or allowed
to fail, that constraint stops existing.

Its limit, stated because a half-checked constraint reads as a checked
one: **it covers the primary database only.** The three Solid schemas
are not dumped or restored here. What does exercise them is
`production-image` below, and `bin/ops dump` refuses any dump carrying an
extension a stock Postgres might lack — but neither is the same as
restoring them onto vanilla Postgres, and nothing yet does that.

**`production-image`** builds the Dockerfile and boots the resulting
image against one database serving all four Rails roles — the shape the
managed addon actually provides, and the shape that took production down
on 2026-08-24 with exit code 0. It requires the container to still be
running, unrestarted, and answering `/up` forty-five seconds later,
because the deployment that failed answered once and then died. It also
counts the Solid tables and the registered queue processes, since no
other job goes through `bin/docker-entrypoint`.

**`secret_scan`** runs gitleaks over every commit and then
`bin/check-personal-paths`, which covers home-directory paths gitleaks
structurally cannot see: its default ruleset allowlists Unix home paths
globally, so the rule in `.gitleaks.toml` never fires on them. Neither
check is absolute and the workflow says so where it defines them.

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

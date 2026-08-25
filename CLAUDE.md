# rails-foundation — Standing rules

Per-project rules for every session here. They supplement whatever
machine-level system the operator carries; if you carry none,
`.claude/rules/portable-core.md` is your baseline.

## What this repo is

A Rails 8 foundation: one always-on container (web + jobs in the same
Puma process), Postgres, CI/CD, backups with a rehearsed restore. It
exists to be built on and, if it grows, to be split out — so every
decision below is judged on whether it can be reversed.

It is a **public** repository. Public was chosen for the free tier that
comes with it (branch rulesets, unlimited Actions minutes, CodeQL,
secret scanning), **not** to open-source the work. There is no LICENSE
file, so all rights are reserved.

Architecture rationale, alternatives considered, and the facts that are
still unverified: `docs/ARCHITECTURE.md`.

## The three decisions that cannot be cheaply undone

Everything else in this stack is a weekend or less to change. These are
not. Do not undo them without an explicit decision from the owner, and
do not let a plausible-sounding refactor erode them.

1. **Authentication stays in our own `users` table.** Adopting a hosted
   auth provider (Clerk, Auth0, Supabase Auth) is a *rewrite* to leave:
   password hashes require a vendor support ticket and social-identity
   linkages do not migrate at all. When MFA or passkeys are needed,
   migrate to `rodauth-rails` — keep the bcrypt `password_digest` so
   hashes carry over.
2. **Postgres stays plain Postgres.** No RLS-as-authorization, no
   PostgREST, no vendor-specific realtime or data APIs. The CI job that
   restores a `pg_dump` onto a vanilla Postgres image and boots the app
   is what enforces this — if that job is ever deleted or skipped, the
   constraint is gone. **It covers the primary database only**, which is
   stated here rather than hidden because a half-checked constraint gets
   trusted like a checked one: the three Solid schemas are not restored
   onto vanilla Postgres by anything. `bin/ops dump` refuses a dump that
   carries any extension a stock Postgres might lack — added after the
   managed database's monitoring extensions turned up inside a real
   backup — and `production-image` boots the whole thing on one database,
   but neither closes that gap.
3. **Region is fixed. App and database never split across regions.**
   Region is chosen at provisioning and changing it means a full
   dump/restore with downtime.

## Operational bans

Each of these has a specific failure behind it. None is a style
preference.

- **Never attach a self-hosted runner to this repo.** It is public, so
  workflows from forked pull requests would execute on that host. This
  is the same blast-radius reasoning that ruled out self-hosting the app
  at home.
- **Never use `pull_request_target`.** It runs with write permissions
  and repository secrets against attacker-controlled code.
- **No load-bearing `schedule:` workflow in this repo.** GitHub
  automatically disables scheduled workflows in a public repository after
  60 days without repository activity, and a disabled workflow emits no
  failure signal. Anything whose absence must be noticed — the backup
  restore drill above all — lives elsewhere and alerts on NOT-RUN, not
  only on failure.
- **Never click "Upgrade to Pay As You Go"** on a cloud account whose
  free tier is currently the mechanical guarantee that the card cannot
  be charged.
- **`config/master.key` never leaves the machine it was generated on**
  except through the secret store. It is not in this repo and there is
  no situation in which committing it is correct.
- SHA-pin every third-party GitHub Action by full commit hash, never by
  tag.

## Public-repo hygiene

Assume every commit is permanent and mirrored within seconds; a
force-push does not un-publish anything.

- Before any push that adds files, verify the ignore rules by
  **behaviour, not by asking git about patterns**. Create the real files
  and check what git can actually see:

  When those files already exist on the machine, do not fabricate them at
  all — ask git what it sees of the real ones, which is the same evidence
  with none of the risk:

  ```sh
  git status --porcelain --ignored=matching -- \
    .env config/master.key config/credentials
  # '!!' = ignored, correct.  '??' = untracked AND visible = a leak.
  # Nothing listed = git cannot see the path at all, also correct.
  ```

  Only when a path is genuinely absent is the fabricate-and-check form
  needed:

  ```sh
  # The guard clause is not optional: every path below is a REAL file
  # this repo may hold, and the test overwrites then deletes it.
  for f in .env config/master.key config/credentials/production.key; do
    [ -e "$f" ] && { echo "REFUSING: $f exists — this test would destroy it"; exit 1; }
  done

  mkdir -p config/credentials
  for f in .env config/master.key config/credentials/production.key; do
    printf 'x\n' > "$f"
  done
  git status --porcelain    # none of the three may appear
  rm -f .env config/master.key config/credentials/production.key
  ```

  That guard was added on 2026-08-24, after the earlier unguarded version
  of this very snippet **overwrote and then deleted a working `.env`** —
  the Postgres password in it was unrecoverable and the database volume
  had to be rebuilt. A verification step is still a write: it is fully
  capable of destroying the thing it exists to protect, and the moment of
  least suspicion is when you are following your own instructions.

  Do **not** use `git check-ignore -v` as this test. It exits 0 whenever
  *any* pattern matches — including a negation such as `!.env.example` —
  so a file that is deliberately **not** ignored reports identically to
  one that is. Found when that check falsely failed on `.env.example`
  while writing this repo's first commit: a check that cannot
  distinguish its own two outcomes is not a check.
- The local gitleaks pre-commit hook is not optional here. GitHub's free
  secret scanning has no pattern for a Rails master key and custom
  patterns are a paid feature — this hook is the only real defence.
- No absolute home paths, no NAS/LAN/VPN hostnames or IPs, no password
  manager vault or item names, no `op://` references, no personal data.
  Use `<you>` / `<USER_HOME>`-style placeholders.

  Of that list, exactly two things are checked by a machine: absolute
  home paths, by `bin/check-personal-paths` in CI, and one national-ID
  shape, by `.gitleaks.toml`. Hostnames, vault names, `op://` references,
  names, email addresses and phone numbers are **not** detected by
  anything — they are a rule you follow, not a rule that catches you.

  The home-path check lives outside gitleaks because it has to:
  gitleaks' default ruleset allowlists Unix home paths globally and
  discards the finding after the rule matches, so the rule in
  `.gitleaks.toml` has never once fired on one. That was found on
  2026-08-25, having been believed enforced since the first commit.
- Rails encrypted credentials (`config/credentials.yml.enc`) **are** safe
  to commit. The key that decrypts them is not.

## Security gates — confirm in chat before acting, every time

These require the owner's explicit "yes" first, even mid-task, even in a
long autonomous run. Never self-approve. One outline plus one "yes"
covers only the actions named in that outline; a follow-up gated step
discovered mid-task needs its own.

- Installing any package, dependency, runtime, or CLI tool
- Cloning external repos or pulling external prompts/skills/scripts
- Writing files outside this working directory
- Shell commands that modify system state beyond read-only
- Pushing branches or opening PRs against a remote
- Changing repository visibility, or creating/deleting repos
- Merging or closing PRs and issues
- `git` commands that rewrite history or discard work
  (`reset --hard`, `rebase`, `commit --amend`, `checkout --`)
- Anything touching production data or a live database

For each, surface a one-paragraph summary **before** acting: what the
action is, where it comes from, its risk class (prompt injection /
supply chain / PII / irreversible / network / public-visibility), and
your verdict. When classification is ambiguous, treat it as gated.

## Verification

Every completion claim needs mechanical evidence produced by something
other than your own belief: pasted test output with its exit code, a
file read back and compared against intent, `git log -1` after a commit.
"Should work" is not evidence.

**A green suite is not delivery.** Before calling anything fixed,
exercise the real path — the actual page, the actual button, the actual
command. If it genuinely cannot be reached without the owner (a
credential, a device), say exactly that and name the step needed.

## Coding posture

- Rails conventions first. Reach for a gem only when the framework has
  no answer, and check its last release date before adopting it.
- Test what you add or change; trigger real failure modes with real
  inputs rather than monkeypatching something to raise. No coverage
  gates.
- Functions small, errors handled at boundaries, input validated at
  system edges, nothing swallowed silently.
- Conventional Commits: `type(scope): description`, imperative, ≤72
  chars, explaining **why**. Never commit directly to `main`.

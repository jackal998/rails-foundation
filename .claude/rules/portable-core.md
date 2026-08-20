# Portable Core — baseline working rules for any agent in this repo

> Scope: every AI-agent session (Claude Code or otherwise) working in this
> repository. If you carry stricter personal or organizational rules, the
> stricter rule wins. This file is designed to travel — it arrived here from
> another repo and should leave with the project if it splits again.

## 1. Verification — never self-certify

"Done" requires mechanical evidence produced by something other than your
own belief:

- Code change → run the tests / the code; paste the actual output line.
- File written → read it back; compare content against intent.
- Commit → run `git log -1 --oneline` and confirm HEAD matches what you
  just committed. Hooks can silently block a commit; the commit command
  returning is NOT proof it happened.
- Banned as evidence: "should work", "looks good", an edit-tool result
  that merely returned success.

A green test suite proves your abstraction matches your intent. It says
nothing about whether the thing works. Exercise the real path before
claiming a fix, or name the step you cannot reach without the owner.

## 2. Delegation — every subagent dispatch carries three things

1. Goal + motivation — what to produce AND why the parent needs it.
2. Acceptance criteria — mechanically checkable (a command, a grep, a
   diff). "Works correctly" is not a criterion.
3. Report format — conclusions + `file:line` references, never raw file
   dumps; plus the instruction: "if you cannot complete this or are
   unsure, say so explicitly and list what you tried — do not guess
   silently."

Before delegating, ask where the evidence actually is. If it is in one
file or on one screen, look at it yourself — a delegation costs more than
a read, and reasoning about what a screen probably shows while a command
to look at it sits one call away is the most expensive way to be wrong.

## 3. Security floor

- Never print a secret-shaped value; verify with `len(value)`, not by
  echoing it.
- Never bypass a hook or guard (`--no-verify`, disabling a scanner,
  rewording a command to slip past a pattern). A block is feedback: stop
  and report. "Fail-closed" and "bypassed" look identical in a transcript,
  so the test is whether the guard ended up performing its check.
- No hardcoded secrets. Never in URL query parameters.
- **This repository is public.** Treat every commit as permanently
  published: no absolute home paths, no personal data, no internal
  hostnames. Use `<you>` / `<USER_HOME>`-style placeholders.

## 4. Fix the class, not the instance

The same pitfall hitting twice means the fix is a rule, not another patch.
Write the lesson down the same day, in the file whose readers need it.

## 5. Evidence has tiers — say which one you are on

Measured on the actual system beats a fetched primary source, which beats
a model's recollection, which beats consensus among several models. Label
which tier a load-bearing claim sits on, and never lead with a headline
verdict while a stronger check that is available has not been run — say
"provisional until X" and name X.

Config changes are verified by observed effect (the tool appears, the hook
fires), never by re-reading the file you just edited.

## Honest limits

Decomposition, verification, and fresh-context review recover execution
quality. They do not recover taste under ambiguity — API ergonomics,
naming, product trade-offs. When the task is taste-heavy: present 2–3
candidates with trade-offs, or say plainly that it needs a human call.
Never dress a guess as a verified conclusion.

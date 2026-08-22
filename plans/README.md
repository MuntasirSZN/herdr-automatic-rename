# Implementation plans

Written by an advisor pass on 2026-08-22, against commit `8bb0db7`. Each plan is self-contained: read it fully before starting, honor its STOP conditions, and update your row here when done.

Three plans, from an audit that started with nine categories. The short list is the point. This codebase is well tested and well documented, so most of what an audit normally finds is not here.

## Execution order and status

| Plan | Title | Priority | Effort | Depends on | Status |
| ------ | ------- | ---------- | -------- | ------------ | -------- |
| 001 | Make the stale-lock steal atomic | P1 | S | none | DONE (grew past its scope: see below) |
| 002 | Recover from an unreadable state.json | P1 | S | none | DONE |
| 003 | Make the shell lint gate able to fail, and run it in CI | P2 | S plus an unbounded tail | none, but see below | DONE (39 findings, all deliberate: 22 cleared by `source=` directives, 17 suppressed with reasons) |

## Dependency notes

- 001 and 002 are independent. Either order works, and they touch different functions in `automatic-rename.sh`, so they can also run in parallel on separate branches.
- 003 ran last, as intended, so shellcheck saw the code 001 and 002 left behind. It flagged nothing in either change.
- 003 has no hard dependency, but do it last. If shellcheck flags a line inside the lock or the state store, fixing it in 001's or 002's diff is one edit instead of two, and those two plans forbid touching each other's code.

## What each plan fixes

001 closes a race that was reproduced, not inferred. Six contenders against one aged lock produced two simultaneous lock holders in 2 of 10 trials, because the steal is three filesystem calls rather than one. Two passes running at once can overwrite each other's ownership records in `state.json`, and a tab whose record is lost opts itself out of automatic naming for good.

002 fixes a single point of failure with no recovery path. A `state.json` that jq cannot parse makes every write fail forever, so tab naming dies for the whole session, silently, and `reset` cannot bring it back either. Reproduced end to end: with a truncated state file, changing a pane's foreground program produced no rename at all, and `reset` renamed the tab once but recorded nothing and reported `Nothing to reset`.

003 is tooling, not a bug. `make lint` cannot fail: its `&&` / `||` recipe reports a real shellcheck failure as `shellcheck not installed; skipping` and exits 0, and `lint-md` has the same shape. CI never runs shellcheck at all, and its `bash -n` loop skips `icons.sh`. So the gate this project already decided it wanted has never been able to say no. Nobody has run shellcheck here yet, so the size of what it finds is unknown, which is why the plan carries a hard cap and a STOP.

## What review changed after the plans landed

Three review passes reshaped plan 001's fix well past what the plan scoped, and the plan is the honest record of how much it underestimated the problem. The single `mv` it specified closed only the narrowest of three windows. Reviewers found that a contender whose age check predated the winner's `mkdir` could move a live lock away, that handing such a lock back with `mv` nests it inside whatever now holds the name and leaves something `rmdir` can never release, and that the lock path standing empty during the decision is itself winnable by a third contender. A stress test settled the design: 6 contenders, 200 trials, 23 two-holder outcomes before the second age read. After it, two harnesses disagree, and the disagreement is the honest answer: one measured zero in 350 trials, another roughly one burst in a hundred. Rare and real, not gone. It settled an argument the other way too. A fifth guard, the fast path refusing a name while a steal was in flight, turned out to be dead code (`mv` does not touch the moved directory's mtime, so "moved recently" was unanswerable), and rebuilt to actually work it changed nothing measurable and cost availability. It was removed rather than kept.

Two review findings were rejected with reasons, both stated in `docs/ARCHITECTURE.md`: healing a corrupt state file does not re-adopt an already-named tab (scenario 42 pins that on an ordinary event), and a steal whose victim exits mid-handoff leaves a lock that ages out rather than one held forever.

## Findings considered and rejected

- **Per-tab state reads are two jq forks instead of one** (`automatic-rename.sh:386-387`). Withdrawn after measurement. A patched build that read both fields in one jq was *slower* (513 ms per pass against 231 ms), and the original 611 ms figure came from a cold cache. A steady pass over 20 tabs is about 230 ms, backgrounded and coalesced. No defect.
- **Test coverage.** Not a finding. Roughly 200 assertions across seven files, including a full-reconcile integration suite driven against a fake herdr that records every rename. The pure naming rules, the prefix helpers, the state machine, the shell hooks, and the workspace sidebar ordering all have direct tests.
- **Documentation drift.** None found. `config.example.sh` documents every knob the code reads, and `docs/ARCHITECTURE.md` matches the implementation on every point checked.
- **Security.** No findings. Sourcing the user's own `config.sh` and feeding their own `SUBSTITUTE_SETS` to `sed` are the design, not a vulnerability. Every herdr-supplied value reaches the shell through the one `clean` jq definition and is quoted at every use. No secrets in the repo.
- **Dependencies.** Nothing to bump. Runtime dependencies are `jq` and the herdr CLI, and the one pinned dev tool (`markdownlint-cli2@0.23.2`) is current enough.
- **Missing `local` for `lpane` and `dirty`** (`automatic-rename.sh:717`). Cosmetic. `ar_reconcile_tabs` runs once per pass and the names collide with nothing.
- **A pass that outlives the 30-second steal window** could still put two reconciles in flight even after 001. Not worth doing now: a 20-tab pass measured about 230 ms, so the margin is two orders of magnitude, and a lock heartbeat brings its own failure modes. Revisit only if someone reports a slow pass.

## Direction, not planned

Three options a maintainer might want, recorded so they are not re-derived. None has a plan.

- **Name a shell tab after its directory.** `HIDE_SHELL` exists because `zsh` says nothing, and the pane's `foreground_cwd` is already lifted for the title refusal, so this costs no new herdr call. `naming.sh`'s header calls dir-based naming out of scope today, and it is tmux-window-name's headline feature.
- **A `status` action.** The opt-out state machine is invisible, so a user asking why a tab stopped renaming has nothing to look at. `ar_notify` and the `reset` arms already compute the answer.
- **An agent-roster drift check.** CHANGELOG 0.7.1 records `maki` going two herdr releases with a `?` icon because herdr added an agent kind and the two program lists did not follow. The icon test now reads its roster from `NAME_ONLY_PROGRAMS`, which closes half of it. The open half is noticing when herdr itself adds a kind.

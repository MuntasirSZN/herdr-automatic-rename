# Plan 001: Make the stale-lock steal atomic so two passes can never hold the lock at once

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving on. If anything in "STOP conditions" happens, stop and report. Do not improvise. When done, update this plan's status row in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 8bb0db7..HEAD -- automatic-rename.sh tests/`
> If `automatic-rename.sh` changed since this plan was written, compare the "Current state" excerpt against the live code first; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `8bb0db7`, 2026-08-22

## Why this matters

`ar_lock` steals a lock older than 30 seconds in three filesystem steps (`rm` the owner file, `rmdir` the lock, `mkdir` it again). Two contenders that find the same stale lock can both come out believing they hold it: the second one's `rm -f .../owner` empties the directory the first just created, its `rmdir` then succeeds against that fresh lock, and its `mkdir` grants a second, parallel claim. Reproduced here: six contenders against one aged lock produced two simultaneous holders in 2 of 10 trials.

Two concurrent passes are worse than wasted work. Every pass reads `state.json`, computes, and writes it back whole (`ar_state_set`, `automatic-rename.sh:315-331`), so one pass can overwrite the other's ownership record. A tab whose record is lost reads, on the next pass, as a tab renamed by hand: `ar_name_eligible` opts it out permanently, recoverable only through `reset`. That is the failure the lock exists to prevent, and `docs/ARCHITECTURE.md` names it as the plugin's one promise.

The same race leaks locks. The two failed owner-file writes seen in the reproduction (`Invalid argument`, `No such file or directory`) leave a lock directory with no `owner` inside it. `ar_unlock` only removes a lock whose owner token is its own, so such a lock is never released and blocks every event for a further 30 seconds.

## Current state

- `automatic-rename.sh` is the whole engine. The lock is at lines 270-301, under the banner `cross-invocation lock (mkdir is atomic; 30s steal window)`.
- `tests/test_state.sh` sources the engine with `XDG_STATE_HOME` pointed at a throwaway dir. That is the structural pattern for the new test file.
- `tests/run.sh` runs every `tests/test_*.sh` by glob, so a new file needs no registration.

The code to change, verbatim from `automatic-rename.sh:277-301`:

```bash
AR_LOCK_TOKEN="$$-${RANDOM:-0}-$(date +%s 2>/dev/null || echo 0)"
ar_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '%s' "$AR_LOCK_TOKEN" > "$LOCK_DIR/owner" 2>/dev/null
    return 0
  fi
  local now mt age
  now=$(date +%s 2>/dev/null || echo 0)
  mt=$(stat -c %Y "$LOCK_DIR" 2>/dev/null || stat -f %m "$LOCK_DIR" 2>/dev/null || echo "$now")
  age=$(( now - mt ))
  if [ "$age" -gt 30 ]; then
    rm -f "$LOCK_DIR/owner" 2>/dev/null
    rmdir "$LOCK_DIR" 2>/dev/null
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      printf '%s' "$AR_LOCK_TOKEN" > "$LOCK_DIR/owner" 2>/dev/null
      return 0
    fi
  fi
  return 1
}
ar_unlock() {
  [ "$(cat "$LOCK_DIR/owner" 2>/dev/null)" = "$AR_LOCK_TOKEN" ] || return 0
  rm -f "$LOCK_DIR/owner" 2>/dev/null
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
```

Repo conventions to match (see `CONTRIBUTING.md`): bash 3.2, no runtime dependency beyond `jq` and the herdr CLI (`mv`, `mkdir`, `rmdir`, `rm`, `stat` are already used here), the `ar_` function prefix, comments that name the failure mode a line prevents, `--` instead of em dashes, and no hard-wrapped markdown.

## Commands you will need

| Purpose | Command | Expected on success |
| --- | --- | --- |
| Syntax check | `/bin/bash -n automatic-rename.sh` | exit 0, no output |
| Full test suite | `./tests/run.sh` | `# ALL TESTS PASSED`, exit 0 |
| One test file | `./tests/run.sh lock` | that file's TAP output, `0 failed` |
| Markdown lint | `make lint-md` | exit 0 |

## Scope

**In scope** (the only files you may modify):

- `automatic-rename.sh`, `ar_lock` only.
- `tests/test_lock.sh` (create).
- `docs/ARCHITECTURE.md`, the `## Locking` section only, one sentence, in step 4.

**Out of scope** (do NOT touch, even though they look related):

- `ar_unlock`. Its owner-token check is already correct and is what keeps the fix safe. Changing it breaks the release-recheck-reacquire loop in `ar_run`.
- `ar_run` and its coalescing loop. The rerun-flag protocol is not part of this fix.
- The 30-second steal window. Do not tune it. A different number does not fix a non-atomic steal.
- `ar_state_set` and the opt-out state machine. Plan 002 covers state-file robustness; leave it alone so the two changes stay reviewable apart.

## Git workflow

- Branch: `advisor/001-atomic-lock-steal`
- Conventional Commits, subject 50 characters or fewer, lowercase. Real examples from `git log`: `fix(naming): strip an agent's brand off its title`, `ci: fail a hard-wrapped markdown line`. Use `fix(lock): make the stale-lock steal atomic`.
- Do NOT push and do NOT open a pull request unless the operator asks.

## Steps

### Step 1: Replace the three-step steal with one atomic rename

In `ar_lock`, replace the `rm -f` plus `rmdir` pair inside the `if [ "$age" -gt 30 ]` branch with a single `mv` of the stale lock directory aside. `mv` of a directory onto a name that does not exist is one `rename(2)`, so exactly one contender can succeed: after it, the source path is gone and every other contender's `mv` fails with `ENOENT`. Only the winner may go on to `mkdir` a fresh lock.

The target shape:

```bash
  if [ "$age" -gt 30 ]; then
    # Claim the right to steal in ONE step. The old sequence was rm + rmdir +
    # mkdir, and a second contender's rm emptied the lock the FIRST one had just
    # created: its rmdir then took that fresh lock away and its mkdir handed it a
    # parallel claim, so two passes ran at once and their whole-file state writes
    # clobbered each other -- which reads, one pass later, as a tab renamed by
    # hand, and opts it out of naming for good. `mv` onto a name that does not
    # exist is a single rename(2), so exactly one contender wins it and the losers
    # find no source to move.
    local stale="$LOCK_DIR.stale.$AR_LOCK_TOKEN"
    mv "$LOCK_DIR" "$stale" 2>/dev/null || return 1
    [ -n "$stale" ] && rm -rf -- "$stale" 2>/dev/null
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      printf '%s' "$AR_LOCK_TOKEN" > "$LOCK_DIR/owner" 2>/dev/null
      return 0
    fi
  fi
```

Declaring `stale` on the existing `local now mt age` line instead is fine; it must be `local` either way.

Three details that are easy to get wrong:

1. The destination name must be unique per process. `$AR_LOCK_TOKEN` is `pid-RANDOM-epoch`, used here rather than `$$` alone because a recycled pid must not collide with residue from an earlier crashed run. Do not simplify it.
2. The `mv` failure must `return 1`, not fall through. A contender that lost the steal has no lock and must report that.
3. The cleanup is `rm -rf` on a directory that may still hold the old `owner` file, guarded on `$stale` being non-empty. Keep the `--` so a path beginning with a dash is not read as an option.

**Verify**: `/bin/bash -n automatic-rename.sh` -> exit 0, no output.

**Verify**: `./tests/run.sh` -> `# ALL TESTS PASSED`. Scenario 37 in `tests/test_reconcile.sh` exercises a *held* (fresh) lock and must still pass unchanged: a fresh lock is younger than the steal window, so `ar_lock` refuses it without reaching this branch.

### Step 2: Add the exclusivity regression test

Create `tests/test_lock.sh`, modeled on `tests/test_state.sh` (source the engine with `XDG_STATE_HOME` pointed at a `mktemp -d` sandbox so `LOCK_DIR` resolves there, use `check` and `check_rc` from `tests/lib.sh`, end with `t_summary`). Three cases:

1. **A fresh lock is not stealable.** `mkdir "$LOCK_DIR"`, then `ar_lock` -> rc 1.
2. **A stale lock is stolen cleanly, by one caller.** `mkdir "$LOCK_DIR"`, write a foreign token into `$LOCK_DIR/owner`, age it with `touch -t 202001010000 "$LOCK_DIR"`, then `ar_lock` -> rc 0, `cat "$LOCK_DIR/owner"` equals `$AR_LOCK_TOKEN`, and no `"$LOCK_DIR".stale.*` residue is left.
3. **Concurrent contenders against one stale lock produce exactly one winner.** This is the regression that fails on the current code.

For case 3, each contender needs its own `AR_LOCK_TOKEN`, so its own shell. Write a small helper script into the sandbox that sources the engine and appends a line to a shared file when `ar_lock` returns 0, then launch six with `&` and `wait`. Repeat for 20 trials, re-creating and re-ageing the stale lock each time, and `check` that the count of trials with more than one winner is `0`.

Note in a comment at the top of case 3 that its failure mode is a false PASS, never a false failure: exclusivity after the fix is guaranteed by `rename(2)`, so the assertion cannot flake, but a run that never interleaves would pass on broken code too. 20 trials times 6 contenders failed the pre-fix code reliably on a fast machine; keep both numbers.

**Verify**: `./tests/run.sh lock` -> the new file's TAP output, `0 failed`.

**Verify** the test catches the bug, by temporarily restoring the old steal sequence:

```sh
cp automatic-rename.sh /tmp/ar-fixed.sh
# hand-edit automatic-rename.sh back to the rm -f + rmdir + mkdir form from
# "Current state" above, then:
./tests/run.sh lock          # expect: NOT ok on the exclusivity case
cp /tmp/ar-fixed.sh automatic-rename.sh
./tests/run.sh lock          # expect: 0 failed
```

If the pre-fix run passes, the test is not reproducing the race: raise the trial count, and if it still passes, STOP and report rather than shipping a test that proves nothing.

### Step 3: Confirm the whole suite on stock bash 3.2

`tests/run.sh` invokes `bash`, which on macOS may be a newer Homebrew bash. The engine targets `/bin/bash` 3.2 and CI checks that path on macOS runners.

**Verify**: `/bin/bash ./tests/run.sh` -> `# ALL TESTS PASSED`. If `/bin/bash --version` reports 3.2 and a *new* failure appears that `bash ./tests/run.sh` does not, the cause is a bash-4 construct you introduced, most likely in the new test file. Fix it there.

### Step 4: Record the change in the architecture doc

`docs/ARCHITECTURE.md` has a `## Locking` section whose first sentence reads: `A `mkdir` lock (atomic, ownership-token stamped, 30-second steal window) plus a rerun flag coalesces a burst of events into one worker.`

Add one sentence to that paragraph: the steal itself is a single `mv` of the stale directory aside, so only one contender can win it, and the three-step steal it replaced could hand two passes the lock at once. One sentence, the doc's existing voice, one line (no hard wrapping), `--` instead of an em dash.

Do not add a CHANGELOG entry unless the operator asks; the repo writes those at release time and this plan does not know the next version number.

**Verify**: `make lint-md` -> exit 0.

## Test plan

- New file `tests/test_lock.sh` with the three cases in step 2. It is the first direct test of `ar_lock`; today the lock is covered only indirectly, by scenario 37 of `tests/test_reconcile.sh` (a held lock makes an action report the wait) and scenario 38 (the rerun flag).
- Structural pattern to follow: `tests/test_state.sh`.
- Do not modify `tests/test_reconcile.sh`. Its scenario 37 is the existing coverage for the non-steal path and must keep passing untouched, which is the evidence this change did not alter refusal behavior.
- Verification: `./tests/run.sh` -> `# ALL TESTS PASSED`, with the new file's cases in the count.

## Done criteria

All must hold:

- [ ] `/bin/bash -n automatic-rename.sh` exits 0
- [ ] `./tests/run.sh` exits 0 and prints `# ALL TESTS PASSED`
- [ ] `/bin/bash ./tests/run.sh` exits 0 and prints `# ALL TESTS PASSED`
- [ ] `tests/test_lock.sh` exists and its exclusivity case fails against the pre-fix `ar_lock` (demonstrated in step 2)
- [ ] `grep -n 'rmdir "$LOCK_DIR"' automatic-rename.sh` returns exactly one line, inside `ar_unlock`
- [ ] `make lint-md` exits 0
- [ ] `git status --porcelain` lists only `automatic-rename.sh`, `tests/test_lock.sh`, `docs/ARCHITECTURE.md`, and `plans/README.md`
- [ ] `plans/README.md` status row for 001 updated

## STOP conditions

Stop and report back, do not improvise, if:

- The `ar_lock` body in the live file does not match the "Current state" excerpt.
- The pre-fix check in step 2 passes, meaning your new test does not reproduce the race even at a raised trial count.
- Any existing test in `tests/test_reconcile.sh` fails after your change. That means the fix altered refusal behavior, which it must not.
- `mv` of the lock directory behaves unexpectedly on your platform (for example the destination already exists as a directory and the move nests instead of renaming). Report what you saw rather than working around it.
- You conclude the fix needs a change in `ar_unlock`, `ar_run`, or the state store. Those are out of scope by design.

## Maintenance notes

- The invariant to protect in review: **the steal must stay one filesystem operation.** Any future edit that splits it back into check-then-act reintroduces this bug. The `mv` line is the whole fix.
- `ar_unlock`'s owner-token check is what makes a lost steal harmless: a contender that lost never wrote its token, so it can never remove the winner's lock. Keep those two properties together in any rework.
- A single pass that runs longer than the 30-second window is still stealable while it works, which would again put two passes in flight. Deliberately not addressed: a full reconcile measured about 0.23 seconds over 20 tabs, and a heartbeat refreshing the lock's mtime is a larger change with its own failure modes. Revisit if a report of a slow pass arrives.
- Deferred: the leaked-lock case where a lock directory exists with no `owner` file inside it. The atomic steal removes the way this plugin creates one, so the remaining sources are external (a crash between `mkdir` and the `printf`). It self-heals after 30 seconds through the steal path.

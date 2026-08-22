# Plan 002: Recover from a state.json that jq cannot read, instead of losing tab naming for good

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving on. If anything in "STOP conditions" happens, stop and report. Do not improvise. When done, update this plan's status row in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 8bb0db7..HEAD -- automatic-rename.sh tests/`
> If `automatic-rename.sh` changed since this plan was written, compare the "Current state" excerpts against the live code first; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none (independent of plan 001; either order works)
- **Category**: bug
- **Planned at**: commit `8bb0db7`, 2026-08-22

## Why this matters

Every write to the state store starts by parsing the file already there. `ar_state_set` reads it with `cat`, pipes it into `jq`, and returns 1 when `jq` cannot parse it; `ar_state_del` and `ar_state_prune` read the file directly and bail the same way. So a `state.json` that does not parse makes every write fail forever, and nothing ever replaces it.

Reproduced end to end against the mock herdr, with a truncated `state.json` and a tab labeled `nvim`:

- `ar_state_get` returns empty for every field, so `ar_name_eligible` treats the tab as first-seen. Its label is not a placeholder, so the tab is opted out. Correct given the evidence, but the opt-out cannot be *recorded*, because recording it is a write.
- The tab is never renamed again. Changing the pane's foreground program from `nvim` to `lazygit` produced no rename at all.
- `reset` does not recover it. It issues the rename (`tab rename w1:t1 lazygit`) but `ar_state_claim` cannot write, so ownership is never recorded, the action reports `Nothing to reset / No tab to re-adopt`, and the next event goes back to renaming nothing.

So the state file is a single point of failure with no self-heal and no message. Automatic naming is dead for the whole session, and the only fix is a user deleting a file nothing tells them about. The fix is small, because the correct behavior on an unreadable file is already known: it is the same as on a missing one, which the code handles fine.

The trigger is rare, which is why this is a small plan rather than an urgent one. Writes are atomic (temp file plus `mv`), so the plugin does not produce a torn file itself. What remains is external: a filesystem or power event, a hand edit, a file written by some future incompatible schema, or a partially written file restored from a backup.

## Current state

- `automatic-rename.sh` is the engine. The state store is lines 302-353, under the banner `naming state (atomic temp+mv; jq keyed by tab_id; only NAME_TABS uses it)`. `STATE_FILE` is line 65, `$STATE_DIR/state.json`.
- `tests/test_state.sh` holds unit tests for the store and the opt-out state machine. New unit cases go there.
- `tests/test_reconcile.sh` holds integration scenarios driving the real engine against `tests/mocks/herdr`. The new scenario goes after the last existing one.

The three functions to change, verbatim from `automatic-rename.sh:315-353`:

```bash
ar_state_set() { # <tab_id> <auto-name> <enabled true|false>
  local base tmp
  base='{}'
  [ -f "$STATE_FILE" ] && base=$(cat "$STATE_FILE" 2>/dev/null)
  [ -n "$base" ] || base='{}'
  # A write that did not land reports it. Ownership IS this file, so swallowing a
  # full disk or an unwritable state directory told the reset action a tab was
  # re-adopted while the next pass, finding no entry, opted it straight back out.
  tmp=$(mktemp "$STATE_DIR/.state.XXXXXX") || return 1
  if printf '%s' "$base" | jq --arg t "$1" --arg a "$2" --argjson e "$3" \
       '.[$t] = {auto: $a, enabled: $e}' > "$tmp" 2>/dev/null; then
    mv "$tmp" "$STATE_FILE" || return 1
  else
    rm -f "$tmp"
    return 1
  fi
}
ar_state_del() { # <tab_id>
  [ -f "$STATE_FILE" ] || return 0
  local tmp
  tmp=$(mktemp "$STATE_DIR/.state.XXXXXX") || return 0
  if jq --arg t "$1" 'del(.[$t])' "$STATE_FILE" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$STATE_FILE"
  else
    rm -f "$tmp"
  fi
}
ar_state_prune() { # <keep tab_ids...> - drop entries for tabs that no longer exist
  [ -f "$STATE_FILE" ] || return 0
  local keep tmp
  keep=$(printf '%s\n' "$@" | jq -R . | jq -s .) || return 0
  tmp=$(mktemp "$STATE_DIR/.state.XXXXXX") || return 0
  if jq --argjson keep "$keep" \
       'with_entries(select(.key as $k | $keep | index($k)))' "$STATE_FILE" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$STATE_FILE"
  else
    rm -f "$tmp"
  fi
}
```

And the reader, already correct and not to change (`automatic-rename.sh:306-313`):

```bash
ar_state_get() { # <tab_id> <field>
  [ -f "$STATE_FILE" ] || return 0
  jq -r --arg t "$1" --arg f "$2" '.[$t][$f] as $v | if $v == null then empty else $v end' \
    "$STATE_FILE" 2>/dev/null
}
```

Empty on an unreadable file is the right answer: empty means "nothing known about this tab", which is what an unreadable file honestly conveys. Leave it exactly as it is.

Repo conventions to match (see `CONTRIBUTING.md`): bash 3.2, no runtime dependency beyond `jq` and the herdr CLI, the `ar_` function prefix, comments that name the failure mode a line prevents (the existing comment inside `ar_state_set` is the model), `--` instead of em dashes, and no hard-wrapped markdown.

## Commands you will need

| Purpose | Command | Expected on success |
| --- | --- | --- |
| Syntax check | `/bin/bash -n automatic-rename.sh` | exit 0, no output |
| Full test suite | `./tests/run.sh` | `# ALL TESTS PASSED`, exit 0 |
| State tests only | `./tests/run.sh state` | TAP output, `0 failed` |
| Reconcile tests only | `./tests/run.sh reconcile` | TAP output, `0 failed` |
| Markdown lint | `make lint-md` | exit 0 |

## Scope

**In scope** (the only files you may modify):

- `automatic-rename.sh`, one new helper plus the three call sites in `ar_state_set`, `ar_state_del`, `ar_state_prune`.
- `tests/test_state.sh`, new unit cases appended before the final `rm -rf "$SB"` / `t_summary` lines.
- `tests/test_reconcile.sh`, one new scenario appended after the last existing one.
- `docs/ARCHITECTURE.md`, one sentence, in step 4.

**Out of scope** (do NOT touch, even though they look related):

- `ar_state_get`. Its empty-on-unreadable behavior is correct, and the `//`-versus-`if` comment above it explains a separate bug that must stay fixed.
- `ar_name_eligible` and the opt-out state machine. The point of this fix is that the state machine's logic is already right; it was starved of a working writer. Changing its rules here would mix two changes in one diff and put the plugin's central promise at risk.
- `ar_state_claim`. Its failure propagation (`return 1` when the write fails) is what this fix makes reachable again, so it needs no edit.
- The `mktemp` plus `mv` write pattern. It is why the plugin does not create torn files.
- Any user-facing warning, notification, or log line about a bad state file. Tempting, but `ar_notify` is only wired into the two actions, and a notification on every event during a broken pass would be worse than the silence. Noted in maintenance.

## Git workflow

- Branch: `advisor/002-state-file-self-heal`
- Conventional Commits, subject 50 characters or fewer, lowercase. Real examples from `git log`: `fix(naming): strip an agent's brand off its title`, `ci: fail a hard-wrapped markdown line`. Use `fix(state): heal a state file jq cannot read`.
- Do NOT push and do NOT open a pull request unless the operator asks.

## Steps

### Step 1: Add `ar_state_read`

Add one helper directly above `ar_state_get`, in the same banner section. It returns the state object as a JSON string, and returns `{}` both when the file is missing and when it does not parse:

```bash
# ar_state_read -> the state object as JSON, or "{}" when the file is missing OR
# unreadable. The two are the same answer: nothing is known about any tab. They
# used to differ, and that is the bug -- every writer below starts from this file,
# so one jq could not parse froze the store forever. The tab whose ownership went
# with it reads as hand-renamed on the next pass, opts out, and the reset action
# cannot bring it back either, since re-adopting it is another write. Naming was
# dead for the session with nothing said and no way back but deleting the file.
ar_state_read() {
  local base=""
  [ -f "$STATE_FILE" ] && base=$(cat "$STATE_FILE" 2>/dev/null)
  if [ -n "$base" ] && printf '%s' "$base" | jq -e 'type == "object"' >/dev/null 2>&1; then
    printf '%s' "$base"
  else
    printf '{}'
  fi
}
```

The check is `type == "object"`, not bare `jq -e .`, on purpose: a valid JSON array or the literal `null` parses fine but is not a state store, and `.[$t] = {...}` against it would either fail or produce nonsense. Keep the stricter test.

**Verify**: `/bin/bash -n automatic-rename.sh` -> exit 0.

### Step 2: Route all three writers through it

In `ar_state_set`, delete the three lines that build `base` (`base='{}'`, the `[ -f ... ] && base=$(cat ...)`, and the `[ -n "$base" ] || base='{}'`) and replace them with `base=$(ar_state_read)`. Keep everything else byte for byte, including the `mktemp` guard, the `mv` and its `|| return 1`, and the `rm -f "$tmp"; return 1` else-branch.

In `ar_state_del` and `ar_state_prune`, both of which pass `"$STATE_FILE"` to `jq` as a file argument, pipe the helper's output in instead. For each: drop the leading `[ -f "$STATE_FILE" ] || return 0` guard (the helper covers a missing file, and pruning a missing file into `{}` is harmless), and change the `jq` invocation to read stdin:

```bash
  if printf '%s' "$(ar_state_read)" | jq --arg t "$1" 'del(.[$t])' > "$tmp" 2>/dev/null; then
```

```bash
  if printf '%s' "$(ar_state_read)" | jq --argjson keep "$keep" \
       'with_entries(select(.key as $k | $keep | index($k)))' > "$tmp" 2>/dev/null; then
```

Leave the rest of both functions alone, `return 0` conventions included: `ar_state_del` and `ar_state_prune` deliberately do not report failure, unlike `ar_state_set`, because no caller acts on it.

Note the cost in a short comment on the helper. Each write now forks one extra `jq` to validate. Writes are the rare path, because `ar_state_claim` skips the write entirely when state already says what the pass computed, which is the steady state for every named tab on every event. `ar_state_prune` runs once per pass. So this is a fork or two per pass, not per tab.

**Verify**: `/bin/bash -n automatic-rename.sh` -> exit 0.

**Verify**: `./tests/run.sh` -> `# ALL TESTS PASSED`. Every existing state test must pass untouched; they are the evidence the healthy path is unchanged.

### Step 3: Add the tests

**Unit cases**, appended to `tests/test_state.sh` before its closing `rm -rf "$SB"` and `t_summary`. That file already ends with a block that `chmod 555`s the state dir, so put these *before* that block or restore permissions first. Read the tail of the file and place them where the state dir is writable.

1. `ar_state_read` on a missing file returns `{}`. (`rm -f "$STATE_FILE"` first.)
2. `ar_state_read` on a truncated file returns `{}`. Write `{"t1": {"auto": "nvim", "enab` into `$STATE_FILE` with `printf`.
3. `ar_state_read` on a valid object returns it unchanged, so healthy state is never discarded. Set an entry with `ar_state_set`, then check `ar_state_read | jq -r '.t1.auto'` is `nvim`.
4. `ar_state_read` on a valid JSON array returns `{}` (the `type == "object"` guard).
5. **The regression**: with a truncated `$STATE_FILE`, `ar_state_set t1 nvim true` returns rc 0 and `ar_state_get t1 auto` reads back `nvim`. This case fails on the current code.
6. `ar_state_prune` against a truncated file leaves a file that parses: run it, then `jq -e 'type == "object"' "$STATE_FILE"` succeeds.

Use `check` and `check_rc` from `tests/lib.sh`, matching the naming style already in the file (short lowercase descriptions, for example `a truncated state file heals on write`).

**Integration scenario**, appended to `tests/test_reconcile.sh` after its final scenario. Follow the shape of every scenario there: a banner comment explaining what it pins and why, `setup`, exported toggles, `fixture` heredocs, `run_event`, `check_contains` / `check_absent` against `$(log)`, then `teardown`. Number it one past the last.

What it must pin, which is the field failure reproduced above:

- Fixtures: one workspace, one tab labeled `nvim` with `pane_count` 1 and focused, one pane, and a `procinfo` fixture whose foreground process is `lazygit`. Set `NAME_TABS=1 AUTO_INDEX=0`.
- Before the event, write a truncated `state.json` into `$XDG_STATE_HOME/herdr-automatic-rename/` with `printf '{"w1:t1": {"auto": "nvim", "enab'`, mirroring how scenario 38 seeds `$STATE` directly.
- Run the `reset` action with `HERDR_TAB_ID=w1:t1`, the user's recovery path.
- Assert: the rename was issued (`check_contains ... "tab rename w1:t1 lazygit"`), the state file now parses and records the tab (`check "..." "lazygit true" "$(jq -r '."w1:t1" | "\(.auto) \(.enabled)"' "$STATE")"`), and a following plain event renames on a program change rather than doing nothing. For that last one, rewrite `procinfo_p1.json` to a different program, clear the log with `: >"$HERDR_MOCK_LOG"`, run `run_event tab.focused`, and `check_contains` the new rename.

The third assertion is the important one. The first two can pass while naming is still dead one event later, which is precisely what the current code does.

**Verify**: `./tests/run.sh state` -> `0 failed`.

**Verify**: `./tests/run.sh reconcile` -> `0 failed`.

**Verify** the tests catch the bug, by reverting the engine only:

```sh
cp automatic-rename.sh /tmp/ar-fixed.sh
git stash push -- automatic-rename.sh    # tests stay, engine goes back to HEAD
./tests/run.sh state reconcile 2>/dev/null || true
./tests/run.sh state       # expect: NOT ok on the truncated-file write case
./tests/run.sh reconcile   # expect: NOT ok on the new scenario
git stash pop
./tests/run.sh             # expect: # ALL TESTS PASSED
```

If either pre-fix run passes, the test is not reproducing the failure. STOP and report rather than shipping it.

### Step 4: Record the change in the architecture doc

`docs/ARCHITECTURE.md`, in `## Why config and state sit at fixed paths`, ends with two paragraphs about the state file and the recorded base. Add one sentence there: a state file that does not parse is read as an empty one rather than freezing every write, because a store no writer can start from used to end tab naming for the session with no way back. One sentence, one line, no hard wrapping, `--` not an em dash.

Do not add a CHANGELOG entry unless the operator asks.

**Verify**: `make lint-md` -> exit 0.

## Test plan

- New unit cases in `tests/test_state.sh`: the six in step 3, following that file's existing `check` / `check_rc` style.
- New integration scenario in `tests/test_reconcile.sh`: the truncated-state recovery, following scenario 38 (which already seeds `$STATE` by hand) and scenario 36 (which asserts what a failed re-adoption reports).
- The existing state and reconcile tests are the regression net for the healthy path. Do not edit any of them; if one needs changing to pass, that is a STOP condition, because it means behavior on a good file moved.
- Verification: `./tests/run.sh` -> `# ALL TESTS PASSED`, and the pre-fix demonstration in step 3 shows the new cases failing without the engine change.

## Done criteria

All must hold:

- [ ] `/bin/bash -n automatic-rename.sh` exits 0
- [ ] `./tests/run.sh` exits 0 and prints `# ALL TESTS PASSED`
- [ ] `/bin/bash ./tests/run.sh` exits 0 and prints `# ALL TESTS PASSED`
- [ ] `grep -n 'ar_state_read' automatic-rename.sh` shows the definition plus exactly three call sites
- [ ] `grep -nF '[ -f "$STATE_FILE" ]' automatic-rename.sh` returns exactly two lines, one in `ar_state_read` (which needs it to avoid `cat` on a missing file) and one in `ar_state_get`
- [ ] The pre-fix demonstration in step 3 showed both new test groups failing against HEAD's engine
- [ ] `make lint-md` exits 0
- [ ] `git status --porcelain` lists only `automatic-rename.sh`, `tests/test_state.sh`, `tests/test_reconcile.sh`, `docs/ARCHITECTURE.md`, and `plans/README.md`
- [ ] `plans/README.md` status row for 002 updated

## STOP conditions

Stop and report back, do not improvise, if:

- Any of the four functions in "Current state" does not match the excerpt in the live file.
- An existing test in `tests/test_state.sh` or `tests/test_reconcile.sh` fails after your change, or needs editing to pass.
- Either pre-fix demonstration in step 3 passes, meaning your tests do not reproduce the failure.
- You need to change `ar_name_eligible`, `ar_state_claim`, or `ar_state_get` to make the integration scenario pass. That would mean the diagnosis in "Why this matters" is wrong, which is worth reporting rather than working around.
- You conclude the fix should warn the user about a bad state file. Deliberately out of scope; report the idea instead of building it.

## Maintenance notes

- The rule to protect in review: **exactly one place decides what an unusable state file means, and it says `{}`.** A future writer added to this section must go through `ar_state_read`, not read `$STATE_FILE` directly. The `grep` in the done criteria makes a regression visible.
- `ar_state_get` staying a direct reader is intentional: it needs no repair path, since empty already means "nothing known".
- Healing is silent by design. A tab whose ownership record was lost still opts out on the pass that heals the file, because a label that does not match a known base is indistinguishable from a hand rename. The difference after this change is that `reset` works again. If users report confusion, the follow-up is a `status` action reporting a tab's naming state, not a notification on every pass.
- Watch the cost if the write path ever becomes hot: `ar_state_read` forks a `jq` per write. It is cheap today because `ar_state_claim` skips unchanged claims, so a quiet session writes nothing. A change that makes every pass write per tab would make this validation worth folding into the same `jq` that does the update.

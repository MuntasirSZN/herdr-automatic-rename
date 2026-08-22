# Plan 003: Make the shell lint gate able to fail, and run it in CI

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving on. If anything in "STOP conditions" happens, stop and report. Do not improvise. When done, update this plan's status row in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 8bb0db7..HEAD -- Makefile .github/workflows/ci.yml`
> If either file changed since this plan was written, compare the "Current state" excerpts against the live code first; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S, with an unbounded tail (see the escape hatch in step 3)
- **Risk**: LOW for the tooling change, MED for any code edit it turns out to demand
- **Depends on**: none. Best done AFTER plans 001 and 002 land, so a shellcheck warning inside the code they touch is fixed once, in their diff, rather than twice.
- **Category**: dx
- **Planned at**: commit `8bb0db7`, 2026-08-22

## Why this matters

This project is 2,000 lines of bash targeting stock macOS `/bin/bash` 3.2, where the dangerous mistakes are quoting, word splitting, and constructs that exist in bash 4 but not 3.2. shellcheck catches those, and today nothing runs it:

- `make lint` cannot fail. Its recipe is `command -v shellcheck && shellcheck ... || echo "shellcheck not installed; skipping"`. When shellcheck is absent the `&&` chain short-circuits and the `||` prints the skip message. When shellcheck *is* present and reports a real problem, the chain also fails, so the same `||` fires: the target prints `shellcheck not installed; skipping` and exits 0. Confirmed with a reduced Makefile. `lint-md` has the identical shape, so a genuine markdown violation is reported as `npx not installed; skipping` too.
- CI never invokes shellcheck at all. The `tests` job runs a `bash -n` syntax check plus the suite; the `markdown` job runs markdownlint directly (so markdown *is* gated in CI, just not by `make`).
- The CI syntax check covers 3 of the 13 files the Makefile hands to shellcheck. `icons.sh` is missing, and it is 168 lines of `case` arms full of octal escapes: the file whose glyphs shipped as empty strings once already, per its own header comment.

None of this has produced a known bug; the code is careful and well tested. The point is that the gate the project already decided it wanted has never been able to say no.

The honest uncertainty: nobody has run shellcheck against this codebase, so the size of the backlog is unknown. shellcheck is not installed on the author's machine and installing it was out of scope for the audit. Step 3 handles that with a hard cap and a STOP condition rather than a guess.

## Current state

`Makefile` has three targets in 21 lines. Verbatim, lines 5-21. Recipe body lines must begin with **one literal tab character**, not spaces. The fences below show them as four spaces, because this file is markdown-linted and a hard tab fails that lint. Convert each indented recipe line to a single tab before saving. `make` fails with `*** missing separator` if you get it wrong, so the error is loud.

```make
# Run the full test suite (needs bash + jq only).
test:
    @./tests/run.sh

# Optional static analysis, if shellcheck is installed. The shell hooks are
# per-shell (zsh/fish) so only the portable bash sources are checked.
lint:
    @command -v shellcheck >/dev/null 2>&1 \
        && shellcheck -s bash automatic-rename.sh naming.sh icons.sh shell/hook.bash tests/*.sh \
        || echo "shellcheck not installed; skipping"
    @$(MAKE) --no-print-directory lint-md

# Markdown prose rules, including the no-hard-wrap check CI enforces.
lint-md:
    @command -v npx >/dev/null 2>&1 \
        && npx --yes markdownlint-cli2@0.23.2 \
        || echo "npx not installed; skipping markdownlint"
```

`.github/workflows/ci.yml` has two jobs, `test` (matrix over `ubuntu-latest` and `macos-latest`) and `markdown`. The syntax-check step, verbatim:

```yaml
      - name: Syntax check
        run: |
          for f in automatic-rename.sh naming.sh shell/hook.bash; do
            /bin/bash -n "$f"
          done
          zsh -n shell/hook.zsh
          fish -n shell/hook.fish
```

The `markdown` job is the pattern to copy for a new single-purpose job: `runs-on: ubuntu-latest`, `actions/checkout@v4`, then the tool.

The files the Makefile hands to shellcheck: `automatic-rename.sh` (1,355 lines), `naming.sh` (354), `icons.sh` (168), `shell/hook.bash` (107), and `tests/*.sh` (9 files, 3,333 lines). `shell/hook.zsh` and `shell/hook.fish` are deliberately excluded, being neither bash nor readable by shellcheck. Keep that exclusion. `tests/mocks/herdr` is a bash script with a shebang but no `.sh` suffix, so `tests/*.sh` does not reach it.

Repo conventions to match (see `CONTRIBUTING.md`): bash 3.2 (shellcheck's `-s bash` does not know that restriction, so it will not warn about a bash-4 feature; a clean run is not evidence of 3.2 safety), only `jq` and the herdr CLI at runtime (shellcheck and markdownlint are dev and CI tools, which is already the case), `--` instead of em dashes, no hard-wrapped markdown, and a test with any behavior change.

## Commands you will need

| Purpose | Command | Expected on success |
| --- | --- | --- |
| Lint (after step 1) | `make lint` | exit 0 when clean, non-zero when a tool reports a problem |
| Markdown lint | `make lint-md` | exit 0 |
| Full test suite | `./tests/run.sh` | `# ALL TESTS PASSED`, exit 0 |
| Syntax check | `/bin/bash -n <file>` | exit 0, no output |
| shellcheck version | `shellcheck --version` | prints a version, or "command not found" |

If shellcheck is not installed locally, install it for this work (`brew install shellcheck` on macOS, `sudo apt-get install -y shellcheck` on Debian or Ubuntu). Ask the operator first if you are not permitted to install packages; without it you can still do steps 1, 2 and 4, and must STOP at step 3 rather than guess.

## Scope

**In scope**:

- `Makefile`, the `lint` and `lint-md` recipes.
- `.github/workflows/ci.yml`, the syntax-check file list, plus one new job.
- `automatic-rename.sh`, `naming.sh`, `icons.sh`, `shell/hook.bash`, `tests/*.sh`, **only** for shellcheck fixes or narrowly targeted `# shellcheck disable=` directives, under the rules in step 3.
- `CONTRIBUTING.md`, one line under "Ground rules" if, and only if, you add suppressions, saying how they are written.

**Out of scope** (do NOT touch):

- `shell/hook.zsh` and `shell/hook.fish`. Not bash. Their CI check is `zsh -n` and `fish -n`, which is the right tool and already present.
- Any refactor shellcheck merely suggests as style where the current code is correct and deliberate. This codebase makes considered choices (word splitting in `ar_state_prune $AR_SEEN_TABS` is intentional, for one) and its comments say so. A style warning against a documented decision gets a suppression with a reason, not a rewrite.
- Adding a formatter (`shfmt`) or a pre-commit hook. Different decision.
- The `test` job's matrix, the dependency installs, and the test suite itself.
- Pinning shellcheck through a third-party GitHub Action. Use the runner's package manager, matching how the repo installs `jq`, `zsh` and `fish` today.

## Git workflow

- Branch: `advisor/003-enforce-shellcheck-in-ci`
- Conventional Commits, subject 50 characters or fewer, lowercase. Real examples from `git log`: `ci: fail a hard-wrapped markdown line`, `chore: release 0.7.2`. Suggested: `build: let make lint fail on a real warning`, then `ci: run shellcheck on the bash sources`.
- Commit each step separately. If step 3 produces code fixes, commit those apart from the tooling change so a reviewer can read them on their own.
- Do NOT push and do NOT open a pull request unless the operator asks.

## Steps

### Step 1: Make the lint recipes able to fail

Rewrite both recipes so a missing tool still skips, but a tool that runs and reports a problem fails the target. Use an `if` rather than an `&&` / `||` chain, because the chain is what conflates the two outcomes. Remember the tab rule above.

```make
lint:
    @if command -v shellcheck >/dev/null 2>&1; then \
        shellcheck -s bash automatic-rename.sh naming.sh icons.sh shell/hook.bash tests/*.sh; \
    else \
        echo "shellcheck not installed; skipping"; \
    fi
    @$(MAKE) --no-print-directory lint-md

lint-md:
    @if command -v npx >/dev/null 2>&1; then \
        npx --yes markdownlint-cli2@0.23.2; \
    else \
        echo "npx not installed; skipping markdownlint"; \
    fi
```

Make runs each recipe line in one shell and fails the target on a non-zero exit, so the `if` body's status is now the target's status. Keep the leading `@`, the `-s bash` flag, the exact file list, and the pinned `markdownlint-cli2@0.23.2`.

**Verify** the indentation is tabs, not spaces: `grep -cP '^\t' Makefile` returns 7, and `make -n lint` prints the recipe instead of `*** missing separator`.

**Verify** the skip path still works, without uninstalling anything, by shadowing the tool with an empty `PATH` entry:

```sh
mkdir -p /tmp/nolint && PATH=/tmp/nolint make lint 2>&1 | head -3
```

Expect `shellcheck not installed; skipping` (and the markdownlint skip line), exit 0.

**Verify** the failure path reaches make. With shellcheck installed, this must exit non-zero:

```sh
printf 'x=1\necho $x\nif [ "$x" = 1 ]; then echo yes; fi\ncd /nope\nrm -rf "$undefined_var/"\n' > /tmp/sc-bad.sh
shellcheck -s bash /tmp/sc-bad.sh; echo "shellcheck exit: $?"    # expect non-zero
```

Then confirm `make lint-md` still exits 0 on the current tree.

### Step 2: Widen the CI syntax check and add the shellcheck job

In `.github/workflows/ci.yml`, add `icons.sh` and the test scripts to the `bash -n` loop, plus `tests/mocks/herdr` (a bash script without a `.sh` suffix, which is why a glob misses it):

```yaml
      - name: Syntax check
        run: |
          for f in automatic-rename.sh naming.sh icons.sh shell/hook.bash \
                   tests/run.sh tests/lib.sh tests/test_*.sh tests/mocks/herdr; do
            /bin/bash -n "$f"
          done
          zsh -n shell/hook.zsh
          fish -n shell/hook.fish
```

Add a third job after `markdown`, modeled on that job's shape. Do NOT fold shellcheck into the `test` matrix: it would run twice for one answer, and `apt-get install shellcheck` does not exist on the macOS runner.

```yaml
  shellcheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # The bash sources only. hook.zsh and hook.fish are not bash, and the test
      # job checks those with `zsh -n` and `fish -n`.
      - name: Install shellcheck
        run: sudo apt-get update && sudo apt-get install -y shellcheck

      - name: Lint shell sources
        run: shellcheck -s bash automatic-rename.sh naming.sh icons.sh shell/hook.bash tests/*.sh
```

Keep the file list identical to the Makefile's, so `make lint` and CI cannot disagree.

**Verify**: run the new loop by hand; `/bin/bash -n` over every file in it passes locally.

**Verify** the YAML parses. With `yq`: `yq '.jobs | keys' .github/workflows/ci.yml` -> lists `test`, `markdown`, `shellcheck`. Otherwise `python3 -c 'import yaml,sys; print(list(yaml.safe_load(open(".github/workflows/ci.yml"))["jobs"]))'`.

### Step 3: Triage what shellcheck reports

Run it and count:

```sh
shellcheck -s bash automatic-rename.sh naming.sh icons.sh shell/hook.bash tests/*.sh > /tmp/sc.txt 2>&1; echo "exit: $?"
grep -oE 'SC[0-9]+' /tmp/sc.txt | sort | uniq -c | sort -rn
```

**Escape hatch, read this before fixing anything.** If that summary shows **more than 15 distinct SC codes**, or **more than 60 findings in total**, STOP and report the summary table plus your read of which codes are real. A backlog that size is its own decision, maybe a scoped `.shellcheckrc`, maybe a phased file-by-file rollout, and it is not yours to make silently inside this plan.

Under the cap, triage each finding into one of three buckets:

1. **A real defect** (unquoted expansion that can word-split on real data, a genuine typo, a subshell whose variable assignment is lost). Fix the code. If the behavior it affects is observable, add a test, per `CONTRIBUTING.md`. Say plainly in the commit body what could have gone wrong.
2. **Deliberate and documented.** This codebase does unusual things on purpose and explains them in comments. Add a targeted directive on the line or function, with a reason:

   ```bash
   # shellcheck disable=SC2086  # intentional: tab ids are whitespace-free and this
   # passes them as separate arguments (see ar_state_prune's contract)
   ```

   Rules for suppressions: on the specific line or immediately above the specific function, never at file scope; always naming exactly one SC code, never a bare `disable=`; always with a one-line reason. A suppression without a reason is not acceptable in this repo's comment culture.
3. **Style-only, and the code reads better fixed.** Fix it, in a commit of its own, touching nothing else.

Do not change behavior to silence a warning. If a fix cannot be made without changing what the code does, that is bucket 1 with a test, or bucket 2 with a reason. It is never a quiet rewrite.

**Verify**: `make lint` -> exit 0.

**Verify**: `./tests/run.sh` -> `# ALL TESTS PASSED`. Any code you touched must keep the whole suite green; a failing test means your fix changed behavior.

**Verify**: `/bin/bash ./tests/run.sh` -> `# ALL TESTS PASSED`, since stock 3.2 is the real target.

### Step 4: Document the suppression convention, only if you added one

If, and only if, step 3 added at least one `# shellcheck disable=` directive, add one bullet to the "Ground rules" list in `CONTRIBUTING.md`, in the voice of the bullets already there: a shellcheck suppression names exactly one SC code, sits on the line or function it applies to, and carries the reason it is deliberate. One line, no hard wrapping, `--` instead of an em dash.

If step 3 added no suppressions, skip this step and say so in your report.

**Verify**: `make lint-md` -> exit 0.

## Test plan

There is no new automated test here: the deliverable *is* a gate. What must be demonstrated instead, and reported:

- The skip path prints the skip message and exits 0 (step 1, first verification).
- A real shellcheck failure exits non-zero and no longer prints `shellcheck not installed; skipping` (step 1, second verification).
- `make lint` exits 0 on the final tree (step 3).
- The full suite passes on both `bash` and `/bin/bash` after any code fixes (step 3).
- Any bucket 1 fix ships with a test, following the existing patterns: `tests/test_naming.sh` for pure naming rules, `tests/test_state.sh` for the store, `tests/test_reconcile.sh` for engine behavior against the mock herdr.

## Done criteria

All must hold:

- [ ] `PATH=/tmp/nolint make lint` prints the skip message and exits 0
- [ ] `make lint` exits 0 on the final tree with shellcheck installed
- [ ] `grep -c '||[[:space:]]*$' Makefile` returns 0, so neither recipe still ends a line with the swallowing `||`
- [ ] `.github/workflows/ci.yml` has a `shellcheck` job whose file list is byte-identical to the Makefile's
- [ ] The CI syntax-check loop includes `icons.sh`, `tests/run.sh`, `tests/lib.sh`, `tests/test_*.sh`, and `tests/mocks/herdr`
- [ ] `./tests/run.sh` exits 0 and prints `# ALL TESTS PASSED`
- [ ] `/bin/bash ./tests/run.sh` exits 0 and prints `# ALL TESTS PASSED`
- [ ] `make lint-md` exits 0
- [ ] Every `# shellcheck disable=` added names exactly one SC code and carries a reason
- [ ] `git status --porcelain` lists only files from the In-scope list, plus `plans/README.md`
- [ ] `plans/README.md` status row for 003 updated, with the shellcheck finding count in the row or the dependency notes

## STOP conditions

Stop and report back, do not improvise, if:

- shellcheck cannot be installed in your environment. Do steps 1, 2 and 4 (4 will be a no-op), report step 3 as blocked, and leave the CI job in place. It will run on the GitHub runner even if you could not run it locally. Say clearly in your report that the job is unproven against the actual codebase.
- The report exceeds the caps in step 3 (more than 15 distinct codes, or more than 60 findings).
- A finding looks like a real bug in `automatic-rename.sh`'s locking, state store, or opt-out state machine. Those three carry the plugin's central promise and have dedicated plans and tests. Report the finding with its `file:line` instead of fixing it here.
- Making `make lint` fail correctly requires changing the file list or dropping a file from it. Do not narrow the gate to make it pass.
- A CI-only failure appears that you cannot reproduce locally. Report the run's log rather than guessing at a fix.

## Maintenance notes

- What a reviewer should scrutinize: **the suppressions, not the tooling.** The Makefile and workflow edits are mechanical. Each `# shellcheck disable=` is a claim that the code is right and the linter is wrong, and it should read as such a year from now.
- The Makefile file list and the CI job's file list are duplicated on purpose (a Makefile variable would drift from the workflow's inline string anyway). If a new bash source is added, it goes in both, and the done criteria's byte-identical check catches a miss.
- shellcheck's `-s bash` does not enforce the bash 3.2 target. The macOS CI leg running `/bin/bash` remains the only thing that checks that, so do not let a green shellcheck job become a reason to trust it for portability.
- Deferred deliberately: `shfmt` or any formatter, a pre-commit hook, and running shellcheck over `tests/mocks/herdr`. It has no `.sh` suffix, so adding it means renaming the file or spelling it out separately. Worth doing, as its own small change.
- The `lint-md` recipe had the same swallowing shape and is fixed here alongside `lint`. CI already lints markdown directly, so nothing was actually ungated there; the fix is so `make lint-md` tells a contributor the truth locally.

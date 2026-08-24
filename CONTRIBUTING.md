# Contributing

Bug reports, fixes, and naming-rule tweaks are all welcome.

## Running the tests

The suite needs only `bash` and `jq`:

```sh
./tests/run.sh            # everything
./tests/run.sh reconcile  # only files matching *reconcile*
make test                 # same as ./tests/run.sh
```

Add or update a test with any behavior change. The suite covers the naming rules (`test_naming.sh`), the `[N]` prefix helpers (`test_prefix.sh`), the state store and opt-out state machine (`test_state.sh`), the cross-invocation lock (`test_lock.sh`), the shell hooks (`test_hooks.sh`), and a full reconcile against a fake herdr (`test_reconcile.sh`, driven by `tests/mocks/herdr`).

## Pre-commit hook

`make hooks` installs a git pre-commit hook that runs the same four checks CI runs: bash/zsh/fish syntax, shellcheck, markdownlint, then the suite. It needs [prek](https://prek.j178.dev) (`pre-commit` works too, and the config is the same `.pre-commit-config.yaml`).

```sh
make hooks                # install the hook
prek run --all-files      # run every check now, staged or not
git commit --no-verify    # skip it for one commit
```

Each hook only fires when a file it cares about is staged, so a docs-only commit pays for markdownlint and nothing else. One caveat: `shellcheck` and `npx` are skipped rather than failed when they are not installed locally, so a green hook on a machine without them says less than it looks like.

CI installs the exact shellcheck release named by `SHELLCHECK_VERSION` in the Makefile, because findings move between versions (an SC2218 that 0.9.0 reports, 0.11.0 does not). `make lint-sh` warns when your local shellcheck is a different version. To bump it, edit that one variable.

## Ground rules

- **Target bash 3.2.** macOS ships `/bin/bash` 3.2, so no associative arrays, no namerefs, no `${var^^}`. When in doubt, test with `/bin/bash`.
- **Keep `naming.sh` pure.** Strings in, strings out, no herdr or filesystem calls, so it stays unit-testable. Anything that talks to herdr belongs in `automatic-rename.sh` (the `ar_` prefix).
- **Depend only on `jq` and the herdr CLI.** No other runtime dependencies.
- **No em dashes in comments or docs.**
- **A shellcheck suppression names its code and its reason.** `make lint` and CI both run `shellcheck -x` over the bash sources, and it passes clean. Where the linter is wrong about something deliberate, put `# shellcheck disable=SCxxxx` on the line or compound command it applies to, never at file scope, with a comment saying why the code is right. A sourced file whose path is computed gets `# shellcheck source=<the real file>` instead, so `-x` reads it rather than skipping it.
- **Never hard-wrap prose in markdown.** One paragraph per line. Release notes are copied out of `CHANGELOG.md` and GitHub soft-wraps prose itself, so a wrapped source ships its line breaks. CI enforces this with a custom markdownlint rule (`.github/markdownlint-rules/no-hard-wrap.js`); run it locally with `make lint-md`.

## Submitting

1. Fork and branch.
2. Make the change with a test.
3. Confirm `prek run --all-files` passes (CI runs the same checks, the suite on both Linux and macOS).
4. Open a pull request describing the behavior before and after.

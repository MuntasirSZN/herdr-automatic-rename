# Contributing

Thanks for looking. Bug reports, fixes, and naming-rule tweaks are all welcome.

## Running the tests

The suite needs only `bash` and `jq`:

```sh
./tests/run.sh            # everything
./tests/run.sh reconcile  # only files matching *reconcile*
make test                 # same as ./tests/run.sh
```

Please add or update a test with any behavior change. The suite covers the naming rules (`test_naming.sh`), the `[N]` prefix helpers (`test_prefix.sh`), the state store and opt-out state machine (`test_state.sh`), the shell hooks (`test_hooks.sh`), and a full reconcile against a fake herdr (`test_reconcile.sh`, driven by `tests/mocks/herdr`).

## Ground rules

- **Target bash 3.2.** macOS ships `/bin/bash` 3.2, so no associative arrays, no namerefs, no `${var^^}`. When in doubt, test with `/bin/bash`.
- **Keep `naming.sh` pure.** It takes strings and returns strings, with no herdr or filesystem calls, so it stays unit-testable. Anything that talks to herdr belongs in `automatic-rename.sh` (the `ar_` prefix).
- **Depend only on `jq` and the herdr CLI.** No other runtime dependencies.
- **No em dashes in comments or docs.**
- **Never hard-wrap prose in markdown.** One paragraph per line: release notes are copied out of `CHANGELOG.md` and GitHub soft-wraps prose itself, so a wrapped source ships its line breaks. CI enforces this with a custom markdownlint rule (`.github/markdownlint-rules/no-hard-wrap.js`); run it locally with `make lint-md`.

## Submitting

1. Fork and branch.
2. Make the change with a test.
3. Confirm `./tests/run.sh` passes (CI runs it on Linux and macOS).
4. Open a pull request describing the behavior before and after.

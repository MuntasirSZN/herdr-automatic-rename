# herdr-automatic-rename developer tasks.

.PHONY: test lint lint-md

# Run the full test suite (needs bash + jq only).
test:
	@./tests/run.sh

# Static analysis, skipped when shellcheck is absent and FAILING when it is not.
# An `&& tool || echo skipping` chain cannot tell those apart: a real warning
# took the || branch too, so this target printed "not installed" and exited 0,
# and no local lint gate could ever say no. CI runs the same file list.
#
# -x follows the sourced files, which the `# shellcheck source=` directives in
# each of them name. The shell hooks are per-shell (zsh/fish) so only the
# portable bash sources are checked; CI covers those two with `zsh -n`/`fish -n`.
lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -x -s bash automatic-rename.sh naming.sh icons.sh config.example.sh \
			shell/hook.bash tests/*.sh tests/mocks/herdr; \
	else \
		echo "shellcheck not installed; skipping"; \
	fi
	@$(MAKE) --no-print-directory lint-md

# Markdown prose rules, including the no-hard-wrap check CI enforces. Same shape
# as lint above, and for the same reason: a hard-wrapped line used to report
# itself as a missing npx.
lint-md:
	@if command -v npx >/dev/null 2>&1; then \
		npx --yes markdownlint-cli2@0.23.2; \
	else \
		echo "npx not installed; skipping markdownlint"; \
	fi

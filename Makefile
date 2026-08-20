# herdr-automatic-rename developer tasks.

.PHONY: test lint lint-md

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

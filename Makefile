# herdr-automatic-rename developer tasks.

.PHONY: test lint lint-sh lint-md syntax hooks

# Run the full test suite (needs bash + jq only).
test:
	@./tests/run.sh

# Every static check. The pieces are separate targets so the pre-commit hooks can
# run each one on its own and report which failed.
lint: lint-sh lint-md

# Skipped when shellcheck is absent and FAILING when it is not. An `&& tool ||
# echo skipping` chain cannot tell those apart: a real warning took the ||
# branch too, so this target printed "not installed" and exited 0, and no local
# lint gate could ever say no. CI runs the same file list.
#
# -x follows the sourced files, which the `# shellcheck source=` directives in
# each of them name. The shell hooks are per-shell (zsh/fish) so only the
# portable bash sources are checked; the syntax target covers those two.
lint-sh:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -x -s bash automatic-rename.sh naming.sh icons.sh config.example.sh \
			shell/hook.bash tests/*.sh tests/mocks/herdr; \
	else \
		echo "shellcheck not installed; skipping"; \
	fi

# Markdown prose rules, including the no-hard-wrap check CI enforces. Same shape
# as lint-sh above, and for the same reason: a hard-wrapped line used to report
# itself as a missing npx.
lint-md:
	@if command -v npx >/dev/null 2>&1; then \
		npx --yes markdownlint-cli2@0.23.2; \
	else \
		echo "npx not installed; skipping markdownlint"; \
	fi

# Parse-only pass over every shell file, which catches the typo shellcheck never
# gets to report. Keep this file list identical to the CI workflow's. hook.zsh
# and hook.fish are not bash, so each gets its own interpreter, and each is
# skipped when that shell is absent (CI always has both).
syntax:
	@for f in automatic-rename.sh naming.sh icons.sh config.example.sh shell/hook.bash \
	          tests/run.sh tests/lib.sh tests/test_*.sh tests/mocks/herdr; do \
		/bin/bash -n "$$f" || exit 1; \
	done
	@if command -v zsh >/dev/null 2>&1; then zsh -n shell/hook.zsh; \
		else echo "zsh not installed; skipping shell/hook.zsh"; fi
	@if command -v fish >/dev/null 2>&1; then fish -n shell/hook.fish; \
		else echo "fish not installed; skipping shell/hook.fish"; fi

# Install the git pre-commit hook from .pre-commit-config.yaml, so the checks
# above run before a commit lands rather than after CI says no.
hooks:
	@if command -v prek >/dev/null 2>&1; then prek install; \
	elif command -v pre-commit >/dev/null 2>&1; then pre-commit install; \
	else echo "prek not installed: see https://prek.j178.dev (or pipx install pre-commit)"; exit 1; fi

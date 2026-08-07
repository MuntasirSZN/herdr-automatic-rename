# Changelog

All notable changes to herdr-automatic-rename are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project uses
[semantic versioning](https://semver.org/).

## [Unreleased]

### Added

- The icon map moved out of `naming.sh` into `icons.sh` and grew from 9
  entries to the full `tmux-nerd-font-window-name` map (its
  [`defaults.yml`](https://raw.githubusercontent.com/joshmedeski/tmux-nerd-font-window-name/main/bin/defaults.yml),
  ~170 programs), keeping the aliases this plugin always shipped (gvim/view,
  bun/npx/pnpm, ipython/ipython3) and a robot glyph for every agent herdr
  detects.
- `ICON_FALLBACK` (default `?`): glyph shown when a program is missing from
  the map, like upstream's `fallback-icon`. `''` turns the fallback off and
  keeps unknown programs text-only. Under `ICON_STYLE=icon` the fallback is
  treated as "no glyph", so an unknown program keeps its plain name (`rg`, not
  `?`).
- `ICON_MAP`: per-program icon overrides as `("prog=glyph")` pairs, checked
  before the builtin map (e.g. `ICON_MAP=("claude=󰚩")`).
- Shell labels get no icon even when the map has them: `precmd` names an idle
  prompt without a program, so a glyph would flip the label between `zsh` and
  `<glyph> zsh` on every reconcile. This covers the fixed `SHELLS` six,
  `IGNORED_PROGRAMS` commands showing the shell label, and the user's real
  login shell (`SHELL_NAME`), which can sit outside `SHELLS` (nu, tcsh,
  elvish, ...).
- The login shell is recognized by program, not by computed label: `prog ==
  SHELL_NAME` is its own shell arm, so a reconcile agrees with the bare prompt
  even with `SHOW_PROGRAM_ARGS=1` (no `? -elvish` when `SHELL_NAME=elvish`).
- `HIDE_SHELL` also blanks the login shell itself: with 0.4.0's fixed `SHELLS`
  six, a login shell outside the list (nu, tcsh, elvish, ...) kept naming
  itself on reconcile while the idle label stayed blank.

## [0.4.0] - 2026-08-05

Adds `HIDE_SHELL`, for leaving shell tabs to herdr's own tab number instead of a
row of `zsh`.

### Added

- `HIDE_SHELL=1` leaves a shell tab unnamed instead of labeling it `zsh`, so
  herdr renders its own tab number there and only the tabs running something
  carry a name (issue #5). It covers all three ways a tab gets the shell label: a
  bare prompt, an explicit `SHELLS` entry, and an `IGNORED_PROGRAMS` command. A
  `PROGRAM_ALIASES` entry for a shell still wins, being a name asked for by hand.
  `IGNORED_PROGRAMS` could never do this, despite reading like it should: its job
  is to hold a tab at the shell name, and a bare prompt short-circuits before any
  program list is consulted.
- With `AUTO_INDEX=1` a hidden tab keeps the jump number alone (`[3]`), and the
  `[N] ` prefix helpers now read that bare form back as the empty base it came
  from. Without that a hidden tab would see its own `[3]` as a hand-typed name
  and opt itself out of naming for good.

## [0.3.0] - 2026-08-04

Catches up with herdr 0.7.5 and 0.8.0. `min_herdr_version` stays at `0.7.1`: a
requirement above the running herdr is a hard load failure, so every new
capability is gated at runtime instead.

### Fixed

- Agent numbering has been silently failing since herdr `0.7.5`, in two ways at
  once, both swallowed by the `|| true` on every rename. That release stopped
  resolving `terminal_id` as an agent target (`resolve_agent_target` takes a
  current pane id or a unique agent name), and the plugin passed exactly that,
  since `terminal_id` is always present in `agent list`. It also added
  `valid_agent_name` (`^[a-z][a-z0-9_-]{0,31}$`), which rejects `[1] claude`
  outright. Renames now target `.pane_id`, the one form every supported herdr
  accepts, and agents are numbered only below `0.7.5`. At or above it the
  prefixes are stripped instead, which is also the only way to unstick an
  `[N] claude` an older herdr and older plugin left behind: that name fails
  every rename a newer herdr accepts, the documented uninstall `--clear`
  included. An unreadable herdr version counts as restricted.
- Reordering a worktree group no longer leaves stale `[N]` numbers. herdr
  `0.8.0` added `workspace.move_block` and routes any drag of a worktree-space
  member through it, which emits the new `workspace.reordered` event instead of
  `workspace.moved`. The plugin now subscribes to both, so a group drag
  renumbers immediately rather than waiting for an unrelated event.

### Added

- A `[[startup]]` hook (herdr `>= 0.7.5`) reconciles once as soon as herdr
  restores a session and after a live handoff. Restored sessions previously kept
  herdr's own labels and stale numbers until the first event happened to arrive.
- The agents herdr `0.8.0` detects are all recognized by name now, in
  `NAME_ONLY_PROGRAMS` and in the Nerd Font robot glyph: `pi`, `gemini`,
  `cursor`/`cursor-agent`, `devin`, `agy`/`antigravity`, `cline`, `omp`,
  `mastracode`, `opencode`, `copilot`, `kimi`, `kiro`/`kiro-cli`, `droid`,
  `amp`, `grok`, `hermes`, `kilo`, and `qodercli`. Two spellings differ from
  herdr's `--kind` id (`cursor-agent`, `kiro-cli`) and both forms are listed.
  Previously only `claude`, `codex`, and `aider` were, so every other agent went
  without an icon, and showed its whole command line under
  `SHOW_PROGRAM_ARGS=1`.

### Documentation

- The README records that tab naming does nothing on a Linux runtime where herdr
  cannot see a foreground process group, and points at herdr `0.8.0`'s opt-in
  `HERDR_PROCESS_DETECTION=child-groups`.
- `docs/ARCHITECTURE.md` covers the agent-name restriction and why herdr
  `0.7.5`'s `agent.view.set` would have made static agent numbers unreliable
  regardless: an active view redefines the order `focus_agent` follows, and no
  event or request exposes one.

## [0.2.3] - 2026-08-02

### Fixed

- A wrapped program on NixOS takes its tab name from the command that was typed rather than the wrapper underneath it, so `nh os switch` reads `nh` instead of `.nh-wrapped` ([#6](https://github.com/qu8n/herdr-automatic-rename/issues/6)). `ar_pane_program` read the foreground program from `argv0` and fell back to `name`, but herdr only sends `argv0` on some platforms; its Linux builds send `argv`, `cmdline`, and `name` alone. Those panes therefore named themselves after `name`, which is the on-disk executable rather than the invocation, and on NixOS the executable behind a wrapped program is `.<prog>-wrapped`. `argv[0]` holds what was typed and is present either way, so it now sits between `argv0` and `name`. `name` was a poor last resort regardless: a `claude` pane reports its version string there.

## [0.2.2] - 2026-07-29

### Fixed

- `ICONS_ENABLED=1` now actually prepends a Nerd Font glyph. Every arm of
  `ar_icon` shipped as `printf ''`, so the lookup always returned the empty
  string, the `[ -n "$ic" ]` guard in `ar_format` never passed, and all three
  `ICON_STYLE` modes did nothing. The glyphs were absent from `naming.sh` from
  its first commit, which means icons never worked in any release up to 0.2.1
  ([#3](https://github.com/qu8n/herdr-automatic-rename/issues/3)). Each arm now
  carries its codepoint in a comment so a stripped glyph can be restored, and
  the tests assert the exact bytes rather than only checking that `ICON_STYLE=name`
  suppresses the glyph, which passed happily against an empty string.

## [0.2.1] - 2026-07-26

### Fixed

- Collapsing a worktree space no longer leaves stale workspace numbers behind.
  `alt+N` counts the sidebar's visible rows, so the members a collapsed space hides
  now give up their `[N]` and every row below them moves up. Collapse state is read
  from `collapsed_space_keys` in herdr's `session.json`, the only place herdr
  publishes it (no API field, no event), on herdr's 5-second save debounce.
- A space now takes its number from its main checkout instead of whichever member
  happens to come first in `workspace list`, matching the row herdr renders at the
  head of the group.
- Two linked worktrees of a repo with no main workspace open no longer group
  together. herdr nests a space only with 2+ members and a non-linked checkout
  among them, so these number as the separate top-level rows they render as.

## [0.2.0] - 2026-07-17

### Added

- Subscribe to herdr's `pane.created` event so a split that adds a pane renames
  the tab promptly, even when the split does not move focus.

### Changed

- A full reconcile now reads its whole picture (workspaces, tabs, panes, agents)
  from a single `herdr api snapshot` call instead of one query per list plus a
  `tab list` per workspace. Needs herdr `>= 0.7.2`; older herdr falls back to the
  per-list queries automatically, so the minimum supported version stays `0.7.1`.

## [0.1.1] - 2026-07-12

### Fixed

- Calling a shell function (or builtin, reserved word, or mistyped command) no
  longer flashes that word onto the tab before the prompt reverts it. The hooks
  now classify the command word; anything that is not an external command makes
  the engine name the tab by the pane's real foreground process, sampled after
  a short settle. A function that wraps a long-running program now names the
  tab after that program instead of the function.

## [0.1.0] - 2026-07-11

First public release.

### Added

- Tab naming (`NAME_TABS`): each tab is named after its foreground program, or
  the shell name at a bare prompt. A hand rename opts the tab out.
- Jump-key numbering (`AUTO_INDEX`): workspaces, tabs, and agents are prefixed
  with the `1-9` number of the keybind that jumps to them.
- Live per-command naming through zsh, bash, and fish shell hooks that resolve
  the engine relative to their own location.
- `reset` and `clear` plugin actions.
- Configuration via `~/.config/herdr-automatic-rename/config.sh` (or
  `$HERDR_AUTOMATIC_RENAME_CONFIG`), with a documented `config.example.sh`.
- A self-contained test suite (bash + jq only) covering naming, prefix helpers,
  the state machine, the shell hooks, and a full reconcile against a fake herdr.

[Unreleased]: https://github.com/qu8n/herdr-automatic-rename/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/qu8n/herdr-automatic-rename/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/qu8n/herdr-automatic-rename/compare/v0.2.3...v0.3.0
[0.2.3]: https://github.com/qu8n/herdr-automatic-rename/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/qu8n/herdr-automatic-rename/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/qu8n/herdr-automatic-rename/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/qu8n/herdr-automatic-rename/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/qu8n/herdr-automatic-rename/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/qu8n/herdr-automatic-rename/releases/tag/v0.1.0

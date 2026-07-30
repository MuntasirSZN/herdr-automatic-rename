# Changelog

All notable changes to herdr-automatic-rename are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project uses
[semantic versioning](https://semver.org/).

## [Unreleased]

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

[Unreleased]: https://github.com/qu8n/herdr-automatic-rename/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/qu8n/herdr-automatic-rename/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/qu8n/herdr-automatic-rename/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/qu8n/herdr-automatic-rename/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/qu8n/herdr-automatic-rename/releases/tag/v0.1.0

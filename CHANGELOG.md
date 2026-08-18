# Changelog

All notable changes to herdr-automatic-rename are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project uses
[semantic versioning](https://semver.org/).

## [Unreleased]

### Fixed

- A tab whose rename herdr rejected stopped being named at all. Ownership was
  recorded before the rename was issued, so a failed one left state claiming a
  base the tab did not carry; the next pass compared the two, read the mismatch
  as a name typed by hand, and opted the tab out of auto-naming for good --
  recoverable only through the `reset` action. Ownership is now recorded for a
  name the tab actually carries: the label already matches, or the rename
  reported success. The shell-hook fast path has always ordered it this way.

- A background tab with more than one pane kept the name it had when it last had
  a single pane, so a split that started an agent still read `nvim`. Naming had
  no pane to read: none of a background tab's panes carries `.focused`, and the
  pane list is all the pass looked at. It now takes the tab's own
  `focused_pane_id` from the snapshot's `layouts`, which answers for every tab.
  Older herdr, whose snapshot has no layouts, keeps the previous behavior.

- The focused tab was named from the GLOBALLY focused pane, which belongs to
  whichever client moved focus last. With a second client attached, or a remote
  attach, that pane can sit in a different tab. Per-tab layouts remove the guess,
  and the pane-list fallback now reads only the tab's own panes. A focused tab
  with several panes and no focused pane of its own -- which is what that same
  second client looks like on a herdr with no layouts -- keeps the label it has
  rather than being named after an arbitrary one of them.

- Where herdr named no foreground process group at all but still reported one
  process for the pane, no name was computed. Some Linux container and sandbox
  setups cannot expose a foreground group, which is what left tab naming doing
  nothing there. A single reported process is not a choice, so such a pane is now
  named after it. Two or more with no named group would be: herdr does not order
  that list and documents its own degraded detection as one where a background job
  can look like the foreground one, so those panes keep the label they have. A
  group herdr DID name whose process is absent from the list is a group racing its
  own exit, and still computes no name; so does a pane herdr reports no process
  for.

- A label carrying a control character reached herdr verbatim: `argv` can hold a
  newline or a tab, so `SHOW_PROGRAM_ARGS=1` could put one in the tab bar. They
  are now replaced where they arrive, in the jq that reads `pane process-info`,
  and the label has its whitespace runs collapsed and its ends trimmed before
  truncation. A clean label -- nearly all of them -- costs no extra process.

  The two values that reader returns travel one per line now rather than as TSV.
  `@tsv` escaped a real tab into the printable two characters `\t`, which no
  scrub downstream can tell from text somebody typed, and it doubled every
  backslash in a command line on the way past.

- A tab carrying no label at all was never named again. Its row had an empty
  field in the middle, and the rows were split on a tab, which bash counts as
  whitespace: `read` collapses a run of them, so every field after the empty one
  shifted and the tab read its own pane count as its label. `HIDE_SHELL=1` with
  numbering off is exactly that state, so a tab blanked once stayed blank however
  many programs ran in it. Rows are split on the ASCII unit separator now, which
  keeps an empty field in place; nothing can carry one, since the values have
  their control characters removed on the way out of jq.

- A name this plugin owns is now written until herdr holds exactly it. Rows
  arrive with control characters replaced, so a label carrying one read as equal
  to the name computed for it and no rename looked necessary, which left the
  character there for good. A label the plugin does NOT own is still left exactly
  as the user typed it.

- Numbering a tab whose name holds a backslash rewrote that name. Every row the
  reconcile reads came back through `@tsv`, which doubles a backslash, so a tab
  called `C:\temp` was renamed to `C:\\temp` (workspace and agent rows read the
  same way). Rows now carry their values unescaped and drop control characters
  instead, which is what keeps them parseable. The same change lets a tab whose
  label carries a control character stay owned: escaped, it matched nothing this
  plugin had recorded and the tab read as renamed by hand.

## [0.6.1] - 2026-08-14

### Fixed

- An agent whose entrypoint is an interpreted script named its tab after the
  interpreter. An npm bin shim is a JS file behind a node shebang, so the kernel
  execs the runtime and the pane's foreground process is `node` on every
  platform: a codex pane read `node`. Before 0.2.3 the same pane read
  `MainThread` -- the resolution chain then had no argv[0] step, so a Linux
  pane (no argv0) fell through to the process's `name`, which for node is its
  thread name; the #6 fix moved these tabs from `MainThread` to `node`. A pip
  or pipx installed agent hits the same thing through `python`, its console
  script being a shebang file too. (An agent whose package ships or execs a
  native binary -- claude, opencode -- reports its own name and was never
  affected.)

  Where the foreground program is a language runtime or package runner (the new
  `WRAPPER_PROGRAMS` list) and herdr has detected an agent in that pane, herdr's
  answer is used instead and the tab reads `codex`. The agent is read off the
  pane objects the reconcile already holds -- herdr publishes its detection
  result on the pane itself -- so the lookup costs no extra herdr call on any
  version.

  Both conditions are required, so a plain `node server.js` tab keeps its name,
  and an agent that reports its own name never consults the pane's agent field.
  Identification stays herdr's job on purpose: its detector already unwraps
  runtime-fronted agents, so a pane it cannot identify is an upstream detection
  gap, not something this plugin second-guesses from `argv`.

## [0.6.0] - 2026-08-13

Splits the `[N]` jump-key numbering by item kind. `AUTO_INDEX_WORKSPACES`,
`AUTO_INDEX_TABS` and `AUTO_INDEX_AGENTS` each override `AUTO_INDEX` for one
kind of row, so numbered tabs above plain workspace names is one line of
config.

Nothing changes for a config that names none of the new knobs. `AUTO_INDEX`
still switches all three kinds together.

### Added

- `AUTO_INDEX_WORKSPACES`, `AUTO_INDEX_TABS` and `AUTO_INDEX_AGENTS` split the
  `[N]` numbering by item kind ([#8](https://github.com/qu8n/herdr-automatic-rename/issues/8)).
  Each defaults to `AUTO_INDEX` and overrides it when set, so numbered tabs above
  plain workspace names is `AUTO_INDEX_WORKSPACES=0` on its own. Existing
  configs are unaffected: `AUTO_INDEX` still switches all three together.

### Changed

- Setting one of the new per-kind knobs to `0` strips the `[N]` already on those
  rows at the next event, instead of leaving them until the `clear` action.

  Only a knob you set does this. The strip cannot tell a prefix this plugin
  wrote from one you typed, so a hand-picked `[1] incident` would lose its
  bracket, and naming the kind is how you ask for that. A config carrying only
  `AUTO_INDEX=0` never triggers it: workspace and agent labels there are left
  alone, exactly as before. Tabs are the one kind already stripped this way
  whenever `NAME_TABS=1`, and that is unchanged. Only all-digit brackets are
  ever touched; `[wip] deploy` is safe throughout.

## [0.5.0] - 2026-08-07

Grows the icon map from 9 entries to ~170 and makes it configurable, with
`ICON_FALLBACK` for programs it does not know and `ICON_MAP` for per-program
overrides.

Upgrade note for anyone already running `ICONS_ENABLED=1`: programs outside the
map now show a `?` where they previously showed no glyph at all. Set
`ICON_FALLBACK=''` to keep them text-only.

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

### Fixed

- `HIDE_SHELL` now blanks the login shell itself. With 0.4.0's fixed `SHELLS`
  six, a login shell outside the list (nu, tcsh, elvish, ...) kept naming
  itself on reconcile while the idle label stayed blank.
- The login shell is recognized by program rather than by computed label:
  `prog == SHELL_NAME` is its own shell arm, so a reconcile agrees with the
  bare prompt even with `SHOW_PROGRAM_ARGS=1`, where the command-line path used
  to hijack it.

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

[Unreleased]: https://github.com/qu8n/herdr-automatic-rename/compare/v0.6.1...HEAD
[0.6.1]: https://github.com/qu8n/herdr-automatic-rename/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/qu8n/herdr-automatic-rename/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/qu8n/herdr-automatic-rename/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/qu8n/herdr-automatic-rename/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/qu8n/herdr-automatic-rename/compare/v0.2.3...v0.3.0
[0.2.3]: https://github.com/qu8n/herdr-automatic-rename/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/qu8n/herdr-automatic-rename/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/qu8n/herdr-automatic-rename/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/qu8n/herdr-automatic-rename/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/qu8n/herdr-automatic-rename/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/qu8n/herdr-automatic-rename/releases/tag/v0.1.0

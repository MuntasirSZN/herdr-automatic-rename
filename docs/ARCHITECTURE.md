# Architecture

This documents the non-obvious decisions in herdr-automatic-rename. For usage, see the [README](../README.md).

## One reconcile, one entry point

`automatic-rename.sh` is invoked for every herdr event, both plugin actions, and the shell hooks' fast path. It routes through `ar_run` and dispatches on `argv[1]`. A full reconcile pulls its whole picture — workspaces, tabs, panes, and agents — from one `herdr api snapshot` (a single socket call, herdr >= 0.7.2), then computes the label every item should have and issues one rename per item whose label is wrong. Older herdr with no `api snapshot` falls back to reading `workspace list`, `pane list`, and `agent list` once each plus `tab list` per workspace. Either way, per-tab foreground detection stays one `pane process-info` per named tab — the snapshot carries the pane list but not each pane's foreground process.

Computing a tab's name and its `[N]` prefix in the same pass is what lets a brand-new tab settle at `[3] zsh` in a single rename. Every rename is skip-if-correct, so re-firing the pass (herdr's own rename re-emits `tab.renamed`) changes nothing and cannot loop.

## Naming lives in a pure module

`naming.sh` turns `(program, cmdline, title)` into a display name and touches neither herdr nor the filesystem. That keeps the naming rules (shells, name-only programs, ignored programs, aliases, substitutions, agent titles, truncation, icons) unit testable in isolation. The icon knobs, glyph map, and lookup live in `icons.sh` (sourced by `naming.sh`) so the 100+ arm case statement stays out of the naming logic. The engine calls `ar_format` across that seam. Every function in these files uses the `ar_` prefix.

## Rows carry values, not escapes

Every `jq` that hands a herdr string to a shell variable runs it through the one `clean` definition (`AR_JQ_CLEAN`) and joins its row on a literal tab. `@tsv` would keep the row parseable by escaping what breaks it, and those escapes are the bug: a tab out of `argv` arrives as the two printable characters `\t`, which nothing downstream can distinguish from typed text, and every backslash in the value is doubled, so numbering a tab called `C:\temp` used to rewrite it as `C:\\temp`. Dropping the control characters instead makes the row unambiguous and leaves everything a user can see untouched. `ar_pane_program` goes one further and returns its two values one per line, which is sound for the same reason.

The delimiter is the ASCII unit separator, not a tab, because bash counts a tab as IFS whitespace: `read` collapses a run of them, so a single empty field shifts every field after it. A tab with no label (what `HIDE_SHELL` leaves) used to parse its pane count as its label and was never named again. `clean` is what makes the separator safe, since no value can contain a character in that class.

## Why config and state sit at fixed paths

State (`~/.local/state/herdr-automatic-rename/`) and config (`~/.config/herdr-automatic-rename/config.sh`) use fixed paths, not `$HERDR_PLUGIN_STATE_DIR` / `$HERDR_PLUGIN_CONFIG_DIR`. The live shell hooks run `preexec`/`precmd`, launched by your shell, not by herdr, so they never receive the `HERDR_PLUGIN_*` variables. The herdr-invoked pass and the shell-invoked fast path must share one config and one state store, which forces a path both can name without herdr's help. `$HERDR_AUTOMATIC_RENAME_CONFIG` overrides the config location.

herdr exposes no per-tab metadata and no auto/manual flag, so the manual-rename opt-out is tracked in a small JSON state file keyed by `tab_id`: the last base the plugin set, and whether auto-naming is still enabled for that tab.

That recorded base is the plugin's only evidence of what it named a tab, so it is written for a name the tab actually **carries** -- the label already matches, or the `rename` reported success. A base recorded for a rename that never landed is indistinguishable, one pass later, from a name typed by hand: the label does not match what state claims, so the tab opts out of naming and only the `reset` action brings it back.

## Locking

A `mkdir` lock (atomic, ownership-token stamped, 30-second steal window) plus a rerun flag coalesces a burst of events into one worker. Contenders raise the rerun flag and exit; the holder loops until no new work arrives. A fast-path run that loses the lock still lands, because the holder's re-pass is a full reconcile that recomputes names itself.

An **action** cannot defer that way. Deferring works because every pass computes the same thing, and an action's request does not live in the state the holder reads: which tab to re-adopt, or whether to strip, is in the contender's own process. So `reset` and `clear` wait for the lock (bounded, since a pass runs in well under a second) and report that they are waiting rather than handing the job to a pass that knows nothing about it. Exiting there is what used to make a reset pressed during a burst of events do nothing, and say nothing either.

A reset's force is spent by the pass that consumes it. The holder can loop its reconcile when events land while it runs, and a tab still forced on a later loop is a tab whose opt-out check is still bypassed: rename it by hand inside that window and the loop would take the name back, which is the one promise this plugin makes.

## The shell hooks find their own engine

herdr installs a github plugin to a content-hashed directory, so the hooks cannot hard-code the engine path. Each hook resolves `automatic-rename.sh` relative to its own sourced-file location: zsh via `${(%):-%N}`, bash via `BASH_SOURCE[0]`, fish via `status current-filename` captured into a global. The bash hook never overwrites a `DEBUG` trap another tool already set, and cooperates with `bash-preexec` / `ble.sh` / `atuin` when present.

## Shell constructs are sampled, not trusted

The preexec fast path names the tab by the first word of the command line, which is only honest when that word resolves to an external program. zsh expands aliases in preexec's `$2` but never expands functions, and bash and fish hand over the raw line, so a function `l`, a builtin, a reserved word, or a typo arrives verbatim. No program list can match those words (`IGNORED_PROGRAMS` holds `eza`, not the function `l` that calls it), so trusting them renamed the tab and let precmd snap it back: a flicker on every instant construct.

Each hook classifies the command word (`whence -w` in zsh, `type -t` in bash, `type --type` in fish). External commands keep the instant rename. Everything else gets a `shell` marker, and the engine sleeps 0.2 s (before taking the lock), then names the tab by the pane's actual foreground process via `pane process-info`. An instant construct has exited by then, so the leader is the shell again and nothing is renamed. A construct that wraps a long-running program gets that program's real name, which the typed word never was. When sampling fails the engine renames nothing rather than guess.

## Numbering caveats

- **Tabs** are numbered by array order, not the non-contiguous `.number` field.
- **Workspaces** are numbered by herdr's visible sidebar order, not the raw `workspace list` order. `alt+N` resolves through herdr's own `workspace_at_visible_position`, so a row the sidebar does not render is a row no keybind reaches, and a collapsed space both hides rows and moves the ones below it. `ar_workspace_positions` mirrors herdr's `workspace_list_entries_inner` and owns the rules (which workspaces nest, which member heads a space, what a collapsed one still renders); its header comment is the copy to keep in sync with upstream. Hidden rows come back as position 0 and drop their prefix like 10+.
- **Agents** are numbered only on herdr `< 0.7.5`, and there only when `agent_panel_sort` is grouped (`spaces`).
  - herdr `0.7.5` added `valid_agent_name` (`^[a-z][a-z0-9_-]{0,31}$`, `src/app/agents.rs`) and now answers `invalid_agent_name` to anything else, so `[N] claude` is not a name that release can hold. `ar_agent_prefix_ok` gates on the version and an unreadable version counts as restricted, because declining to number is recoverable and firing renames herdr rejects is not. The same release also stopped resolving `terminal_id` as an agent target (`resolve_agent_target`, `src/app/terminal_targets.rs`), so renames target `.pane_id`, the one form every supported version accepts.
  - Where it does apply, `priority` sort still opts out: the panel reorders behind an order the CLI never exposes, so the plugin strips agent numbers rather than guess wrong, and renumbers when you switch back.
  - Stripping runs on the restricted versions too, which is what unsticks an `[N] claude` written by an older herdr and older plugin. Nothing else can: that name fails every rename a newer herdr accepts, including `--clear` aimed at a `terminal_id`.
  - Numbering keeps its two-phase park (park at a unique temp, then finalize) to dodge herdr's duplicate-name rejection when several agents share a base like `claude`. It is reachable only on herdr `< 0.7.5`.
  - `agent.view.set` (herdr `0.7.5`) is a further reason the feature stops there. An active view redefines the order `focus_agent` follows, by sort or by filtering rows out, and `apply_agent_view` bypasses `agent_panel_sort` entirely. No event announces a view and no request reads one back, so a plugin cannot even detect the drift. Both of those releases are ones where agent numbering is off anyway.
- Nothing numbers past 9, since no keybind reaches a 10th item.

## Collapse is readable, but only from session.json

herdr publishes sidebar collapse nowhere in its API: no field on `workspace list` or `api snapshot`, no request method, and none of the events a plugin can subscribe to (checked against protocol 17). Toggling a space flips `collapsed_space_keys` in memory and marks the session dirty, which leaves one readable copy: the top-level `collapsed_space_keys` array in that session's `session.json`. `ar_collapsed_spaces` reads it, at the path `ar_herdr_session_dir` derives by stripping the filename off `$HERDR_SOCKET_PATH`. herdr keeps a session's socket, `session.json`, and `config.toml` in one directory and exports that variable into plugin commands and pane environments both, so the herdr-invoked pass and the shell hooks resolve the same files, in a named session as well as the default one. `ar_agent_sort` reads its `config.toml` through the same helper for that reason.

Two consequences follow. The file is written atomically (temp plus rename, so no torn reads) on a 5-second debounce, so a pass that runs right after the click still reads the old value and corrects itself on a later event. And because the toggle emits no event, nothing wakes the plugin when collapse changes: the numbers settle on whatever event arrives next, which in an active session is usually seconds away (`pane.agent_status_changed` fires constantly). So the first `alt+N` after a collapse can still jump by the old numbering. Upstream support, either an event or a `collapsed` field on `WorkspaceInfo`, is what would close that window.

## An agent tab is named from its terminal title

Five agent panes named after their foreground program give five tabs reading `claude`, which is the one thing the program-name rule cannot fix. The task is what tells them apart, and a coding agent already publishes it: it sets its terminal title to a description of the work and keeps that current as the work moves. So where herdr reports an agent for the pane, `ar_tab_name` prefers the title over the program name (`AGENT_TITLES`, default on).

Reading it is free. herdr publishes the title on the pane object itself, beside the detection result, so `ar_pane_facts` lifts the agent, the title, and the pane's directory out of the `AR_PANES_JSON` the reconcile already fetched: one jq over cached JSON, no herdr call on any version. A title that lands also ends the computation, so such a tab skips the `pane process-info` call the program path needs, which leaves an agent-heavy session making fewer herdr round-trips than before. The local cost is a wash rather than a saving: the reply that used to be parsed is simply not fetched, and the values come off the tab row instead. Refreshes ride `pane.agent_status_changed`, an event the plugin already subscribes to for agent numbering, so the label follows the work with nothing polling.

`ar_title_clean` decides whether a title says anything. It refuses:

- the agent naming itself: its herdr kind (`claude`), that kind followed by `code` (`Claude Code`), or a `TITLE_IGNORE` entry, which is what an agent titles a session it has no task for yet;
- the directory the pane sits in, which is what claude falls back to at startup;
- a bare number, which is herdr's own generated tab label handed back through the title.

Each refusal returns the empty string, and naming carries on to the program, `PROGRAM_ALIASES` and the `WRAPPER_PROGRAMS` unwrapping included. A title that survives replaces the program name outright, alias and all: `AGENT_TITLES` is the request for the task, and an alias shortening `claude` to `cl` is not a request to hide the work. The program still supplies the icon, and the label gets its own budget, `MAX_TITLE_LEN` (28) rather than `MAX_NAME_LEN` (20), cut at a word boundary when that leaves at least half of it -- a title is a sentence, and `Investigate` says more than `I` does.

The first thing `ar_title_clean` does is drop the leading run of non-alphanumerics. herdr keeps an ANSI-stripped copy of the title (`terminal_title_stripped`) and stripped means exactly that: the spinner glyph an agent parks in front of its title while it works is still on it, and claude cycles four of them. Without the strip the label would flip between `Task` and `<glyph> Task` on every status event, and each flip is a rename.

`jq` does that strip, and the case-folding both sides of the comparisons above need, in one call. Its character classes know Unicode; a byte-wise strip would eat the first letter of a title that opens with a non-ASCII word, and herdr may launch a plugin with no `LC_*` at all. Reaching for jq keeps the function inside the module's rule rather than bending it -- strings in, strings out, no herdr and no filesystem -- and `ar_format` next door already calls it to truncate on codepoint boundaries for the same locale reason.

## Which pane names a tab

A tab's name comes from one of its panes, so the pass has to pick that pane. The snapshot's `layouts` array is what makes the choice possible: one entry per tab, each carrying the `focused_pane_id` of that tab's own focus. It holds for tabs nobody is looking at, which the pane list cannot report -- no pane of a background tab carries `.focused` -- and it is per-tab, so it never picks up the globally focused pane, which belongs to whichever client moved focus last and may sit in another tab entirely (herdr supports several clients and remote attach).

Focus alone is not the whole answer for a tab with several panes, though. A split with an agent in one pane and a shell in the other is about the agent, and while the agent works focus sits in the shell, so naming by focus alone advertised the shell. The reshape picks, in order:

1. the tab's own focused pane, when herdr reports an agent running in it;
2. any pane of the tab holding an agent whose status is `working` or `blocked`;
3. the tab's own focused pane.

Rule 2 asks for a status on purpose. An idle agent has nothing to say about a tab you have moved on to, and naming that tab after it would take the label away from the pane you are reading.

That is per-tab data, so it travels with the tab: the reshape that slices the snapshot joins the pane it picked onto each tab row as `_name_pane`, along with that pane's agent, task title and directory, and the tab loop reads all of it off the row it already has. `ar_resolve_pane` holds only the inference for rows where the column is empty, which costs the loop nothing on either path.

Those lifted facts describe **the pane the reshape picked**, and nothing else, so naming uses them only when the pane it resolved is that pane. Where the column came back empty the pane came from the pane list instead, and its facts have still to be read: taking the row's empty fields for that pane cost such a tab both its title and the runtime unwrap, so a `node`-fronted agent read `node` again.

Older herdr, and the per-list fallback path, ship no layouts. Rules 1 and 3 both ask for the tab's own focused pane, so neither can be answered there. Rule 2 asks only for an agent at work among the tab's panes, so it still can, and it still does: a no-layout snapshot names such a tab after that agent. Deliberate -- a split with an agent working in it is the case the rule exists for, and the rule never needed a layout to see it. Everything else falls to the inference in `ar_resolve_pane`: the sole pane of a single-pane tab, else the tab's own focused pane, else nothing. So a background multi-pane tab keeps whatever name it has unless an agent is working in it.

The per-list path is the narrower case. With no snapshot there is no reshape at all, so rule 2 never runs either and that inference is the whole of it.

## The placeholder rule

herdr labels a fresh tab with a small integer. When naming is on but the tab's foreground program cannot be read yet (no pane resolves, or `process-info` answers nothing), the pass counts the tab's position but defers its rename, so no throwaway `[3] 3` flashes before the real name arrives. When naming is off, the integer is numbered as-is, since nothing else will ever name it.

## An empty name is a name (HIDE_SHELL)

`HIDE_SHELL=1` labels a shell tab with the empty string, because that is the only way to get herdr's own tab number back on screen: herdr renders the number whenever a tab has no label, and there is no API to ask for it directly.

The empty string is now a name the engine has to carry around, so the invariant is: **a name is returned on stdout, and "cannot compute one" is reported only through exit status, never as empty output.** Every site that could confuse the two follows from it:

- `ar_tab_name` reports failure through its exit status instead of an empty string, and `ar_reconcile_tabs` branches on that status rather than on the string it got back.
- The `[N] ` prefix helpers accept a bare `[3]`, the numbered form of an empty base. Without that, a hidden tab would read its own label back as a hand-typed name and opt itself out of naming permanently.
- `ar_desired` numbers an empty base as `[3]` rather than `[3] `, since herdr drops the trailing space anyway and the bare form round-trips back through `ar_strip_prefix`.
- The opt-out state machine keeps a tab whose recorded name is empty even when the label reads as herdr's integer again, which is what a restored session and herdr's own relabeling look like from here.
- `ar_reconcile_tabs` writes an empty base when the emptiness is deliberate, and skips the tab only when herdr has not labeled it at all.
- The fast path is the one exception: it calls `ar_format` directly rather than through `ar_tab_name`, so it has no status to read and tests `HIDE_SHELL` itself to decide whether an empty `ar_format` result is an answer.

The placeholder rule above is unaffected: it defers a tab whose name is not computable *yet*, while an empty name is computed and final.

## Testing

`tests/` runs on bash and jq alone (no bats). It covers the pure naming rules, the `[N]` prefix helpers, the JSON state store and opt-out state machine, the shell hooks, and a full reconcile driven against a fake `herdr` (`tests/mocks/herdr`) that serves fixture JSON and records every rename the engine issues. Sourcing `automatic-rename.sh` defines its functions but runs nothing (guarded by `BASH_SOURCE[0] == $0`), so the helpers can be exercised directly.

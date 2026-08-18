# herdr-automatic-rename

[![tests](https://github.com/qu8n/herdr-automatic-rename/actions/workflows/ci.yml/badge.svg)](https://github.com/qu8n/herdr-automatic-rename/actions/workflows/ci.yml)

This plugin makes it easier to navigate your herdr surfaces:

**Name each tab after what it is running.**

- Inspired by [tmux](https://github.com/tmux/tmux)'s `automatic-rename`, a tab shows its foreground process (`nvim`, `claude`) or the shell (`zsh`) instead of simply `1`, `2`, `3`, etc.
- Even better, tabs running a coding agent automatically show the active tasks, with helpful names like `Squash merge command` and `Check PR 2169 relevance`.

**Prefix workspaces and tabs with their jump number.**

- An `[N]` matching the `1-9` binding for that slot, so you can glance at the tab bar or sidebar and use a keyboard shortcut to quickly jump there.
- Agents get one too on herdr `< 0.7.5` when the name rule allowed it.

Each of these features can be toggled independently:

- `NAME_TABS=0` turns off naming, and every tab keeps the name herdr gave it.
- `AUTO_INDEX=0` turns off numbering, and nothing gets an `[N]`.

<img width="3216" height="2088" alt="readme-demo-screenshot" src="https://github.com/user-attachments/assets/43f620c0-d667-4fa9-b76c-dbafde41b7ec" />

## Before and after

herdr labels a new tab with a number and leaves workspace rows at their plain names. One four-tab workspace on the stock config (`NAME_TABS=1`, `AUTO_INDEX=1`):

```
herdr alone      │ 1       │ 2        │ 3       │ notes     │
with the plugin  │ [1] zsh │ [2] nvim │ [3] zsh │ [4] notes │
```

| Tab is running | herdr alone | with the plugin |
| --- | --- | --- |
| a bare shell prompt | `1` | `[1] zsh` |
| `nvim README.md` | `2` | `[2] nvim` |
| `ls -la`, an `IGNORED_PROGRAMS` entry | `3` | `[3] zsh` |
| a tab you renamed `notes` yourself | `notes` | `[4] notes` |
| `claude`, mid-task | `1` | `[1] Squash merge command` |
| `claude`, nothing asked of it yet | `2` | `[2] claude` |

Workspaces are numbered, never renamed. `dotfiles` becomes `[1] dotfiles`. Agent rows keep their detected names on current herdr (see [Notes](#notes)).

### Agent tabs

herdr publishes the terminal title on the pane object it already sends, so the task label costs no extra call. It refreshes on `pane.agent_status_changed`, so nothing polls. The spinner glyph an agent parks in front of its title is stripped off, or the label would flip on every status change.

A title has to say something to be used. One that names the agent rather than the work (`Claude Code`, the agent's own kind, anything in `TITLE_IGNORE`), one that is the pane's directory or the path to it, and a bare number are all refused, and the tab falls back to the program name. `AGENT_TITLES=0` turns titles off and names every agent tab after its program, as before.

For a tab with several panes, the name comes from the pane that matters: the tab's own focused pane when an agent runs in it, else an agent working or blocked anywhere in the tab, else the focused pane. An agent-plus-shell split still reads as the agent while you type in the shell half, and an idle agent does not take the name away from what you are looking at. The shell hook is per-pane, so a command you start in that half names the tab the instant it starts, until the next herdr event applies the rule above again.

### Quiet shell tabs

If a row of `zsh` tabs tells you nothing, `HIDE_SHELL=1` names only the tabs actually running something and leaves the rest to herdr's own tab number:

```
HIDE_SHELL=0, AUTO_INDEX=0  │ lazygit     │ nvim     │ fish │ pi     │
HIDE_SHELL=1, AUTO_INDEX=0  │ lazygit     │ nvim     │ 3    │ pi     │
HIDE_SHELL=1, AUTO_INDEX=1  │ [1] lazygit │ [2] nvim │ [3]  │ [4] pi │
```

That covers a bare prompt, an explicit shell, the login shell itself, and anything in `IGNORED_PROGRAMS`. With numbering on, the label keeps the jump number, so you can still get there.

## Requirements

herdr `>= 0.7.1`, `jq`, and bash. Linux or macOS.

Newer herdr versions add more, each detected at runtime:

- `0.7.2`: a reconcile reads herdr's whole state in one `api snapshot` call instead of per-list queries.
- `0.7.4` (recommended): a plugin rename repaints the tab bar immediately. Below it the new name still lands, but the bar catches up only on the next redraw, such as a focus change or a resize.
- `0.7.5`: a restored session is reconciled when herdr comes up rather than at the first event.
- `0.8.0`: reordering a worktree group renumbers right away.

## Install

```sh
herdr plugin install qu8n/herdr-automatic-rename --yes
```

Events work immediately.

### Shell hook (highly recommended)

Renames the instant a command starts. Without it, naming waits for the next focus or tab event. Source your shell's hook, which self-locates the engine wherever herdr installed it.

**zsh** (`~/.zshrc`):

```zsh
for _f in ${HOME}/.config/herdr/plugins/github/herdr-automatic-rename-*/shell/hook.zsh(N); do
  source $_f; break
done
```

**bash** (`~/.bashrc`, after any prompt or history tool like starship or atuin):

```bash
for _f in "$HOME"/.config/herdr/plugins/github/herdr-automatic-rename-*/shell/hook.bash; do
  [ -r "$_f" ] && { source "$_f"; break; }
done
```

**fish** (`~/.config/fish/config.fish`):

```fish
for _f in $HOME/.config/herdr/plugins/github/herdr-automatic-rename-*/shell/hook.fish
    test -r "$_f"; and source "$_f"; and break
end
```

Outside a herdr pane the hook does nothing. On bash it cooperates with bash-preexec, atuin, and ble.sh, else owns `DEBUG` without clobbering an existing trap.

A command word that is not an external program (a shell function, a builtin, or a typo) never renames the tab directly. The hook flags it and the engine reads the pane's real foreground process a moment later, so an instant function leaves the tab name alone and a function that opens `nvim` names the tab `nvim`.

### Turn off herdr's new-tab name prompt

herdr asks each new tab for a name (`prompt_new_tab_name`, on by default). Under `NAME_TABS=1` that prompt has nothing left to do, and a name typed into it counts as a hand rename, which opts the tab out until you `reset` it:

```toml
# ~/.config/herdr/config.toml
[ui]
prompt_new_tab_name = false
```

New tabs then arrive with herdr's generated number for the plugin to name. Accepting the prompt's prefilled number works too, since a bare integer reads as a placeholder, but it costs a keystroke per tab. Keep `prompt_new_workspace_name` if you use it: the plugin only prefixes workspace names, it never generates them.

## Configuration

Works with no config. To change a knob, copy the sample:

```sh
mkdir -p ~/.config/herdr-automatic-rename
cp "$(dirname "$(herdr plugin list --json | jq -r '.result.plugins[]|select(.plugin_id=="herdr-automatic-rename").source.managed_path')")"/herdr-automatic-rename-*/config.example.sh \
  ~/.config/herdr-automatic-rename/config.sh
```

Override the path with `HERDR_AUTOMATIC_RENAME_CONFIG`.

| Knob | Default | What it does |
| --- | --- | --- |
| `NAME_TABS` | `1` | Name each tab after its foreground program. `0` leaves tab names alone. |
| `AUTO_INDEX` | `1` | Add the `[N]` jump number (1-9) to workspaces and tabs, and to agents on herdr `< 0.7.5`. |
| `AUTO_INDEX_WORKSPACES`<br>`AUTO_INDEX_TABS`<br>`AUTO_INDEX_AGENTS` | `AUTO_INDEX` | Number one kind of row. Each defaults to `AUTO_INDEX` and overrides it, so `AUTO_INDEX` stays the single switch and these are the exceptions. |
| `SHOW_PROGRAM_ARGS` | `0` | `0` shows the program name (`git`), `1` its whole command line (`git log --oneline`). |
| `MAX_NAME_LEN` | `20` | Cut the finished label off after this many characters. |
| `AGENT_TITLES` | `1` | Name a coding-agent tab after the task in its terminal title (`Squash merge command`) rather than after the program (`claude`). |
| `MAX_TITLE_LEN` | `MAX_NAME_LEN` + 8 | Cut a title label off after this many characters, at a word boundary where one is close enough. Titles are sentences, so they get more room than a command name. |
| `TITLE_IGNORE` | `claude code`, `codex cli`, ... | Titles that name the agent instead of its work, matched against the whole title, ignoring ASCII case. |
| `SHELL_NAME` | `$SHELL` basename | Label shown at an idle prompt, such as `zsh`. |
| `HIDE_SHELL` | `0` | `1` gives a shell tab no name at all, so herdr's own tab number shows there instead. |
| `SHELLS` | `zsh bash sh fish dash ksh` | Programs counted as a shell prompt and shown by their own name. |
| `NAME_ONLY_PROGRAMS` | editors, git tools, agents | Programs always shown by bare name, never with args (`nvim`, `claude`). |
| `IGNORED_PROGRAMS` | `ls`, `cd`, `cat`, ... | Quick commands that should not rename the tab. It keeps showing the shell. |
| `WRAPPER_PROGRAMS` | `node`, `npx`, `python`, ... | Runtimes and package runners that front for the program you launched. In a pane herdr detected an agent in, the tab is named after that agent instead. |
| `PROGRAM_ALIASES` | none | Force a program to a custom label, e.g. `("lazygit=lg")`. |
| `SUBSTITUTE_SETS` | two rules | `sed -E` rewrites that tidy up the label, e.g. to shorten a path-heavy command line. |
| `ICONS_ENABLED` | `0` | `1` prepends a Nerd Font glyph for the program. Shell labels never get one, so the tab does not flicker between `zsh` and `<glyph> zsh`. |
| `ICON_STYLE` | `name_and_icon` | With icons on, show `name_and_icon`, `icon` only, or `name` only. |
| `ICON_FALLBACK` | `?` | Glyph for programs missing from the builtin map (~170 programs, from tmux-nerd-font-window-name's `defaults.yml`). `''` turns the fallback off. |
| `ICON_MAP` | none | Per-program icon overrides, `("prog=glyph")` pairs. Wins over the builtin map. |

`config.example.sh` documents each one with examples.

Setting one of the `AUTO_INDEX_*` knobs to `0` also strips the `[N]` already on those rows, at the next herdr event. Nothing records which prefixes the plugin wrote, so that cleanup cannot tell one of ours from a name you typed that opens with a bracketed number: `[1] incident` becomes `incident`. Naming the kind is how you ask for it, which is why a config carrying only `AUTO_INDEX=0` leaves workspace and agent labels as they are. Tabs are the exception under `NAME_TABS=1`, where that pass has always taken the prefix off on its way through. Only digits count, so `[wip] deploy` is never touched.

## Actions

- `reset`: re-adopt a hand-renamed tab.
- `clear`: strip every `[N]`, restore base names, revert agents to detection.

Both report what they did as a herdr notification, since a keybinding leaves nothing else to confirm them by. A `reset` claims success only when that tab had opted out and now carries an automatic name again; one that found no such tab, one that ran with `NAME_TABS=0`, and one whose rename herdr refused each say so instead. If another naming pass holds the lock, both actions wait briefly and then ask you to try again rather than dropping the request. A herdr with no `notification show` declines the notification, and the action still runs.

Run from the CLI, or bind a key:

```sh
herdr plugin action invoke herdr-automatic-rename.reset
```

```toml
# ~/.config/herdr/config.toml (example binding)
[[keys.command]]
key = "alt+shift+r"
type = "plugin_action"
command = "herdr-automatic-rename.reset"
```

## Uninstall

Strip labels first (else `clear`'s renames re-fire the hooks), then remove:

```sh
bash "$(herdr plugin list --json \
  | jq -r '.result.plugins[]|select(.plugin_id=="herdr-automatic-rename").source.managed_path')/automatic-rename.sh" --clear
herdr plugin uninstall herdr-automatic-rename
```

## Notes

- **Manual renames win.** Rename a tab yourself and naming leaves it alone. Numbering still applies. `clear` the label or `reset` to hand it back.
- **Agent numbering needs herdr `< 0.7.5`.** That release added a name rule (`^[a-z][a-z0-9_-]{0,31}$`) that rejects a bracketed number outright, so newer herdr leaves agent rows alone and strips any prefix an older setup left behind. Where it does apply it also needs grouped (`spaces`) sort, the mode whose CLI order matches the panel `focus_agent` follows. In `priority` sort that order is API-invisible, so numbers are stripped there too.
- **Tab names go quiet on Linux runtimes with no foreground process group.** Naming reads the pane's foreground process, and some container and sandbox setups leave herdr unable to see one, which stops tab naming entirely (numbering is unaffected). herdr `>= 0.8.0` has an opt-in fallback: set `HERDR_PROCESS_DETECTION=child-groups` in its environment. It is best-effort by herdr's own account, since in that mode a background job can look like the foreground one. The plugin covers one case of that without guessing: where herdr names no foreground group but reports exactly one process for the pane, there is nothing to choose between, so the tab is named after it. Two or more processes with no named group would be a guess, and the tab keeps its own label instead.
- **Collapsing a space renumbers.** `alt+N` counts the sidebar's visible rows, so a collapsed space hides its worktree workspaces from numbering and every row below it moves up. The hidden ones go bare until you expand. Focusing one of those worktrees while the space stays collapsed renders that row again, which shifts the rows below it back down. herdr publishes collapse only in `session.json`, on a 5-second debounce and with no event to hook, so the first jump right after a collapse can still use the old numbers.
- **Stops at 9.** No binding reaches a 10th item, so `10+` stay bare.

## Development

Engine: `automatic-rename.sh` (bash 3.2, needs only `jq` and the herdr CLI). Pure naming: `naming.sh`, with icons in `icons.sh`. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) covers the non-obvious decisions.

Tests need only bash and jq:

```sh
./tests/run.sh            # all
./tests/run.sh reconcile  # one file
```

They cover the naming rules, the `[N]` prefix helpers, the state machine, the shell hooks, and a full reconcile against a fake `herdr`.

## License

MIT. See [LICENSE](LICENSE).

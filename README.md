# herdr-automatic-rename

[![tests](https://github.com/qu8n/herdr-automatic-rename/actions/workflows/ci.yml/badge.svg)](https://github.com/qu8n/herdr-automatic-rename/actions/workflows/ci.yml)

## Features

**1. Automatic tab rename with the foreground process.** Inspired by [tmux](https://github.com/tmux/tmux)'s `automatic-rename`, each tab shows its foreground process (e.g., `nvim`, `claude`) or the shell at a bare prompt (e.g., `zsh`). Custom renames are respected.

**2. Automatic prefix spaces/tabs with the 1-9 keybind jump number**. Add an `[N]` prefix to each workspace and tab matching the `1-9` binding for that slot. Glance at the tabs or sidebar, see what runs where, and quickly jump by number. Agents get one too on herdr `< 0.7.5`, which is the last release whose agent names allow it.

Each feature can be toggled and work independently.

<img width="3216" height="2088" alt="readme-demo-screenshot" src="https://github.com/user-attachments/assets/43f620c0-d667-4fa9-b76c-dbafde41b7ec" />

## Before and after

herdr labels a new tab with a number, and leaves workspace and agent rows at their plain names. One four-tab workspace, before and after (stock config: `NAME_TABS=1`, `AUTO_INDEX=1`):

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

Workspaces get numbered, never renamed, so only the prefix is new:

| Sidebar row | herdr alone | with the plugin |
| --- | --- | --- |
| workspace | `dotfiles` | `[1] dotfiles` |
| agent | `claude` | `claude` (see below) |

Agents are the exception. herdr `0.7.5` restricted agent names to `^[a-z][a-z0-9_-]{0,31}$`, which no `[N] ` prefix can satisfy, so on herdr `>= 0.7.5` agent rows are left at their detected names and any `[N]` a previous version of this plugin managed to set is stripped back off. On herdr `< 0.7.5` agents still get `[1] claude`.

Turn one feature off and you keep the other half: `AUTO_INDEX=0` names without the prefix (`zsh`, `nvim`), and `NAME_TABS=0` leaves every base name as herdr or you left it and adds only the `[N]`. `SHOW_PROGRAM_ARGS=1` swaps a program's name for its whole command line, so a `npm run dev` tab reads `[2] npm run dev` rather than `[2] npm`.

Numbering also splits by item kind. `AUTO_INDEX_WORKSPACES`, `AUTO_INDEX_TABS` and `AUTO_INDEX_AGENTS` each default to whatever `AUTO_INDEX` is and override it when you set them, so `AUTO_INDEX` remains the single switch for all of it and these are the exceptions. Numbered tabs above plain workspace names is one line:

```sh
AUTO_INDEX_WORKSPACES=0
```

Setting one of those to `0` also strips the `[N]` already on those rows, at the next herdr event, so you do not have to run the `clear` action to tidy up after the change.

That cleanup runs only for a kind you name. Nothing here records which `[N]` prefixes the plugin wrote, so it cannot tell one of ours from a name you typed that opens with a bracketed number: `[1] incident` becomes `incident`. Naming the kind is how you ask for that. A config carrying only `AUTO_INDEX=0`, from before these settings existed, leaves workspace and agent labels exactly as they are. Tabs are the exception, and only under `NAME_TABS=1`: that pass runs for the naming, and has always stripped the prefix on its way through. Only digits count either way, so `[wip] deploy` is never touched.

If a row of `zsh` tabs tells you nothing, `HIDE_SHELL=1` names only the tabs actually running something and leaves the rest to herdr, which falls back to its own tab number:

```
HIDE_SHELL=0, AUTO_INDEX=0  │ lazygit     │ nvim     │ fish │ pi     │
HIDE_SHELL=1, AUTO_INDEX=0  │ lazygit     │ nvim     │ 3    │ pi     │
HIDE_SHELL=1, AUTO_INDEX=1  │ [1] lazygit │ [2] nvim │ [3]  │ [4] pi │
```

That covers a bare prompt, an explicit shell, and anything in `IGNORED_PROGRAMS`. With numbering on, the label keeps the jump number and nothing else, so you can still jump to the tab.

## Requirements

herdr `>= 0.7.1`, `jq`, and bash. Linux or macOS.

herdr `>= 0.7.4` is recommended. There a plugin rename repaints the tab bar immediately, so live renames appear the instant they happen; on older herdr the new name still lands but the tab bar only catches up on the next redraw (a focus change or resize). herdr `>= 0.7.2` also lets a full reconcile read its whole state in one `api snapshot` call — without it the plugin falls back to per-list queries automatically.

Two newer versions add smaller wins, both detected at runtime: on herdr `>= 0.7.5` a restored session is reconciled the moment herdr comes up rather than at the first event, and on `>= 0.8.0` reordering a worktree group renumbers immediately. Everything else works down to `0.7.1`.

## Install

```sh
herdr plugin install qu8n/herdr-automatic-rename --yes
```

Events work immediately.

### Shell hook (highly recommended)

Renames the instant a command starts. Without it, naming waits for the next focus or tab event. Source your shell's hook so that it self-locates the engine wherever herdr installed it.

**zsh** (`~/.zshrc`):

```zsh
for _f in ${HOME}/.config/herdr/plugins/github/herdr-automatic-rename-*/shell/hook.zsh(N); do
  source $_f; break
done
```

**bash** (`~/.bashrc`, after any prompt/history tool like starship or atuin):

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

No-op outside a herdr pane. On bash it cooperates with bash-preexec / atuin / ble.sh, else owns `DEBUG` without clobbering an existing trap.

A command word that is not an external program (a shell function, builtin, or typo) never renames the tab directly. The hook flags it, and the engine reads the pane's real foreground process a moment later: an instant function leaves the tab name alone, and a function that opens `nvim` names the tab `nvim`.

### Turn off herdr's new-tab name prompt

herdr asks each new tab for a name (`prompt_new_tab_name`, on by default). Under `NAME_TABS=1` that prompt has nothing left to do, and a name typed into it counts as a hand rename, which opts the tab out of naming until you `reset` it. Turn it off:

```toml
# ~/.config/herdr/config.toml
[ui]
prompt_new_tab_name = false
```

New tabs then arrive with herdr's generated number for the plugin to name. Accepting the prompt's prefilled number works as well, since a bare integer reads as a placeholder, but it costs a keystroke per tab. Keep `prompt_new_workspace_name` if you use it: the plugin only prefixes workspace names, it never generates them.

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
| `NAME_TABS` | `1` | Rename each tab to its foreground program. `0` leaves tab names alone. |
| `AUTO_INDEX` | `1` | Add the `[N]` jump-key number (1-9) in front of each workspace and tab (and agent on herdr `< 0.7.5`). |
| `AUTO_INDEX_WORKSPACES` | `AUTO_INDEX` | Number workspaces. Set it alone to keep numbered tabs while workspace names stay plain. |
| `AUTO_INDEX_TABS` | `AUTO_INDEX` | Number tabs. |
| `AUTO_INDEX_AGENTS` | `AUTO_INDEX` | Number agents (herdr `< 0.7.5` only, and only under the grouped panel sort). |
| `SHOW_PROGRAM_ARGS` | `0` | `0` shows just the program name (`git`), `1` shows its full command line (`git log --oneline`). |
| `MAX_NAME_LEN` | `20` | Cut the finished label off after this many characters. |
| `SHELL_NAME` | `$SHELL` basename | Label shown at an idle prompt when no program is running (e.g. `zsh`). |
| `HIDE_SHELL` | `0` | `1` gives a shell tab no name at all, so herdr's own tab number shows there instead of `zsh`. Covers the login shell (`SHELL_NAME`), not just the fixed `SHELLS` list. |
| `SHELLS` | `zsh bash sh fish dash ksh` | Programs counted as "a shell prompt" and shown by their own name. |
| `NAME_ONLY_PROGRAMS` | editors, git tools, agents | Programs always shown by bare name, never with args (`nvim`, `claude`). |
| `IGNORED_PROGRAMS` | `ls`, `cd`, `cat`, ... | Quick commands that should not rename the tab. It keeps showing the shell instead. |
| `WRAPPER_PROGRAMS` | `node`, `npx`, `bun`, `python`, ... | Language runtimes and package runners that front for the program you launched. In a pane herdr has detected an agent in, the tab is named after that agent instead of the runtime. |
| `PROGRAM_ALIASES` | none | Force a specific program to a custom label, e.g. `("lazygit=lg")`. |
| `SUBSTITUTE_SETS` | two rules | `sed -E` rewrites that tidy up the label, e.g. to shorten a path-heavy command line. |
| `ICONS_ENABLED` | `0` | `1` prepends a Nerd Font glyph for the program (needs a Nerd Font installed). Shell labels never get one, so the tab doesn't flicker between `zsh` and `<glyph> zsh`. |
| `ICON_STYLE` | `name_and_icon` | When icons are on, show `name_and_icon`, `icon` only, or `name` only. |
| `ICON_FALLBACK` | `?` | Glyph for programs missing from the builtin map (~170 programs, from tmux-nerd-font-window-name's `defaults.yml`). `''` turns the fallback off; under `ICON_STYLE=icon` it is treated as no glyph (a bare `?` label says nothing). |
| `ICON_MAP` | none | Per-program icon overrides, `("prog=glyph")` pairs; wins over the builtin map. |

`config.example.sh` documents each with examples.

## Actions

- `reset`: re-adopt a hand-renamed tab.
- `clear`: strip every `[N]`, restore base names, revert agents to detection.

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
- **Agent numbering needs herdr `< 0.7.5`.** That release added a name rule (`^[a-z][a-z0-9_-]{0,31}$`) that rejects a bracketed number outright, so newer herdr leaves agent rows alone and strips any prefix an older setup left behind. Where it does apply, it also needs grouped (`spaces`) sort, the mode whose CLI order matches the panel `focus_agent` follows. In `priority` sort that order is API-invisible, so numbers are stripped there too.
- **Tab names go quiet on Linux runtimes with no foreground process group.** Naming reads the pane's foreground process, and some container and sandbox setups leave herdr unable to see one, which makes tab naming do nothing at all (numbering is unaffected). herdr `>= 0.8.0` has an opt-in fallback: set `HERDR_PROCESS_DETECTION=child-groups` in its environment. It is best-effort by herdr's own account, since in that mode a background job can look like the foreground one, so a tab may occasionally follow the wrong process.
- **Collapsing a space renumbers.** `alt+N` counts the sidebar's visible rows, so a collapsed space hides its worktree workspaces from numbering and every row below it moves up. The hidden ones go bare until you expand. Focusing one of those worktrees while the space stays collapsed renders that row again, which shifts the rows below it back down. herdr publishes collapse only in `session.json`, on a 5-second debounce and with no event to hook, so the first jump right after a collapse can still use the old numbers.
- **Stops at 9.** No binding reaches a 10th item, so `10+` stay bare.

## Development

Engine: `automatic-rename.sh` (bash 3.2, needs only `jq` and the herdr CLI). Pure naming: `naming.sh` (icons: `icons.sh`). Tests need only bash and jq:

```sh
./tests/run.sh            # all
./tests/run.sh reconcile  # one file
```

They cover the naming rules, the `[N]` prefix helpers, the state machine, the shell hooks, and a full reconcile against a fake `herdr`.

## License

MIT. See [LICENSE](LICENSE).

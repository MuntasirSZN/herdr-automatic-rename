# herdr-automatic-rename

[![tests](https://github.com/qu8n/herdr-automatic-rename/actions/workflows/ci.yml/badge.svg)](https://github.com/qu8n/herdr-automatic-rename/actions/workflows/ci.yml)

## Features

**1. Automatic tab rename with the foreground process.** Inspired by [tmux](https://github.com/tmux/tmux)'s `automatic-rename`, each tab shows its foreground process (e.g., `nvim`, `claude`) or the shell at a bare prompt (e.g., `zsh`). Custom renames are respected.

**2. Automatic prefix spaces/tabs/agents with the 1-9 keybind jump number**. Add an `[N]` prefix to each workspace, tab, and agent matching the `1-9` binding for that slot. Glance at the tabs or sidebar, see what runs where, and quickly jump by number.

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

Workspaces and agents get numbered, never renamed, so only the prefix is new:

| Sidebar row | herdr alone | with the plugin |
| --- | --- | --- |
| workspace | `dotfiles` | `[1] dotfiles` |
| agent | `claude` | `[1] claude` |

Turn one feature off and you keep the other half: `AUTO_INDEX=0` names without the prefix (`zsh`, `nvim`), and `NAME_TABS=0` leaves every base name as herdr or you left it and adds only the `[N]`. `SHOW_PROGRAM_ARGS=1` swaps a program's name for its whole command line, so a `npm run dev` tab reads `[2] npm run dev` rather than `[2] npm`.

## Requirements

herdr `>= 0.7.1`, `jq`, and bash. Linux or macOS.

herdr `>= 0.7.4` is recommended. There a plugin rename repaints the tab bar immediately, so live renames appear the instant they happen; on older herdr the new name still lands but the tab bar only catches up on the next redraw (a focus change or resize). herdr `>= 0.7.2` also lets a full reconcile read its whole state in one `api snapshot` call — without it the plugin falls back to per-list queries automatically.

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
| `AUTO_INDEX` | `1` | Add the `[N]` jump-key number (1-9) in front of each workspace, tab, and agent. |
| `SHOW_PROGRAM_ARGS` | `0` | `0` shows just the program name (`git`), `1` shows its full command line (`git log --oneline`). |
| `MAX_NAME_LEN` | `20` | Cut the finished label off after this many characters. |
| `SHELL_NAME` | `$SHELL` basename | Label shown at an idle prompt when no program is running (e.g. `zsh`). |
| `SHELLS` | `zsh bash sh fish dash ksh` | Programs counted as "a shell prompt" and shown by their own name. |
| `NAME_ONLY_PROGRAMS` | editors, git tools, agents | Programs always shown by bare name, never with args (`nvim`, `claude`). |
| `IGNORED_PROGRAMS` | `ls`, `cd`, `cat`, ... | Quick commands that should not rename the tab. It keeps showing the shell instead. |
| `PROGRAM_ALIASES` | none | Force a specific program to a custom label, e.g. `("lazygit=lg")`. |
| `SUBSTITUTE_SETS` | two rules | `sed -E` rewrites that tidy up the label, e.g. to shorten a path-heavy command line. |
| `ICONS_ENABLED` | `0` | `1` prepends a Nerd Font glyph for the program (needs a Nerd Font installed). |
| `ICON_STYLE` | `name_and_icon` | When icons are on, show `name_and_icon`, `icon` only, or `name` only. |
| `ICON_FALLBACK` | `?` | Glyph for programs missing from the builtin map (~170 programs, from tmux-nerd-font-window-name's `defaults.yml`). `''` turns the fallback off. |
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
- **Agents number only in grouped (`spaces`) sort**, where the CLI order matches the panel `focus_agent` follows. In `priority` sort that order is API-invisible, so numbers are stripped. Switch back and they return.
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

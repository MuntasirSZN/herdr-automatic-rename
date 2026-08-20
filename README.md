# herdr-automatic-rename

[![tests](https://github.com/qu8n/herdr-automatic-rename/actions/workflows/ci.yml/badge.svg)](https://github.com/qu8n/herdr-automatic-rename/actions/workflows/ci.yml)

This plugin makes is easier to navigate across your herdr surfaces:

- Like [tmux](https://github.com/tmux/tmux)'s `automatic-rename`, a tab shows its foreground process (`nvim`, `claude`) or the shell (`zsh`) instead of `1`, `2`, `3`. A tab running a coding agent shows the task instead, with names like `Squash merge command`.
- Workspaces and tabs get an `[N]` prefix, matching the `1-9` binding for that slot, so you can glance at the sidebar or the tab bar and jump straight there.

Each can be toggled on/off in the config file:

- Set `NAME_TABS=0` to turn off the naming.
- Set `AUTO_INDEX=0` to turn off the numbering.

<img width="3216" height="2088" alt="readme-demo-screenshot" src="https://github.com/user-attachments/assets/43f620c0-d667-4fa9-b76c-dbafde41b7ec" />

## Requirements

herdr `>= 0.7.1`, `jq`, and bash, on Linux or macOS.

Use herdr `>= 0.7.4` if you can. Below that a new name still lands, but the tab bar shows it only on the next redraw, such as a focus change.

## Install

### 1. Install the plugin

```sh
herdr plugin install qu8n/herdr-automatic-rename --yes
```

The plugin will trigger at the next herdr event.

### 2. Add shell hook

The hook renames a tab the instant a command starts. Without it, a new name waits for the next focus or tab event.

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

### 3. Turn off herdr's new-tab name prompt

herdr asks each new tab for a name (`prompt_new_tab_name`, on by default). A name typed into that prompt counts as a hand rename, which opts the tab out until you `reset` it, so turn the prompt off:

```toml
# ~/.config/herdr/config.toml
[ui]
prompt_new_tab_name = false
```

Keep `prompt_new_workspace_name` if you use it. The plugin only prefixes workspace names, it never generates them.

## Configuration

Every setting has a working default, so start with no config at all. To change one, copy the sample:

```sh
mkdir -p ~/.config/herdr-automatic-rename
cp "$(dirname "$(herdr plugin list --json | jq -r '.result.plugins[]|select(.plugin_id=="herdr-automatic-rename").source.managed_path')")"/herdr-automatic-rename-*/config.example.sh \
  ~/.config/herdr-automatic-rename/config.sh
```

Override that path with `HERDR_AUTOMATIC_RENAME_CONFIG`. [config.example.sh](config.example.sh) documents every knob with examples. It covers numbering per row kind, agent titles, label length, the program lists (shells, ignored commands, custom labels), and Nerd Font icons.

## Window title

herdr `>= 0.8.2` writes the outer terminal's window title, `{hostname}: {workspace}` by default, so a workspace's `[N]` prefix already shows up there. Add `{tab}` to get the tab name too, the agent's task included:

```toml
# ~/.config/herdr/config.toml
[ui]
window_title = "{hostname}: {workspace} · {tab}"
```

herdr's `{terminal_title}` token holds the focused pane's raw title instead. `{tab}` is that same title after the plugin has truncated it and swapped the useless ones back to the program name.

## Actions

- `reset` re-adopts a tab you renamed by hand.
- `clear` strips every `[N]`, restores base names, and reverts agents to detection.

Both report what they did as a herdr notification. Run one from the CLI, or bind a key:

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

Strip the labels first, else `clear`'s renames re-fire the hooks. Then remove the plugin:

```sh
bash "$(herdr plugin list --json \
  | jq -r '.result.plugins[]|select(.plugin_id=="herdr-automatic-rename").source.managed_path')/automatic-rename.sh" --clear
herdr plugin uninstall herdr-automatic-rename
```

## Good to know

- **Manual renames win.** Rename a tab yourself and naming leaves it alone, though numbering still applies. Run `reset` to hand it back.
- **Search finds the generated names.** herdr `>= 0.8.2` searches renamed single-tab labels, so the Session Navigator matches the name this plugin wrote.
- **Numbering stops at 9.** No binding reaches a 10th row, so the rest stay bare.
- **Naming needs a foreground process.** Some Linux container and sandbox setups leave herdr unable to see one, which stops tab naming (numbering is unaffected). On herdr `>= 0.8.0`, set `HERDR_PROCESS_DETECTION=child-groups` in its environment.

## Development

The engine is `automatic-rename.sh`, with the naming rules in `naming.sh` and icons in `icons.sh`. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) covers the non-obvious decisions, and [CONTRIBUTING.md](CONTRIBUTING.md) covers the tests.

## License

MIT. See [LICENSE](LICENSE).

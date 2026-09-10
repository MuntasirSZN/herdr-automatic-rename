# herdr-automatic-rename

[![tests](https://github.com/qu8n/herdr-automatic-rename/actions/workflows/ci.yml/badge.svg)](https://github.com/qu8n/herdr-automatic-rename/actions/workflows/ci.yml) [![release](https://img.shields.io/github/v/release/qu8n/herdr-automatic-rename)](https://github.com/qu8n/herdr-automatic-rename/releases) [![herdr](https://img.shields.io/badge/dynamic/toml?url=https%3A%2F%2Fraw.githubusercontent.com%2Fqu8n%2Fherdr-automatic-rename%2Fmain%2Fherdr-plugin.toml&query=%24.min_herdr_version&prefix=%3E%3D%20&label=herdr)](https://github.com/qu8n/herdr) [![license](https://img.shields.io/github/license/qu8n/herdr-automatic-rename)](LICENSE)

<img width="900" height="390" alt="Tab bars before and after the plugin names tabs" src="docs/readme-demo.jpg" />

By default, herdr names your tabs `1`, `2`, `3`, etc. This plugin automatically renames your tabs so you can immediately know what each tab contains. It also adds a `[N]` number prefix for keyboard-first users to quickly navigate across tabs.

Some examples of tabs renamed by this plugin:

```text
TAB NAME                                HOW TO READ IT
-------------------------------------   --------------------------------
[1] zsh                                 a plain shell
[2] api › feat/oauth › nvim             directory › branch › program
[3] prod-01 › ssh                       a machine you reached over ssh
[4] PROJ-482 › Fix the revenue query    branch › what an agent is doing
```

Tab names are highly configurable. See the Configuration section below for more info.

## Quick start

### Requirements

- herdr `>= 0.7.1`
- `jq`
- bash
- Linux or macOS

### Install or update

Simply run this automation script:

```sh
curl -fsSL https://raw.githubusercontent.com/qu8n/herdr-automatic-rename/main/install.sh | bash
```

This script installs the latest version of the plugin and adds our shell hook, which makes the renaming mechanism happen immediately when a command starts. It picks the hook for your login shell out of zsh, bash, and fish, and writes it to that shell's startup file.

<details>
<summary>Alternative, manual setup instructions</summary>

#### Install the plugin

```sh
herdr plugin install qu8n/herdr-automatic-rename --yes
```

#### Add the hook for your shell

zsh (`~/.zshrc`):

```zsh
for _f in ${HOME}/.config/herdr/plugins/github/herdr-automatic-rename-*/shell/hook.zsh(N); do
  source $_f; break
done
```

bash (`~/.bashrc`):

```bash
for _f in "$HOME"/.config/herdr/plugins/github/herdr-automatic-rename-*/shell/hook.bash; do
  [ -r "$_f" ] && { source "$_f"; break; }
done
```

fish (`~/.config/fish/config.fish`):

```fish
for _f in $HOME/.config/herdr/plugins/github/herdr-automatic-rename-*/shell/hook.fish
    test -r "$_f"; and source "$_f"; and break
end
```

</details>

### Recommended herdr configs

**1. Turn off herdr's new-tab name prompt.**

When you create a new tab, herdr prompts you to give it a name. For the best UX, you should disable this feature to let this plugin do the naming for you. (When you manually set a name, this plugin respects that and doesn't automatically rename it unless you invoke the `reset` action on that tab.)

```toml
# ~/.config/herdr/config.toml
[ui]
prompt_new_tab_name = false
```

**2. Install the herdr integrations for your coding agents.**

See [herdr's integrations docs](https://herdr.dev/docs/integrations/) for installation details. This lets herdr then detect an agent natively instead of by reading the screen, which makes for agent tab naming smoother.

## Configuration (optional)

To customize a config, write it to `~/.config/herdr-automatic-rename/config.sh` (or point `HERDR_AUTOMATIC_RENAME_CONFIG` elsewhere).

| Setting | Default | What it does |
| --- | --- | --- |
| `NAME_TABS` | `1` | Automatic tab naming (the core feature of this plugin). |
| `AUTO_INDEX` | `1` | Prefix with their `1-9` prefix key. |
| `TAB_CONTEXT` | `1` | Show the `<where>` half of a tab name: directory, branch, or ssh host. |
| `SHOW_BRANCH` | `1` | Add the checked-out branch. Trunk branches and branches that repeat what is on screen are left out. |
| `AGENT_TITLES` | `1` | Name an agent tab after the task it reports, not after the agent name (e.g. `claude`). |
| `TITLE_STYLE` | `task` | `name_and_task` keeps the agent in front, like `cc:auth-flow`. Worth it when you run several agents. |
| `TITLE_CONDENSE` | `0` | Keep a long title's keywords instead of cutting off its tail. |
| `HIDE_SHELL` | `0` | `1` shows nothing for a plain prompt, so herdr's own number shows through. |
| `ICONS_ENABLED` | `0` | Show Nerd Font glyph in front of the name. |
| `PROGRAM_ALIASES` | none | Rename programs on the tab: `"lazygit=lg"`. |
| `WORKSPACE_SUBSTITUTE_SETS` | none | Rewrite the workspace label herdr derives from the directory: `'s\|^worktree-\|wt-\|'` shows `worktree-feature` as `wt-feature`. Display only, so the directory and the Git worktree keep their names. |
| `MAX_NAME_LEN` `MAX_TITLE_LEN` `MAX_CONTEXT_LEN` `MAX_BRANCH_LEN` | `20` `MAX_NAME_LEN + 8` `12` `12` | Character budget per part of the tab name. |

See [config.example.sh](config.example.sh) for the full configuration details.

## Actions

- `reset` re-adopts a tab you renamed by hand.
- `clear` strips every `[N]` number prefix, restores base names, and reverts agents to detection.
- `doctor` prints why the current tab has the name it has for troubleshooting.

Run one from the CLI, or bind it in `config.toml` as a `plugin_action`, like this:

```sh
herdr plugin action invoke herdr-automatic-rename.reset
```

## Uninstall

```sh
bash "$(herdr plugin list --json \
  | jq -r '.result.plugins[]|select(.plugin_id=="herdr-automatic-rename").source.managed_path')/automatic-rename.sh" --clear
herdr plugin uninstall herdr-automatic-rename
```

Then delete `~/.local/state/herdr-automatic-rename/`.

## Caveats

- **Manual renames win.** When you rename a tab yourself, the plugin respects that and doesn't touch it, though the prefix numbering still applies. `reset` hands it back to the plugin.
- **Numbering stops at 9.** No binding reaches a 10th row, so the rest keep plain names.
- **An agent answers to either of its names.** herdr knows `cursor-agent` and `kiro-cli` as `cursor` and `kiro`, so one `PROGRAM_ALIASES` entry covers both spellings. Muse is the same, including its `muse-bin-<version>` build.
- **Transcripts are read for untitled Claude Code tabs.** With the Claude integration installed, a tab whose agent has no title is named from the session's transcript on disk, so the plugin reads what you typed to the agent. `AGENT_TRANSCRIPT=0` in `config.sh` turns that off.
- **Naming needs a foreground process.** Some Linux container and sandbox setups hide one from herdr, so naming stops while numbering keeps working. On herdr `>= 0.8.0`, set `HERDR_PROCESS_DETECTION=child-groups` in its environment.
- **On herdr below `0.7.4`** a new name lands but only shows at the next redraw, such as a focus change.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## License

MIT.

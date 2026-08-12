# herdr-automatic-rename configuration.
#
# Copy to ~/.config/herdr-automatic-rename/config.sh and uncomment what you want to
# change (or point $HERDR_AUTOMATIC_RENAME_CONFIG somewhere else). This file is sourced
# by automatic-rename.sh BEFORE naming.sh, so anything set here wins over the defaults.
# Every setting has a working default, so an empty config is fine.

# ---- feature toggles (both default on) ----

# Auto-name each tab after its foreground program (the shell name at a bare
# prompt). Set to 0 to leave tab names alone.
# NAME_TABS=1

# Prefix workspaces and tabs with their 1-9 jump-key number, e.g. "[2] api". Set
# to 0 to name without numbering. Agents are included only on herdr < 0.7.5:
# newer herdr rejects a bracketed agent name, so those rows keep their detected
# names (and lose any prefix an older setup left on them).
# AUTO_INDEX=1

# Numbering, per item kind. Each defaults to AUTO_INDEX and overrides it when
# set, so AUTO_INDEX stays the one knob for "number everything" or "number
# nothing" and these carve out the exceptions. Numbered tabs with plain
# workspace names, for instance, is the first line on its own:
# AUTO_INDEX_WORKSPACES=0
# AUTO_INDEX_TABS=1
# AUTO_INDEX_AGENTS=1
#
# Setting one of these to 0 also removes the prefixes already on those rows, on
# the next herdr event -- no need to run the "clear" action.
#
# That cleanup cannot tell one "[N] " apart from another. Nothing records which
# prefixes this plugin wrote, so a name you typed yourself that starts with a
# bracketed number, say "[1] incident", loses the bracket too. Naming the kind
# here is how you ask for the cleanup and accept that. A config with only
# AUTO_INDEX=0 in it never triggers it and keeps every label untouched.
# Anything else in brackets ("[wip] foo") is left alone, digits are the only
# trigger.

# ---- naming knobs (only used when NAME_TABS=1) ----

# 1 = a regular program shows its full command line ("psql -h db"); 0 = just its
# name ("psql"). Default 0.
# SHOW_PROGRAM_ARGS=0

# Truncate the final label to this many characters (counted by codepoint).
# MAX_NAME_LEN=20

# Name shown at a bare prompt. Defaults to your $SHELL's basename.
# SHELL_NAME=zsh

# 1 = don't name a shell tab at all: a bare prompt, an explicit shell, an
# IGNORED_PROGRAMS command, and the login shell itself (SHELL_NAME, which may be
# outside the SHELLS list) all leave the label empty, and herdr shows its own
# tab number there instead of "zsh". With AUTO_INDEX=1 the label keeps the jump
# number alone ("[3]"). Programs are named as usual either way.
# HIDE_SHELL=0

# Programs that count as "a shell prompt" and are shown by their own name.
# Assigning the array replaces the default; SHELLS=() disables the category.
# SHELLS=(zsh bash sh fish dash ksh)

# Programs shown by name only, without command-line args. Coding agents live
# here so an agent tab reads "claude" instead of its full invocation.
# NAME_ONLY_PROGRAMS=(nvim vim vi view gvim git lazygit gitui lazydocker claude codex aider)

# Quick commands that should not take over the tab name: while one runs, the tab
# keeps showing the shell so it does not flicker.
# IGNORED_PROGRAMS=(ls eza ll la cd z zoxide cat bat less more echo pwd clear which man head tail wc cp mv rm mkdir touch fzf sudo doas)

# Rename specific programs on the tab. "<program>=<label>" pairs; wins over every
# rule except the bare-prompt shell name.
# PROGRAM_ALIASES=(
#   "lazygit=lg"
#   "clx=hn"
# )

# Ordered `sed -E` rewrites applied to the final label.
# SUBSTITUTE_SETS=(
#   's|.*ipython([32])|ipython\1|'
#   's|.*poetry shell.*|poetry|'
# )

# Prepend a Nerd Font glyph (needs a Nerd Font). ICON_STYLE is one of
# name_and_icon (default), name, or icon.
# ICONS_ENABLED=0
# ICON_STYLE=name_and_icon

# Glyph shown when a program is missing from the builtin map (which comes from
# tmux-nerd-font-window-name's defaults.yml, ~170 programs). An empty string
# turns the fallback off, so unknown programs get no icon. Under ICON_STYLE=icon
# the fallback is treated as "no glyph": a bare "?" says nothing about the
# program, so the plain name is kept instead. Shell labels never get an icon
# either way (SHELLS, the login shell, and IGNORED_PROGRAMS commands): the tab
# is showing the shell, not the program.
# ICON_FALLBACK='?'

# Per-program icon overrides, "<program>=<glyph>" pairs; wins over the builtin
# map and the fallback. Glyphs are literal Nerd Font characters.
# ICON_MAP=(
#   "claude=󰚩"
#   "lazygit=󰊢"
# )

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
# AUTO_INDEX=0 in it never triggers it, so workspace and agent labels stay as
# they are. Tabs are the exception, and only under NAME_TABS=1: that pass runs
# for the naming, and has always taken the prefix off on its way through.
# Anything else in brackets ("[wip] foo") is left alone, digits are the only
# trigger.

# ---- naming knobs (only used when NAME_TABS=1) ----

# 1 = put the CONTEXT in front of the program: the directory the pane sits in,
# the branch it has checked out, the machine it reached over ssh, joined with
# CONTEXT_SEP -- "api › MC-13675 › nvim". A tab says what is running; without
# this half, five agent tabs across three checkouts read alike. 0 names by the
# program alone.
#
# The directory is refused when it says nothing a tab bar has room for: your home
# directory, the filesystem root, and the name of the workspace the tab is in
# (herdr shows that above the tabs already, so repeating it there spends half the
# width on what is on screen anyway).
# TAB_CONTEXT=1
#
# A pane running ssh is named after the machine it reached instead ("prod-01 ›
# ssh"): its directory is the local one it was launched from, and the branch
# checked out there would read as the remote machine's. The user is dropped,
# because root@prod-01 and deploy@prod-01 are the same machine.

# 1 = qualify the context with the branch the pane's repository has checked out:
# "api › MC-13675 › nvim". It says which slice of a project a tab is on, where
# the directory alone says only which project.
#
# The branch is read from the files under .git and never by running git, so it
# costs no process. Three rules keep it quiet: the repository's own default
# branch is left out (every tab would carry it alike, and which branch that is
# comes from the repository rather than a list of names), a branch that fits is
# shown whole, and one that does not is reduced -- to its issue key where it has
# one ("bugfix-asa-cpanel-uapi-mc-13675" -> "MC-13675"), else to the part after
# the last "/", cut at a whole word.
# SHOW_BRANCH=1

# Longest branch a label may carry, in characters. 0 leaves branches out, the
# same as SHOW_BRANCH=0. An issue key is shown whole even when it exceeds this:
# half a key identifies nothing.
# MAX_BRANCH_LEN=12

# Truncate the directory part to this many characters. It is a project name, not
# a sentence, and the program beside it still needs the room MAX_NAME_LEN gives
# it, so it has a budget of its own rather than eating that one.
# MAX_CONTEXT_LEN=12

# What joins the parts of a label. Written as a literal character; the default is
# U+203A, a single right-pointing angle quote.
# CONTEXT_SEP=' › '

# 1 = a regular program shows its full command line ("psql -h db"); 0 = just its
# name ("psql"). Default 0.
# SHOW_PROGRAM_ARGS=0

# Truncate the program name to this many characters (counted by codepoint). Each
# part of a label has a budget of its own -- MAX_CONTEXT_LEN for the directory,
# MAX_TITLE_LEN for an agent's task -- so the whole is bounded by the sum rather
# than by a total you would have to keep in step with the parts.
# MAX_NAME_LEN=20

# 1 = name a tab running a coding agent after the task the agent reports in its
# terminal title ("Squash merge command") instead of after the program
# ("claude"), which is what tells five claude tabs apart. herdr publishes the
# title on the pane, so the label costs no extra call. A title that names the
# agent rather than the work, one that is just the pane's directory, and a bare
# number are refused, and the tab falls back to the program name (aliases
# included). 0 names every agent tab after its program.
# AGENT_TITLES=1

# 1 = when a coding agent has NOT titled its terminal, read what its own session
# says it is about. Claude Code derives that title from what you typed, so a
# session you opened with a slash command and never typed a prompt into is never
# given one, and its tab reads "claude" for as long as it runs. Only Claude Code
# is read; any other agent is named from its terminal title exactly as before.
#
# What it reads is the title Claude Code generated for the session, or failing
# that your first prompt -- which is what Claude Code's own session list shows
# for an untitled session. It reads that out of the transcript file on disk, so
# set this to 0 if you would rather nothing read it. herdr has to have told the
# plugin which session the pane holds, which is what `herdr integration install
# claude` sets up; without it there is nothing to read and this does nothing.
# AGENT_TRANSCRIPT=1

# Truncate a title to this many characters, at a word boundary when that leaves
# most of the budget. A title is a sentence rather than a command name, so it
# needs more room than MAX_NAME_LEN gives -- and with numbering on the "[N] "
# prefix eats four more. Defaults to MAX_NAME_LEN plus 8, so narrowing that for a
# narrow tab bar narrows titles with it.
# MAX_TITLE_LEN=28

# Titles that name the agent instead of the work it is doing, matched against the
# whole title, ignoring the case of ASCII letters. An agent sets one of these before
# it has a task (at startup, or once a session is cleared), and "Claude Code"
# says less than "claude" does. The agent's own kind, that kind followed by
# "code", the directory the pane sits in, and a bare number are refused without
# being listed. Assigning the array replaces the default; TITLE_IGNORE=() leaves
# only those built-in refusals.
# TITLE_IGNORE=("claude code" "codex cli" "gemini cli" "opencode" "amp code" "cursor agent" "new session" "untitled")

# Agents that stamp their own brand on the FRONT of every terminal title, as
# "<herdr agent kind>=<brand>" pairs. Most agents put their status glyph first and
# the plugin takes it off; oh-my-pi puts the brand first and the glyph second
# ("π ⠋ Fix the parser" while it works, "π > ..." at your turn, "π ! ..." when it
# wants you), so without the brand named here the glyph reached the tab and the
# label changed on every status change. The brand is removed only at the very
# front and only when a non-alphanumeric follows it, so a title that merely starts
# with the same letter keeps it, and the case of ASCII letters is ignored.
# Assigning the array replaces the default.
# TITLE_BRANDS=("pi=π" "omp=π")

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

# Language runtimes and package runners that front for the program you actually
# launched. An agent installed from npm is usually a bin shim pointing at a JS
# entrypoint, so the foreground process is `node` and the tab would be named
# after the runtime; pip and pipx console scripts do the same through `python`.
# When one of these is the foreground program in a pane herdr has detected an
# agent in, the tab is named after that agent instead ("codex", not "node").
# Both conditions are needed, so a plain `node server.js` tab keeps its name.
# Add your interpreter here if it resolves to a versioned name (python3.12).
# WRAPPER_PROGRAMS=(node bun deno npx bunx npm pnpm yarn python python3 uv uvx pipx ruby)

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

#!/usr/bin/env bash
# Unit tests for naming.sh -- the pure, herdr-free name computation.
# String in / string out, so every rule is testable without a live herdr.

here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

# Pin the shell name so bare-prompt cases are deterministic regardless of $SHELL.
SHELL_NAME=zsh
. "$here/../naming.sh"

# ---- bare prompt / shells ----
check "bare prompt -> shell name" "zsh" "$(ar_format '' '')"
check "explicit shell shows own name" "bash" "$(ar_format 'bash' 'bash')"
check "fish shell name" "fish" "$(ar_format 'fish' '')"

# ---- name-only programs (editors, agents, git) ----
check "nvim is name-only" "nvim" "$(ar_format 'nvim' 'nvim README.md')"
check "claude is name-only" "claude" "$(ar_format 'claude' 'claude --dangerously-skip-permissions')"
check "git is name-only" "git" "$(ar_format 'git' 'git status')"

# ---- ignored programs keep showing the shell ----
check "ls is ignored -> shell" "zsh" "$(ar_format 'ls' 'ls -la')"
check "cd is ignored -> shell" "zsh" "$(ar_format 'cd' 'cd ..')"

# ---- regular programs show their command line (SHOW_PROGRAM_ARGS default on) ----
SHOW_PROGRAM_ARGS=1
check "regular program shows cmdline" "htop -d 5" "$(ar_format 'htop' 'htop -d 5')"
check "regular program, args off -> name only" "psql" "$(SHOW_PROGRAM_ARGS=0 ar_format 'psql' 'psql -h db')"

# ---- program aliases win over category ----
PROGRAM_ALIASES=("clx=hn" "lazygit=lg")
check "alias clx->hn" "hn" "$(ar_format 'clx' 'clx --nerdfonts')"
check "alias lazygit->lg" "lg" "$(ar_format 'lazygit' 'lazygit')"
PROGRAM_ALIASES=()

# ---- substitutions ----
check "poetry shell -> poetry" "poetry" "$(ar_format 'poetry' 'poetry shell')"
check "ipython3 collapse" "ipython3" "$(ar_format 'ipython3' '/usr/bin/ipython3')"

# ---- truncation (MAX_NAME_LEN), counted by codepoint ----
check "truncates to MAX_NAME_LEN" "12345678901234567890" \
  "$(MAX_NAME_LEN=20 ar_format 'x' '123456789012345678901234567890')"
# A multibyte string must be cut on a codepoint boundary, never mid-byte.
check "multibyte truncation is clean" "ünïcödé" \
  "$(MAX_NAME_LEN=7 ar_format 'x' 'ünïcödéxxxxxxx')"

# ---- icons ----
# Expected glyphs are built from explicit UTF-8 byte escapes rather than pasted
# literals: bash 3.2 has no $'\uXXXX', and the Private Use Area codepoints these
# tests assert on are precisely what an editor or a copy-paste silently ate once
# before (the old ar_icon shipped with every arm returning "", so ICONS_ENABLED
# was a no-op through v0.2.1). Byte escapes cannot be eaten that way, so these
# tests still fail loudly if the glyphs ever vanish from icons.sh again.
g_nvim=$(printf '\xee\x9a\xae')      # U+E6AE nf-custom-neovim
g_vim=$(printf '\xee\x98\xab')       # U+E62B nf-custom-vim
g_git=$(printf '\xee\x9c\x82')       # U+E702 nf-dev-git
g_node=$(printf '\xee\x9c\x98')      # U+E718 nf-dev-nodejs_small
g_python=$(printf '\xee\x9c\xbc')    # U+E73C nf-dev-python
g_docker=$(printf '\xef\x8c\x88')    # U+F308 nf-linux-docker
g_cargo=$(printf '\xee\x9e\xa8')     # U+E7A8 nf-dev-rust
g_go=$(printf '\xee\x98\xa7')        # U+E627 nf-seti-go
g_agent=$(printf '\xf3\xb0\x9a\xa9') # U+F06A9 nf-md-robot
g_htop=$(printf '\xee\xae\xa2')      # U+EBA2

# ar_icon must return a real glyph per program group, not the empty string.
check "ar_icon nvim" "$g_nvim" "$(ar_icon nvim)"
check "ar_icon vim" "$g_vim" "$(ar_icon vim)"
check "ar_icon gvim" "$g_vim" "$(ar_icon gvim)"
check "ar_icon git" "$g_git" "$(ar_icon git)"
check "ar_icon lazygit" "$g_git" "$(ar_icon lazygit)"
check "ar_icon node" "$g_node" "$(ar_icon node)"
check "ar_icon pnpm" "$g_node" "$(ar_icon pnpm)"
check "ar_icon python3" "$g_python" "$(ar_icon python3)"
check "ar_icon docker" "$g_docker" "$(ar_icon docker)"
check "ar_icon cargo" "$g_cargo" "$(ar_icon cargo)"
check "ar_icon go" "$g_go" "$(ar_icon go)"
check "ar_icon claude" "$g_agent" "$(ar_icon claude)"
check "ar_icon codex" "$g_agent" "$(ar_icon codex)"
# htop used to be the "unknown program" sentinel; the upstream map knows it.
check "ar_icon htop" "$g_htop" "$(ar_icon htop)"

# A program missing from the map gets the fallback glyph by default; an empty
# ICON_FALLBACK turns that off and restores the old empty-returning contract.
check "ar_icon unknown -> fallback" "?" "$(ar_icon nosuchprog)"
check "ar_icon unknown, fallback off -> empty" "" "$(ICON_FALLBACK='' ar_icon nosuchprog)"
# The fallback must never apply to the empty argument (ar_format only asks for
# a real program; ar_icon '' is a guard, not a lookup).
check "ar_icon empty arg -> empty" "" "$(ar_icon '')"

# ICON_MAP overrides win over both the builtin map and the fallback. (Arrays
# cannot be passed as a command prefix -- bash exports them as a flat string --
# so the assignment is a separate statement before the call, as elsewhere.)
check "ICON_MAP overrides builtin glyph" "$g_vim" "$(
  ICON_MAP=("nvim=${g_vim}")
  ar_icon nvim
)"
check "ICON_MAP covers unknown program" "$g_agent" "$(
  ICON_MAP=("nosuchprog=${g_agent}")
  ar_icon nosuchprog
)"

# ICON_STYLE wiring, end to end through ar_format.
check "icon style default is icon+name" "$g_nvim nvim" \
  "$(ICONS_ENABLED=1 ar_format 'nvim' 'nvim')"
check "icon style 'name_and_icon' is icon+name" "$g_git git" \
  "$(ICONS_ENABLED=1 ICON_STYLE=name_and_icon ar_format 'git' 'git status')"
check "icon style 'icon' is glyph only" "$g_nvim" \
  "$(ICONS_ENABLED=1 ICON_STYLE=icon ar_format 'nvim' 'nvim')"
check "icon style 'name' suppresses glyph" "nvim" \
  "$(ICONS_ENABLED=1 ICON_STYLE=name ar_format 'nvim' 'nvim')"

# Icons off (the default) never prepends a glyph, even for a known program.
check "icons off -> no glyph" "nvim" "$(ar_format 'nvim' 'nvim')"
# Unknown program with icons on and the fallback off: plain name, no glyph.
check "icons on, fallback off, unknown -> plain name" "nosuchprog" \
  "$(ICONS_ENABLED=1 ICON_FALLBACK='' SHOW_PROGRAM_ARGS=0 ar_format 'nosuchprog' 'nosuchprog -d 5')"
# Unknown program with icons on: fallback glyph + name.
check "icons on, unknown -> fallback glyph + name" "? nosuchprog" \
  "$(ICONS_ENABLED=1 SHOW_PROGRAM_ARGS=0 ar_format 'nosuchprog' 'nosuchprog -d 5')"
# An ignored program keeps showing the shell, so it gets no icon either --
# even though sudo has a real glyph in the map and ls would hit the fallback.
check "icons on, ignored program -> shell name, no icon" "zsh" \
  "$(ICONS_ENABLED=1 ar_format 'sudo' 'sudo apt update')"
# ICON_MAP works end to end through ar_format.
check "ICON_MAP override end to end" "$g_agent nosuchprog" \
  "$(
    ICON_MAP=("nosuchprog=${g_agent}")
    ICONS_ENABLED=1 SHOW_PROGRAM_ARGS=0 ar_format 'nosuchprog' 'nosuchprog -x'
  )"

# A glyph is one codepoint, so "<glyph> <name>" must be truncated by codepoint,
# never mid-byte. node is not name-only, so its cmdline is long enough to cut:
# MAX_NAME_LEN=6 keeps the glyph, the space, and 4 chars of the name.
check "icon+name truncates on codepoint boundary" "$g_node node" \
  "$(ICONS_ENABLED=1 MAX_NAME_LEN=6 SHOW_PROGRAM_ARGS=1 ar_format 'node' 'nodeandmore')"

# ---- default: SHOW_PROGRAM_ARGS defaults to 0 (regular program -> name only) ----
got=$(bash -c 'SHELL_NAME=zsh; . "$1"; ar_format htop "htop -d 5"' _ "$here/../naming.sh")
check "SHOW_PROGRAM_ARGS defaults to name-only" "htop" "$got"

# ---- config arrays: an intentionally-empty override must survive the guard ----
# naming.sh uses `declare -p`, not `${arr+x}` (which reports a zero-element array
# as unset and would silently restore the default list). Source it fresh in a
# subshell with IGNORED_PROGRAMS=() and confirm `ls` is no longer suppressed.
got=$(bash -c 'SHELL_NAME=zsh; SHOW_PROGRAM_ARGS=1; IGNORED_PROGRAMS=(); . "$1"; ar_format ls "ls -la"' _ "$here/../naming.sh")
check "empty IGNORED_PROGRAMS override survives" "ls -la" "$got"

t_summary

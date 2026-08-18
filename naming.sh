# naming.sh - pure, herdr-free name computation for herdr-automatic-rename.
#
# Sourced by automatic-rename.sh. Every function is string-in / string-out (no herdr
# or filesystem calls) so the logic is unit-testable on its own (see
# tests/test_naming.sh). Targets bash 3.2 (macOS /bin/bash): no associative
# arrays, no namerefs. Functions share the ar_ prefix with the engine, which
# calls ar_format across the module seam.
#
# Naming rule: a tab is named after its foreground program (nvim, claude, git,
# ...). At a bare prompt, or while a quick throwaway command runs, it shows the
# shell name (e.g. zsh) instead -- or nothing at all with HIDE_SHELL=1. Loosely
# modeled on tmux-window-name, minus the directory-based naming.
#
# Every list below is guarded with `declare -p` rather than `${VAR+x}`, so
# clearing one in config.sh (e.g. IGNORED_PROGRAMS=()) actually takes effect:
# `${VAR+x}` reports a zero-element array as unset and would overwrite it.

# Icon knobs, the glyph map, and ar_icon live in icons.sh (same directory) so
# this file stays free of the 100+ entry glyph table. Sourcing it here keeps
# every caller of naming.sh (automatic-rename.sh and the test suite) working
# unchanged. icons.sh loads after config.sh has run, so its defaults only fill
# unset vars.
_ar_icons_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$_ar_icons_dir/icons.sh"
unset _ar_icons_dir

# ---- configurable knobs (override in config.sh / $HERDR_AUTOMATIC_RENAME_CONFIG) ----
: "${MAX_NAME_LEN:=20}"     # truncate the final label to this many chars
: "${SHOW_PROGRAM_ARGS:=0}" # 1 = regular programs show their full command line; 0 = name only

# 1 = name a tab running a coding agent after the task the agent reports in its
# terminal title ("Squash merge command"), rather than after the agent program
# ("claude"). Coding agents keep that title current as the work changes, so this
# is what tells five claude tabs apart. herdr publishes it on the pane, so the
# name costs no extra call -- and where it lands the tab needs no process lookup
# at all. 0 names every agent tab after its program, as before.
#
# A title only replaces the program name when it says something: see
# ar_title_clean for what gets refused. Whenever it refuses, naming falls back to
# the program, PROGRAM_ALIASES included.
: "${AGENT_TITLES:=1}"

# Truncate a title to this many characters, at a word boundary where one is close
# enough. Titles are sentences, not command names, so they get more room than a
# command name -- but derived from MAX_NAME_LEN, so narrowing that for a narrow
# tab bar narrows titles with it instead of leaving them at a fixed 28.
: "${MAX_TITLE_LEN:=$(( ${MAX_NAME_LEN:-20} + 8 ))}"

# Field separator for the rows this module reads, matching AR_ROW_SEP in
# automatic-rename.sh, which sets it before sourcing this file (the fallback here
# is what lets the module and its tests stand alone). A tab or a newline would not
# do: bash counts both as IFS whitespace and `read` collapses them, losing an
# empty field. Change one and change the other.
: "${AR_ROW_SEP:=$'\037'}"

# Name shown at a bare prompt (no foreground program), and while an
# IGNORED_PROGRAMS command runs, so the tab holds steady instead of flickering.
: "${SHELL_NAME:=${SHELL##*/}}"
: "${SHELL_NAME:=zsh}"

# 1 = give the tab no name at all in every case that would otherwise show the
# shell: a bare prompt, an explicit SHELLS entry, an IGNORED_PROGRAMS command.
# The empty label hands the tab back to herdr, which then renders its own tab
# number, so a shell tab reads "3" instead of "zsh" (issue #5). With AUTO_INDEX=1
# the label keeps the jump number and nothing else ("[3]"), so the tab can still
# be jumped to.
: "${HIDE_SHELL:=0}"

# Foreground processes that mean "a shell prompt" -> shown by their own name.
declare -p SHELLS >/dev/null 2>&1 || SHELLS=(zsh bash sh fish dash ksh)

# Programs shown by bare name, without command-line args (i.e. with
# SHOW_PROGRAM_ARGS=1, which is what makes this list visible). Coding agents are
# included so an agent tab reads as "claude" rather than its full invocation.
#
# The agent entries are the executable names herdr itself detects as interactive
# agents (src/detect/mod.rs, herdr 0.8.0). Two differ from herdr's --kind id and
# both spellings are listed: cursor-agent (kind "cursor") and kiro-cli (kind
# "kiro"). aider is not a herdr agent kind but is a real agent, so it stays.
declare -p NAME_ONLY_PROGRAMS >/dev/null 2>&1 || NAME_ONLY_PROGRAMS=(nvim vim vi view gvim git lazygit gitui lazydocker
  claude codex aider pi gemini cursor cursor-agent devin agy antigravity cline omp mastracode opencode
  copilot kimi kiro kiro-cli droid amp grok hermes kilo qodercli)

# Quick tools that should not take over the tab name: while one runs the tab
# keeps showing the shell (SHELL_NAME) so it does not flicker.
declare -p IGNORED_PROGRAMS >/dev/null 2>&1 || IGNORED_PROGRAMS=(ls eza ll la cd z zoxide cat bat less more echo pwd clear which man head tail wc cp mv rm mkdir touch fzf sudo doas)

# Language runtimes and package runners that front for the program you actually
# launched. An agent installed from npm is usually a bin shim pointing at a JS
# entrypoint: the kernel execs the interpreter, so the foreground process is
# node and the tab would be named after it. A pip or pipx console script is the
# same story for python. (An agent whose package ships or execs a native binary
# -- claude, opencode -- reports its own name and never needs this.)
#
# Where herdr has detected an agent in that pane, its answer is used instead (see
# ar_tab_name). Everywhere else these are named as any other program, so a plain
# `node server.js` tab is untouched.
declare -p WRAPPER_PROGRAMS >/dev/null 2>&1 || WRAPPER_PROGRAMS=(node bun deno npx bunx npm pnpm yarn
  python python3 uv uvx pipx ruby)

# Ordered, complete `sed -E` programs applied to the final display string.
declare -p SUBSTITUTE_SETS >/dev/null 2>&1 || SUBSTITUTE_SETS=(
  's|.*ipython([32])|ipython\1|'
  's|.*poetry shell.*|poetry|'
)

# Titles that name the agent instead of the work it is doing. An agent sets one
# of these before it has a task (at startup, or once a session is cleared), and a
# tab reading "Claude Code" says less than "claude" does. Matched case-insensitively
# against the whole title. The agent kind itself, that kind followed by "code", the
# directory the pane sits in, and a bare number are refused without being listed.
declare -p TITLE_IGNORE >/dev/null 2>&1 || TITLE_IGNORE=("claude code" "codex cli" "gemini cli"
  "opencode" "amp code" "cursor agent" "new session" "untitled")

# Exact program-name renames: "<program>=<label>" pairs. A matching foreground
# program is shown as <label> regardless of its category (e.g. "clx=hn" makes a
# clx tab read "hn"). Takes priority over every rule except the bare-prompt shell
# name. Set this in config.sh, e.g. PROGRAM_ALIASES=("clx=hn" "lazygit=lg").
declare -p PROGRAM_ALIASES >/dev/null 2>&1 || PROGRAM_ALIASES=()

# ---- helpers ----

# ar_in_list <needle> <list items...>
ar_in_list() {
  local n=$1 e
  shift
  for e in "$@"; do [ "$e" = "$n" ] && return 0; done
  return 1
}

# ar_alias <program> -> its PROGRAM_ALIASES label, or empty when unaliased.
ar_alias() {
  local n=$1 pair
  [ -n "$n" ] || return 0
  for pair in "${PROGRAM_ALIASES[@]}"; do
    case "$pair" in
    "$n="*)
      printf '%s' "${pair#*=}"
      return 0
      ;;
    esac
  done
}

# ar_subst <string> -> string with SUBSTITUTE_SETS applied in order
ar_subst() {
  local s=$1 expr
  for expr in "${SUBSTITUTE_SETS[@]}"; do
    s=$(printf '%s' "$s" | sed -E "$expr")
  done
  printf '%s' "$s"
}

# ar_title_clean <title> <title lowercased> <pane directory lowercased> <agent kind>
#   -> the task the title describes, or "" when it describes no task and the
#      program name is the better label.
#
# The title arrives with its leading run of non-alphanumerics already gone: an
# agent parks a spinner glyph there while it works, and herdr reports the title
# with the glyph still on, so a tab would flip between "Task" and "<glyph> Task"
# on every status change. That strip and the lowercasing happen in the jq that
# lifts the title off the pane (see AR_JQ_CLEAN), because jq knows Unicode where a
# byte-wise strip in bash would eat the first letter of "Überprüfung" and a
# byte-wise fold would not touch it. Everything left here is a comparison, so this
# function costs nothing.
ar_title_clean() {
  local t=$1 lower=$2 dirlc=$3 kind=$4
  [ -n "$t" ] || return 0
  # A bare number is herdr's own tab label handed back, not a task.
  case $t in *[!0-9]*) : ;; *) return 0 ;; esac
  # Everything that names the agent instead of its work: the kind on its own, the
  # kind with "code" after it, the directory the pane sits in, and the titles an
  # agent shows before there is a task. $dirlc may be empty and $lower never is,
  # so an unknown directory refuses nothing.
  ar_title_ignore_fold
  ar_in_list "$lower" "$kind" "$kind code" "$dirlc" "${_ar_title_ignore_lc[@]}" && return 0
  printf '%s' "$t"
}

# ar_title_ignore_fold - lowercase TITLE_IGNORE once per run, into
# $_ar_title_ignore_lc. The comparison above is against a lowercased title, and a
# user writing "New Session" should not silently get nothing, so the list is
# folded rather than documented as case-sensitive. Folded on first use, not at
# load: the shell hooks source this file on every prompt and never name a tab
# after a title.
ar_title_ignore_fold() {
  [ -n "${_ar_title_ignore_done:-}" ] && return 0
  _ar_title_ignore_done=1
  _ar_title_ignore_lc=()
  [ "${#TITLE_IGNORE[@]}" -gt 0 ] || return 0
  local entry
  while IFS= read -r entry; do
    [ -n "$entry" ] && _ar_title_ignore_lc+=("$entry")
  done <<< "$(printf '%s\n' "${TITLE_IGNORE[@]}" | tr 'A-Z' 'a-z')"
}

# ---- helpers ----

# ar_format <program|""> <cmdline> [title] -> final tab label
#   program == "" means a bare prompt (name by the shell).
ar_format() {
  local prog=$1 cmdline=$2 title=${3:-} name="" ic aliased="" is_shell=0 max=${MAX_NAME_LEN:-20}
  # Only the program-name chain below consults an alias, so a title (or a bare
  # prompt) does not pay for the lookup.
  [ -n "$prog" ] && [ -z "$title" ] && aliased=$(ar_alias "$prog")
  if [ -n "$title" ]; then
    # A task title from ar_title_clean. It replaces the program name outright,
    # alias and all: AGENT_TITLES is the switch for wanting the task instead, and
    # an alias set to shorten "claude" to "cl" is not a request to hide the work.
    # It still gets the icon for the program below, and its own length budget.
    name=$title
    max=${MAX_TITLE_LEN:-28}
  elif [ -z "$prog" ]; then
    name=$SHELL_NAME
    is_shell=1
  elif [ -n "$aliased" ]; then
    name=$aliased # user rename (PROGRAM_ALIASES) wins
  elif ar_in_list "$prog" "${SHELLS[@]}"; then
    name=$prog
    is_shell=1 # a shell shows its own name (zsh)
  elif [ "$prog" = "$SHELL_NAME" ]; then
    name=$prog
    is_shell=1 # the login shell, even outside SHELLS (nu, tcsh, ...)
  elif ar_in_list "$prog" "${IGNORED_PROGRAMS[@]}"; then
    name=$SHELL_NAME
    is_shell=1 # quick tools: keep showing the shell
  elif ar_in_list "$prog" "${NAME_ONLY_PROGRAMS[@]}"; then
    name="$(ar_subst "$prog")" # nvim, claude, ...: just the name
  elif [ "${SHOW_PROGRAM_ARGS:-1}" = "1" ] && [ -n "$cmdline" ]; then
    name="$(ar_subst "$cmdline")"
  else
    name="$(ar_subst "$prog")"
  fi

  # HIDE_SHELL: drop the shell label entirely and let herdr number the tab. An
  # explicit PROGRAM_ALIASES entry for a shell (e.g. "fish=sh") is a name the
  # user asked for by hand, so it survives; nothing else about a shell tab does
  # -- bare prompt, an explicit SHELLS entry, an IGNORED_PROGRAMS command, or
  # the login shell itself.
  if [ "${HIDE_SHELL:-0}" = "1" ] && [ "$is_shell" = "1" ]; then
    printf ''
    return 0
  fi

  # Icons annotate the program the tab is named after. Skip them whenever the
  # label is a shell name: precmd names an idle prompt via ar_format "" "",
  # which `[ -n "$prog" ]` denies an icon, so a glyph here would flip the label
  # between "zsh" and "<glyph> zsh" on every reconcile. is_shell covers the
  # bare prompt, the fixed SHELLS six, IGNORED_PROGRAMS, and the login shell
  # itself (SHELL_NAME may sit outside SHELLS -- nu, tcsh, elvish -- yet still
  # hit the map, or the fallback, at reconcile); comparing against SHELL_NAME
  # additionally keeps a cmdline- or alias-derived label of the same text plain.
  if [ "${ICONS_ENABLED:-0}" = "1" ] && [ -n "$prog" ] && [ "$is_shell" = "0" ] &&
    [ "$name" != "$SHELL_NAME" ]; then
    ic=$(ar_icon "$prog")
    # A lone fallback glyph says nothing about the program, so under
    # ICON_STYLE=icon it is skipped and the plain name is kept: rg -> "rg",
    # not "?". (name_and_icon still shows "? rg".)
    if [ "${ICON_STYLE:-name_and_icon}" = "icon" ] && [ -n "$ic" ] && [ "$ic" = "$ICON_FALLBACK" ]; then
      ic=""
    fi
    if [ -n "$ic" ]; then
      case "${ICON_STYLE:-name_and_icon}" in
      icon) name=$ic ;;                      # icon only
      name) : ;;                             # name only (icon suppressed)
      name_and_icon | *) name="$ic $name" ;; # icon + name (default)
      esac
    fi
  fi
  # Scrub what a command line can carry into a label: control characters (argv
  # can hold a newline or a tab, and SHOW_PROGRAM_ARGS=1 puts argv in the label)
  # and runs of whitespace. herdr takes the string verbatim, so an unscrubbed one
  # reaches the tab bar as it is.
  #
  # One tr both translates and squeezes, and only for a label that needs it: the
  # case guard keeps the fork off a clean label, which is nearly all of them and
  # all of the ones on the shell-hook path. Squeezing FIRST is what makes the
  # single-character trims below enough. A UTF-8 label survives either tr: a
  # bytewise one never matches a continuation byte (every one is >= 0x80, outside
  # the class), and a locale-aware one consumes whole characters.
  case $name in
  *[[:cntrl:]]* | *"  "*) name=$(printf '%s' "$name" | tr -s '[:cntrl:] ' ' ') ;;
  esac
  name=${name# }
  name=${name% }

  # Truncate by Unicode codepoint, not byte. bash's ${#name} / ${name:0:$max}
  # count bytes under a C/POSIX locale (herdr may launch plugins with no LC_*),
  # which would slice a multibyte char in half and emit mojibake. jq (already a
  # hard dependency of this plugin) always reads input as UTF-8, so it slices on
  # codepoint boundaries regardless of the ambient locale; fall back to the byte
  # cut only if jq is somehow unavailable.
  if [ "${#name}" -gt "$max" ]; then
    local truncated
    truncated=$(printf '%s' "$name" | jq -Rrs --argjson n "$max" '.[:$n]' 2>/dev/null || printf '')
    if [ -n "$truncated" ]; then
      name=$truncated
    else
      name=${name:0:$max}
    fi
    # A title is a sentence, so cut it at a word boundary rather than mid-word --
    # but only when that leaves most of the budget, since "Investigate" tells you
    # more than "I" does.
    if [ -n "$title" ]; then
      # ${name% *} is the whole string when there is no space in it, so a single
      # long word is left cut where it was. The half-budget floor is what stops
      # "Investigate" from becoming "I". Counting bytes is deliberate here: the
      # floor is a heuristic, not the cut.
      local short=${name% *}
      [ "${#short}" -ge $(( max / 2 )) ] && name=$short
    fi
  fi
  printf '%s' "$name"
}

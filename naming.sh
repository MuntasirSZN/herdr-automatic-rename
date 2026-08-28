# naming.sh - pure, herdr-free name computation for herdr-automatic-rename.
#
# Sourced by automatic-rename.sh. Every function is string-in / string-out (no herdr
# or filesystem calls) so the logic is unit-testable on its own (see
# tests/test_naming.sh). Targets bash 3.2 (macOS /bin/bash): no associative
# arrays, no namerefs. Functions share the ar_ prefix with the engine, which
# calls ar_label across the module seam.
#
# Two environment variables are read for DEFAULTS, both below: $SHELL names the
# shell a bare prompt is labeled with, and $HOME is the directory ar_context_dir
# treats as nowhere in particular. Neither is looked up per call.
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
# shellcheck source=icons.sh
. "$_ar_icons_dir/icons.sh"
unset _ar_icons_dir

# ---- configurable knobs (override in config.sh / $HERDR_AUTOMATIC_RENAME_CONFIG) ----
# The ACTIVITY half of a label -- the program, or an agent's task -- is cut to
# this. Each part of a label carries a budget of its own (MAX_CONTEXT_LEN and
# MAX_BRANCH_LEN are the others), so the whole is bounded by construction and
# there is no total to keep in step with the parts.
: "${MAX_NAME_LEN:=20}"     # truncate the program name to this many chars
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

# ---- the context half of a label (TAB_CONTEXT) ----

# 1 = put the context in front of the program: the directory the pane sits in,
# the branch it has checked out, the machine it reached over ssh. A tab says WHAT
# is running; without this half, five agent tabs across three checkouts read alike
# and tell each other apart by position only. 0 names by the program alone, as
# before.
#
# The switch is read inside ar_context_dir rather than at each call site, because
# the reconcile and the shell hook both compute labels and a label they disagree
# about is a tab that flips on every prompt.
: "${TAB_CONTEXT:=1}"

# Truncate the directory part to this many characters. It is a project name, not
# a sentence, and the program beside it still needs the room MAX_NAME_LEN gives
# it -- so it gets a budget of its own rather than eating that one.
: "${MAX_CONTEXT_LEN:=12}"

# 1 = qualify the context with the branch the pane's repository has checked out:
# "api > MC-13675 > nvim". It says which slice of a project a tab is on, where
# the directory alone says only which project. 0 leaves branches out, and so
# does MAX_BRANCH_LEN=0.
: "${SHOW_BRANCH:=1}"

# Longest branch a label may carry, in characters. Twelve holds an issue key, or
# a word and part of the next. A branch over it is reduced rather than dropped:
# see ar_branch_label.
: "${MAX_BRANCH_LEN:=12}"

# What joins the parts of a label. Where a part came from -- a directory, a
# branch, a program -- is not something a separator can convey, so every part
# shares one. Written as its UTF-8 bytes for the reason icons.sh writes its
# glyphs that way: a literal one is what an editor or a copy-paste eats without
# saying so. This is U+203A, a single right-pointing angle quote.
: "${CONTEXT_SEP:=$' \342\200\272 '}"

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
# agents (src/detect/mod.rs, herdr 0.8.2). Two differ from herdr's --kind id and
# both spellings are listed: cursor-agent (kind "cursor") and kiro-cli (kind
# "kiro"). aider is not a herdr agent kind but is a real agent, so it stays.
declare -p NAME_ONLY_PROGRAMS >/dev/null 2>&1 || NAME_ONLY_PROGRAMS=(nvim vim vi view gvim git lazygit gitui lazydocker
  claude codex aider pi gemini cursor cursor-agent devin agy antigravity cline omp mastracode opencode
  copilot kimi kiro kiro-cli droid amp grok hermes kilo qodercli qwen maki)

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

# Agents that stamp their own brand on the FRONT of every title, as
# "<herdr agent kind>=<brand>" pairs. oh-my-pi titles a session
# "<brand> <spinner> Fix the parser" while it works, "<brand> > ..." when the turn
# is yours, "<brand> ! ..." when it wants you, and "<brand>: ..." with its title
# state off, so its brand arrives in front of the status glyph rather than behind
# it. The spinner strip only takes a LEADING run of non-alphanumerics and jq reads
# the brand as a letter, so the strip stopped on it and each of those states
# reached the tab as a different label: the glyph on show, and a rename on every
# status change (issue #12). Naming the brand takes it off and leaves the separator
# to the strip that was already there -- so a title of nothing but brand and glyph
# empties out and the tab falls back to the program name, which is the answer an
# agent with no task wants.
#
# Only at the very front, and only with a non-alphanumeric behind it, so a title
# that merely starts with the same letter keeps it. Matched ignoring the case of
# ASCII letters, like every other title compare. The brand is written as its bytes
# for the reason icons.sh writes its glyphs that way: a literal one is what an
# editor eats without saying so. "pi" and "omp" are both canonical herdr agent
# kinds (src/detect/mod.rs, herdr 0.8.2) and both are the same program's brand.
declare -p TITLE_BRANDS >/dev/null 2>&1 || TITLE_BRANDS=("pi="$'\317\200' "omp="$'\317\200')

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

# ar_trunc <string> <max> -> the string cut to <max> Unicode codepoints.
#
# Not bytes: bash's ${#s} and ${s:0:$max} count those under a C/POSIX locale
# (herdr may launch plugins with no LC_*), which slices a multibyte character in
# half and emits mojibake. jq (already a hard dependency) always reads its input
# as UTF-8, so it slices on codepoint boundaries whatever the ambient locale is;
# the byte cut is the fallback for a jq that is somehow unavailable. The length
# test is a byte count on purpose -- a string of fewer bytes than max is also of
# fewer codepoints, so the fork is skipped for every label that does not need it.
ar_trunc() {
  local s=$1 max=$2 cut
  [ "${#s}" -gt "$max" ] || { printf '%s' "$s"; return 0; }
  cut=$(printf '%s' "$s" | jq -Rrs --argjson n "$max" '.[:$n]' 2>/dev/null || printf '')
  [ -n "$cut" ] || cut=${s:0:$max}
  printf '%s' "$cut"
}

# ar_context_dir <pane directory> <workspace base label> -> the directory part of
# the context, or "" when the directory says nothing worth a tab's width.
#
# The BASENAME, not ar_project_base's answer: that walks up to the repository a
# directory belongs to, which is what herdr names a WORKSPACE after and therefore
# the one thing a tab in it must not repeat. A tab cd'd into a subdirectory of
# its project says which subdirectory, where the repository name would say what
# the sidebar says.
#
# Normally the project name, then. Refused: a relative path (whatever
# the reader's cwd makes of it -- herdr reports absolute ones), the filesystem
# root, and the home directory, which is where a shell sits when it is nowhere in
# particular.
#
# Also refused: the name of the workspace the tab is in. herdr shows that above
# the tabs, so a tab there spends half its width repeating what is already on
# screen. Matched ignoring case, and exactly otherwise -- a tab whose directory
# has left its workspace behind is exactly the one that keeps saying where it is.
#
# The fold is the shell's, so it follows the locale: ASCII where the plugin was
# launched without one, and whatever the locale knows where it has one. That is
# the opposite of the choice made for title comparisons, and deliberately: both
# sides here are directory names the user chose themselves, so folding `Ä` onto
# `ä` drops a repetition they would also call one, where a title compared against
# a product name has no such licence.
ar_context_dir() {
  local dir=$1 ws=$2 base
  [ "${TAB_CONTEXT:-1}" = "1" ] || return 0
  case $dir in /*) ;; *) return 0 ;; esac
  dir=${dir%/}                        # a trailing slash names the same directory
  [ -n "$dir" ] || return 0           # ... and "/" is left with nothing
  [ "$dir" = "${HOME%/}" ] && return 0
  base=${dir##*/}
  [ -n "$base" ] || return 0
  if [ -n "$ws" ]; then
    # A QUOTED right-hand side is a literal string rather than a glob, so a
    # workspace named "a[b" compares as itself; nocasematch is what folds the
    # case, and it folds ASCII under the C locale the plugin may be launched in.
    local folded=1 nocase
    nocase=$(shopt -p nocasematch)      # whatever the caller had, to put back
    shopt -s nocasematch
    [[ $base == "$ws" ]] || folded=0
    $nocase
    [ "$folded" = "1" ] && return 0
  fi
  ar_trunc "$base" "${MAX_CONTEXT_LEN:-12}"
}

# The characters branch names are built out of. Cutting a long one at any of
# them ends it on a whole word.
_AR_BRANCH_SEPS='-_./ '

# The alphabet, for ar_upper. Two strings and an index rather than `tr`, because
# what this raises is an issue key on a path that runs per named tab on every
# event and again on every shell prompt, and `tr` is a process.
_AR_LOWER='abcdefghijklmnopqrstuvwxyz'
_AR_UPPER='ABCDEFGHIJKLMNOPQRSTUVWXYZ'

# An issue key: two to six letters and at least two digits, on its own rather
# than inside a longer word. The bounds are what keep it clear of hyphenated
# words ("utf-8" has too few digits, "release-2026" too many letters). Held in a
# variable because bash 3.2 matches an unquoted one as a pattern and a quoted one
# as a literal.
_AR_BRANCH_KEY='(^|[^[:alnum:]])([[:alpha:]]{2,6}-[[:digit:]]{2,6})([^[:digit:]]|$)'

# ar_upper <string> -> the string with its ASCII lowercase letters raised, and
# every other character left exactly as it is. Folding ASCII alone is deliberate,
# as everywhere else in this file: what this raises is a tracker's own alphabet,
# not the user's prose.
ar_upper() {
  local s=$1 out="" c rest
  while [ -n "$s" ]; do
    c=${s%"${s#?}"}                     # the first character, however wide
    s=${s#?}
    # A letter cuts the alphabet in two, and where it sits is how much is left.
    # A character that is not one leaves the alphabet whole, which is the test.
    rest=${_AR_LOWER#*"$c"}
    [ "$rest" != "$_AR_LOWER" ] && c=${_AR_UPPER:$(( 25 - ${#rest} )):1}
    out=$out$c
  done
  printf '%s' "$out"
}

# ar_branch_wanted -> 0 when a branch would be shown at all. Its own function
# because the engine asks BEFORE reading a repository: the answer is no reads at
# all rather than reads whose answer is thrown away.
ar_branch_wanted() {
  [ "${TAB_CONTEXT:-1}" = "1" ] || return 1
  [ "${SHOW_BRANCH:-1}" = "1" ] || return 1
  [ "${MAX_BRANCH_LEN:-12}" -gt 0 ] 2>/dev/null || return 1
}

# ar_branch_label <branch or short hash> <the repository's default branch>
#   -> what the branch contributes to a label, or "" when it contributes nothing.
#
# Three rules keep it from saying anything it has not earned:
#
#   The trunk contributes nothing. Every tab in the repository would carry it
#   alike, so it is a column of noise. The comparison is exact, because git refs
#   are: a branch named `Main` beside a `main` trunk is a different branch.
#
#   A name that fits is left whole. `feat/oauth` keeps the namespace that tells
#   it from `fix/oauth`; only a name too wide is touched at all.
#
#   Reducing one prefers an issue key outright, because that identifies the work
#   whatever convention wraps it, and it is the one value allowed past the
#   budget: half a key identifies nothing. Failing a key the namespace goes --
#   it is the half every branch in the repository shares -- and what is left is
#   cut at a whole word.
ar_branch_label() {
  local branch=$1 default=$2 max=${MAX_BRANCH_LEN:-12} cut next
  # Asked again here, though the engine asks before it reads a repository: this
  # is the rule, and a rule that is only enforced by its caller is one a second
  # caller can miss.
  ar_branch_wanted || return 0
  [ -n "$branch" ] || return 0
  [ "$branch" = "$default" ] && return 0
  [ "${#branch}" -le "$max" ] && { printf '%s' "$branch"; return 0; }
  if [[ $branch =~ $_AR_BRANCH_KEY ]]; then
    # Folding ASCII alone is deliberate, as everywhere else in this file: an
    # issue key is a tracker's own alphabet, not the user's prose.
    # shellcheck disable=SC2018,SC2019
    printf '%s' "${BASH_REMATCH[2]}" | tr 'a-z' 'A-Z' 
    return 0
  fi
  branch=${branch##*/}
  cut=$(ar_trunc "$branch" "$max")
  # When the character that did not fit is itself a separator the head already
  # ends on a whole word, and cutting again would throw one away.
  next=${branch:${#cut}:1}
  case $next in
  ["$_AR_BRANCH_SEPS"]) ;;
  *) case $cut in *["$_AR_BRANCH_SEPS"]*) cut=${cut%["$_AR_BRANCH_SEPS"]*} ;; esac ;;
  esac
  # A separator on either end says nothing on its own.
  cut=${cut#["$_AR_BRANCH_SEPS"]}
  cut=${cut%["$_AR_BRANCH_SEPS"]}
  printf '%s' "$cut"
}

# ar_compose <context> <branch> <activity> -> the tab's base label.
#
# Read as a path from the general to the particular -- where the work is, then
# what is being done -- with CONTEXT_SEP between every pair. Each part arrives
# already cut to its own budget, so the whole is bounded by construction and
# there is no second number to keep in step.
#
# An empty activity is HIDE_SHELL asking for no label at all, and half a label is
# not what it asked for: the tab is handed back to herdr whole.
ar_compose() {
  local ctx=$1 branch=$2 activity=$3 out=""
  [ -n "$activity" ] || return 0
  [ -n "$ctx" ] && out=$ctx
  [ -n "$branch" ] && { [ -n "$out" ] && out="$out$CONTEXT_SEP$branch" || out=$branch; }
  [ -n "$out" ] && out="$out$CONTEXT_SEP$activity" || out=$activity
  # Scrub what only this half of a label can carry in. The reconcile's directory
  # arrives through jq's `clean` and the activity is scrubbed by ar_format, but
  # the shell hook takes its directory from a raw $PWD -- and a directory may be
  # named anything a filesystem accepts. A control character reaching the tab bar
  # is the visible half of it; the invisible half is that herdr hands the label
  # back normalized, which reads as a name somebody typed and opts the tab out of
  # naming for good. Guarded, so a clean label pays no fork (the common case).
  case $out in
  *[[:cntrl:]]* | *"  "*) out=$(printf '%s' "$out" | tr -s '[:cntrl:] ' ' ')
                          out=${out# }; out=${out% } ;;
  esac
  printf '%s' "$out"
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
  # A title that is a PATH is the same "nothing to say yet" answer in a longer
  # coat: an agent titling itself `~/dev/api` or `/home/u/dev/api` is naming where
  # it sits, not what it is doing. The list above catches the bare directory name;
  # this catches the path that ends in it.
  #
  # Only for a title with no whitespace in it, though, or a real description would
  # go the same way: "Fix build for services/payments" in a directory called
  # payments ends in exactly that word. A path has no spaces; a sentence about the
  # work almost always does. The leading dot is dropped from the directory too,
  # because a title of "~/.config" has already lost its own to the strip above.
  #
  # The trailing slash comes off before the tail is taken: `~/dev/api/` names the
  # same directory `~/dev/api` does, and ${lower##*/} on a string that ends in one
  # is EMPTY, which matches no directory and walked the whole path through.
  case $lower in
  *[[:space:]]*) : ;;
  *) local tail=${lower%/}; tail=${tail##*/}
     [ -n "$dirlc" ] && { [ "$tail" = "$dirlc" ] || [ "$tail" = "${dirlc#.}" ]; } && return 0 ;;
  esac
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
  # Folding ASCII only is deliberate: the comparisons this feeds are product and
  # directory names, and the Unicode-aware fold happens in jq (see AR_JQ_CLEAN).
  # shellcheck disable=SC2018,SC2019
  while IFS= read -r entry; do
    [ -n "$entry" ] && _ar_title_ignore_lc+=("$entry")
  done <<< "$(printf '%s\n' "${TITLE_IGNORE[@]}" | tr 'A-Z' 'a-z')"
}

# ---- helpers ----

# ar_label <pane directory> <workspace base> <branch> <program|""> <cmdline> [title]
#   -> the whole label a tab should carry.
#
# The branch arrives as an argument where the directory arrives raw, because
# reading it is a filesystem walk and this module does not touch the filesystem
# (see git.sh). So it is the one part a caller has to remember: ar_branch_of next
# to the engine's two naming paths is what both of them call for it.
#
# The one entry point for naming a tab. Both callers -- the reconcile and the
# shell hook's fast path -- go through it, so neither can skip a step the other
# takes: a label they disagree about is a tab that flips on every prompt. That is
# why the raw directory comes in rather than a context computed outside.
ar_label() {
  local ctx activity
  ctx=$(ar_context_dir "$1" "$2")
  activity=$(ar_format "$4" "$5" "${6:-}")
  ar_compose "$ctx" "$3" "$activity"
}

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

  # Cut to the budget (ar_trunc counts codepoints, not bytes).
  if [ "${#name}" -gt "$max" ]; then
    name=$(ar_trunc "$name" "$max")
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

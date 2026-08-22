#!/usr/bin/env bash
# Unit tests for naming.sh -- the pure, herdr-free name computation.
# String in / string out, so every rule is testable without a live herdr.

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh"

# Pin the shell name so bare-prompt cases are deterministic regardless of $SHELL.
SHELL_NAME=zsh
# shellcheck source=naming.sh
. "$here/../naming.sh"
# The engine too, for AR_JQ_CLEAN alone: the spinner strip a title gets before
# ar_title_clean ever sees it is a jq definition there now, and it is still worth
# pinning one seam over rather than only end to end (see the title section below).
# Sourcing the engine defines its functions and constants and runs nothing (the
# ar_main guard), which is what tests/test_prefix.sh relies on as well.
# shellcheck source=automatic-rename.sh
. "$here/../automatic-rename.sh"

# ---- bare prompt / shells ----
check "bare prompt -> shell name" "zsh" "$(ar_format '' '')"
check "explicit shell shows own name" "bash" "$(ar_format 'bash' 'bash')"
check "fish shell name" "fish" "$(ar_format 'fish' '')"

# ---- name-only programs (editors, agents, git) ----
check "nvim is name-only" "nvim" "$(ar_format 'nvim' 'nvim README.md')"
check "claude is name-only" "claude" "$(ar_format 'claude' 'claude --dangerously-skip-permissions')"
check "git is name-only" "git" "$(ar_format 'git' 'git status')"

# NAME_ONLY_PROGRAMS only bites with SHOW_PROGRAM_ARGS=1 (0 is the default and
# already renders bare names), so assert these there. Covers the agents herdr
# 0.8.0 detects, including the two whose executable differs from its --kind id.
check "grok is name-only" "grok" "$(SHOW_PROGRAM_ARGS=1 ar_format 'grok' 'grok --model x')"
check "agy is name-only" "agy" "$(SHOW_PROGRAM_ARGS=1 ar_format 'agy' 'agy --conversation 12')"
check "opencode is name-only" "opencode" "$(SHOW_PROGRAM_ARGS=1 ar_format 'opencode' 'opencode run x')"
check "cursor-agent name-only" "cursor-agent" "$(SHOW_PROGRAM_ARGS=1 ar_format 'cursor-agent' 'cursor-agent -p x')"
check "kiro-cli is name-only" "kiro-cli" "$(SHOW_PROGRAM_ARGS=1 ar_format 'kiro-cli' 'kiro-cli chat')"
check "gemini is name-only" "gemini" "$(SHOW_PROGRAM_ARGS=1 ar_format 'gemini' 'gemini -p hi')"

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

# ---- control characters and whitespace in a label ----
# argv can hold anything, and with SHOW_PROGRAM_ARGS=1 the command line IS the
# label. herdr sets the string verbatim, so a raw tab or newline out of a cmdline
# would land in the tab bar; worse, a label herdr normalized on the way in reads
# back as a string this plugin never set, and ar_name_eligible cannot tell that
# from a hand rename -- it would opt the tab out of naming for good. The control
# characters are written as printf escapes on purpose: a literal tab here is
# invisible to review and an editor or a copy-paste eats it silently.
check "tab in cmdline becomes a space" "htop -d 5" \
  "$(SHOW_PROGRAM_ARGS=1 ar_format 'htop' "$(printf 'htop\t-d 5')")"
check "newline in cmdline becomes a space" "htop -d 5" \
  "$(SHOW_PROGRAM_ARGS=1 ar_format 'htop' "$(printf 'htop\n-d 5')")"
check "BEL and ESC go the same way" "htop -d 5" \
  "$(SHOW_PROGRAM_ARGS=1 ar_format 'htop' "$(printf 'htop \x07-d\x1b 5')")"
check "runs of spaces collapse to one" "htop -d 5" \
  "$(SHOW_PROGRAM_ARGS=1 ar_format 'htop' 'htop   -d    5')"
check "leading and trailing space trimmed" "htop -d 5" \
  "$(SHOW_PROGRAM_ARGS=1 ar_format 'htop' '  htop -d 5  ')"
# A label with nothing to scrub must come through byte for byte -- the scrub sits
# on the path every name takes, so a label it rewrites is a label it broke.
check "ordinary label unchanged by the scrub" "htop -d 5" \
  "$(SHOW_PROGRAM_ARGS=1 ar_format 'htop' 'htop -d 5')"
# Control characters are ASCII-range bytes and a UTF-8 continuation byte is not,
# so scrubbing cannot cut a multibyte character in half on its way to the
# codepoint truncation below.
check "multibyte survives the scrub" "ünïcödé arg" \
  "$(SHOW_PROGRAM_ARGS=1 ar_format 'x' "$(printf 'ünïcödé\targ')")"

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

# Every program the engine names by itself has a glyph of its own. The roster is
# read out of NAME_ONLY_PROGRAMS rather than typed again here, which is the whole
# point: a hand-copied list only catches a typo in a name somebody already
# remembered to add in both files, and maki spent two herdr releases drawing the
# "?" fallback for exactly that reason. The robot glyph's bytes stay pinned by
# the claude and codex checks above.
for _prog in "${NAME_ONLY_PROGRAMS[@]}"; do
  check "ar_icon $_prog is mapped" "mapped" \
    "$([ -n "$(ICON_FALLBACK='' ar_icon "$_prog")" ] && echo mapped || echo unmapped)"
done

# A program missing from the map gets the fallback glyph by default; an empty
# ICON_FALLBACK turns that off and restores the old empty-returning contract.
check "ar_icon unknown -> fallback" "?" "$(ar_icon nosuchprog)"
check "ar_icon unknown, fallback off -> empty" "" "$(ICON_FALLBACK='' ar_icon nosuchprog)"
# The fallback must never apply to the empty argument (ar_format only asks for
# a real program; ar_icon '' is a guard, not a lookup).
check "ar_icon empty arg -> empty" "" "$(ar_icon '')"
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
# Shells get no icon even when the map knows them (zsh is in icons.sh, dash is
# not): precmd names an idle prompt via ar_format "" "", which `[ -n "$prog" ]`
# denies an icon, so a shell glyph here would flip the label between "zsh" and
# "<glyph> zsh" on every reconcile. The last check pins both paths to the same
# string.
check "icons on, shell program -> shell name, no icon" "zsh" \
  "$(ICONS_ENABLED=1 ar_format 'zsh' '-zsh')"
check "icons on, shell missing from map -> no fallback glyph" "dash" \
  "$(ICONS_ENABLED=1 ar_format 'dash' '')"
check "idle prompt and shell reconcile agree with icons on" \
  "$(ICONS_ENABLED=1 ar_format '' '')" \
  "$(ICONS_ENABLED=1 ar_format "$SHELL_NAME" '')"
# SHELL_NAME follows the user's real login shell, which can sit outside the
# fixed SHELLS six (nu, tcsh, elvish, ...). prog == SHELL_NAME is its own
# shell arm, so a reconcile reads the bare name (never the cmdline, even with
# SHOW_PROGRAM_ARGS=1 -- "-elvish" would dodge a name-based comparison) and
# gets no glyph or fallback, keeping it equal to the idle prompt.
check "odd login shell (elvish) gets no icon" "elvish" \
  "$(SHELL_NAME=elvish ICONS_ENABLED=1 ar_format 'elvish' '')"
check "odd login shell outside map (nu) -> no fallback glyph" "nu" \
  "$(SHELL_NAME=nu ICONS_ENABLED=1 ar_format 'nu' '')"
check "odd login shell with args on -> shell name, no icon" "elvish" \
  "$(SHELL_NAME=elvish ICONS_ENABLED=1 SHOW_PROGRAM_ARGS=1 ar_format 'elvish' '-elvish')"
check "idle and odd-shell reconcile agree with args on" \
  "$(SHELL_NAME=elvish ICONS_ENABLED=1 SHOW_PROGRAM_ARGS=1 ar_format '' '')" \
  "$(SHELL_NAME=elvish ICONS_ENABLED=1 SHOW_PROGRAM_ARGS=1 ar_format 'elvish' '-elvish')"
# Under ICON_STYLE=icon a lone fallback glyph would be the whole label, so it
# is suppressed and the plain name kept; name_and_icon still shows "? name"
# (pinned above).
check "icon style 'icon' with unknown program -> plain name" "nosuchprog" \
  "$(ICONS_ENABLED=1 ICON_STYLE=icon SHOW_PROGRAM_ARGS=0 ar_format 'nosuchprog' 'nosuchprog -d 5')"
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

# ---- HIDE_SHELL: every shell-ish case names the tab nothing (issue #5) ----
# The empty label is what makes herdr fall back to rendering its own tab number,
# so these must be EMPTY strings, not $SHELL_NAME and not a space.
check "hide_shell bare prompt" "" "$(HIDE_SHELL=1 ar_format '' '')"
check "hide_shell explicit fish" "" "$(HIDE_SHELL=1 ar_format 'fish' '-fish')"
check "hide_shell explicit bash" "" "$(HIDE_SHELL=1 ar_format 'bash' 'bash')"
check "hide_shell ignored ls" "" "$(HIDE_SHELL=1 ar_format 'ls' 'ls -la')"
# The login shell is hidden too, even outside SHELLS and with args on: without
# the prog == SHELL_NAME arm, "nu" would name itself on reconcile while the
# idle prompt stays blank (the HIDE_SHELL gap from the 0.4.0 release).
check "hide_shell login shell outside SHELLS (nu)" "" \
  "$(SHELL_NAME=nu HIDE_SHELL=1 SHOW_PROGRAM_ARGS=1 ar_format 'nu' '-nu')"
# Only shells are hidden: a real program is named exactly as before.
check "hide_shell keeps nvim" "nvim" "$(HIDE_SHELL=1 ar_format 'nvim' 'nvim README.md')"
check "hide_shell keeps program" "htop" "$(HIDE_SHELL=1 SHOW_PROGRAM_ARGS=0 ar_format 'htop' 'htop -d 5')"
# An alias is a label the user asked for by hand, so it outlives the knob.
check "hide_shell keeps alias on a shell" "sh" \
  "$(
    PROGRAM_ALIASES=("fish=sh")
    HIDE_SHELL=1 ar_format 'fish' '-fish'
  )"
# Off (the default) is the old behavior, unchanged.
check "hide_shell off -> shell name" "zsh" "$(HIDE_SHELL=0 ar_format '' '')"
got=$(bash -c 'SHELL_NAME=zsh; . "$1"; ar_format "" ""' _ "$here/../naming.sh")
check "HIDE_SHELL defaults to off" "zsh" "$got"

# ---- default: SHOW_PROGRAM_ARGS defaults to 0 (regular program -> name only) ----
got=$(bash -c 'SHELL_NAME=zsh; . "$1"; ar_format htop "htop -d 5"' _ "$here/../naming.sh")
check "SHOW_PROGRAM_ARGS defaults to name-only" "htop" "$got"

# ---- config arrays: an intentionally-empty override must survive the guard ----
# naming.sh uses `declare -p`, not `${arr+x}` (which reports a zero-element array
# as unset and would silently restore the default list). Source it fresh in a
# subshell with IGNORED_PROGRAMS=() and confirm `ls` is no longer suppressed.
got=$(bash -c 'SHELL_NAME=zsh; SHOW_PROGRAM_ARGS=1; IGNORED_PROGRAMS=(); . "$1"; ar_format ls "ls -la"' _ "$here/../naming.sh")
check "empty IGNORED_PROGRAMS override survives" "ls -la" "$got"

# ---- ar_title_clean: the task a title describes, or nothing ----
# A coding agent keeps its terminal title on the work in progress, which is the
# one thing naming five tabs after their program cannot do: they all read
# "claude". So the title is the better name -- but only while it says something
# about the work, and an agent spends real time saying nothing (it has just
# started, the session was cleared, it is repeating the directory back). Each
# refusal below is one of those, and each is the difference between a tab that
# tells you what it is doing and one that tells you less than "claude" did.
#
# The non-ASCII expectations are written as UTF-8 byte escapes for the same
# reason as the icon glyphs above: bash 3.2 has no $'\uXXXX', and a pasted
# character is precisely what an editor or a copy-paste has silently eaten before.
spinner=$(printf '\xe2\x9c\xb3')                       # U+2733, one of claude's four
uber=$(printf '\xc3\x9cberpr\xc3\xbcfung der Anfrage') # "Überprüfung der Anfrage"

# The strip and the lowercasing both happen in the jq that lifts a title off a
# pane, so ar_title_clean receives the title already stripped and already folded,
# plus the pane's directory folded the same way. This helper stands in for that jq
# -- tr matches jq's ascii_downcase, which leaves a non-ASCII letter alone -- so
# each check below stays one readable line and the argument order the engine
# passes (see ar_tab_name) is written down once.
# The fold here mirrors the engine's, ASCII only, for the same reason it gives.
# shellcheck disable=SC2018,SC2019
_clean() {
  ar_title_clean "$1" "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" \
    "$(printf '%s' "${3:-}" | tr 'A-Z' 'a-z')" "${2:-}"
}
# And the strip itself, one seam over, through the definition the engine shares
# between its two title lifts (def task in AR_JQ_TASK, which the engine concatenates
# after AR_JQ_CLEAN for the `clean` and `lc` it builds on). The spinner an agent parks
# on the front of its title changes with its status, so a title carried through
# with the glyph still on it would rename the tab on every change. The strip lives
# in jq because jq's character classes know Unicode, where a byte-wise strip in
# bash would read the first byte of "Ü" as non-alphanumeric and eat the letter.
# tests/test_reconcile.sh scenarios 28 and 32 assert the same thing end to end, on
# each of the two paths that lift a title off a pane.
# The optional second argument is the brand the agent in the pane stamps on the
# front of its titles, which the engine looks up per pane (see _brand); "" is every
# agent that stamps none, which is what every check written before this one passes.
_task() { printf '%s' "$1" | jq -Rr --arg b "${2:-}" "$AR_JQ_CLEAN$AR_JQ_TASK"'task($b)'; }
# And the lookup, over the real TITLE_BRANDS: the engine joins the array with
# newlines and hands it to each lift as one argument, so a map that comes out
# empty is a strip that never runs.
_brand() { printf '%s\n' "${TITLE_BRANDS[@]}" \
  | jq -Rrs --arg a "$1" "$AR_JQ_CLEAN$AR_JQ_TASK"'brandmap[$a | lc] // ""'; }

check "leading spinner is stripped" "Squash merge command" \
  "$(_task "$spinner Squash merge command")"
# Only the LEADING run of non-alphanumerics goes: punctuation inside the sentence
# is the agent's own wording and stays.
check "punctuation inside a title survives" "Fix: the parser, again" \
  "$(_task 'Fix: the parser, again')"
# A title that is nothing but a spinner strips away to nothing, which is what
# leaves the empty-title refusal below to cover that case whole.
check "a title that is only a spinner strips to nothing" "" "$(_task "$spinner ")"
# Titles are prose in whatever language the user works in, so a non-ASCII letter
# must survive the strip intact -- both behind a spinner and as the first thing in
# the title, which is the byte the naive strip ate.
check "a multibyte title survives the spinner strip" "$uber" "$(_task "$spinner$uber")"
check "a multibyte first letter is not eaten" "$uber" "$(_task "$uber")"

# ---- the brand an agent stamps on its own titles ----

# oh-my-pi puts its brand FIRST and the status glyph second: "PI SP <spinner> SP
# label" while it works, "PI SP > SP label" when the turn is yours, "PI SP ! SP
# label" when it wants you, and "PI: SP label" with its title state off
# (buildTerminalTitleWithState in oh-my-pi's title-generator.ts). The strip above
# only takes a LEADING run of non-alphanumerics, and jq reads the brand as a
# letter, so it stopped on character one and every one of those states reached the
# tab as a different label -- a rename on each status change, spinner and all
# (issue #12). Naming the brand takes it off and leaves the separator to the strip
# that was already there. Built from its UTF-8 bytes for the same reason the
# spinner is: a literal glyph is what an editor eats without saying so.
pi=$(printf '\317\200')             # the brand, U+03C0
braille=$(printf '\342\240\213')   # one of its ten working frames, U+280B

check "the brand and the spinner both go" "Fix the parser bug" \
  "$(_task "$pi $braille Fix the parser bug" "$pi")"
# Every other status has to reduce to the SAME label, because that is the rename
# the tab would otherwise do on each of them. A second working frame is the same
# string shape as the first and would pin nothing; the separators below are not.
check "the your-turn separator reads the same" "Fix the parser bug" \
  "$(_task "$pi > Fix the parser bug" "$pi")"
check "the needs-you separator reads the same" "Fix the parser bug" \
  "$(_task "$pi ! Fix the parser bug" "$pi")"
# With the title state off the separator is a colon against the brand, no space.
check "the title-state-off form reads the same" "Fix the parser bug" \
  "$(_task "$pi: Fix the parser bug" "$pi")"
# A brand with no label behind it is an agent with nothing to report, and it has
# to stay empty so the refusals below hand the tab back to the program name.
check "a brand and separator alone strip to nothing" "" "$(_task "$pi >" "$pi")"
check "a brand alone strips to nothing" "" "$(_task "$pi" "$pi")"
# The brand comes off the FRONT of a title, not out of a word that starts with it.
check "a word starting with the brand is kept" "${pi}calc rewrite" \
  "$(_task "${pi}calc rewrite" "$pi")"
# The brand belongs to the agent that stamps it: the same title from an agent with
# no brand configured is that agent's own wording and stays whole.
check "an unbranded agent keeps the title" "$pi $braille oxc" \
  "$(_task "$pi $braille oxc" "")"
# The brand is compared against the FRONT of the title, so anything in front of it
# has to be gone by then: herdr's own leading whitespace, a control character clean
# turned into a space, or a glyph another agent might park there. Without the strip
# ahead of the compare this whole title reaches the tab, brand and glyph included.
check "a brand behind whitespace still goes" "oxc" "$(_task " $pi $braille oxc" "$pi")"
check "a brand behind a spinner too"        "oxc" "$(_task "$braille $pi oxc" "$pi")"
# An ASCII brand is matched ignoring case, as every other title compare is.
check "an ASCII brand folds case" "x" "$(_task 'PI > x' 'pi')"

# The lookup that picks the brand: keyed by herdr's agent kind, which is "pi" for
# pi and "omp" for oh-my-pi (both are canonical kinds in herdr's src/detect/mod.rs).
check "pi's brand is configured"        "$pi" "$(_brand pi)"
check "oh-my-pi's kind maps to it too"  "$pi" "$(_brand omp)"
check "the kind is folded like the rest" "$pi" "$(_brand OMP)"
check "an agent with no brand gets none" "" "$(_brand claude)"

# End to end over the seam: the reported case. oh-my-pi with no session title yet
# labels itself after the directory it sits in, so once the brand is off, what is
# left is the pane's own cwd -- which the refusals below already knew to hand back
# to the program name. Before the brand strip this reached the tab as
# "PI <spinner> oxc" and no refusal could see it.
check "brand plus spinner plus cwd is refused" "" \
  "$(_clean "$(_task "$pi $braille oxc" "$pi")" omp oxc)"

check "a task title is the answer" "Squash merge command" \
  "$(_clean 'Squash merge command' claude api)"

# The refusals. Each returns "" so naming falls back to the program name.
check "an empty title says nothing" "" "$(_clean '' claude api)"
# A bare number is herdr's own tab label read back off the pane, not a task.
check "a bare number is refused" "" "$(_clean '3' claude api)"
# ... but a number is only a refusal when it is the WHOLE title: "3 files
# changed" is a task, and a prefix test would have thrown it away.
check "a title that merely starts with a digit is kept" "3 files changed" \
  "$(_clean '3 files changed' claude api)"
# The agent naming itself, in the three shapes it does that. Every comparison is
# case-insensitive because the agent chooses the capitalization, not the user.
check "the agent kind is refused" "" "$(_clean 'claude' claude api)"
check "the agent kind, any case" "" "$(_clean 'Claude' claude api)"
# "<kind> code" is refused without being listed, which is what covers an agent
# whose startup title TITLE_IGNORE has never heard of. droid is deliberately not
# in the default list, so this pins the rule rather than the list.
check "the kind followed by code is refused" "" "$(_clean 'Droid Code' droid api)"
check "the pane directory repeated back is refused" "" \
  "$(_clean 'api' claude api)"
check "the pane directory, any case" "" "$(_clean 'API' claude api)"

# A title that is a PATH says where the agent sits, not what it is doing, and an
# agent with nothing to report is exactly where that comes from. The list of
# refusals catches the bare directory name; these catch the path it ends. The last
# case is the one that has to survive: a task description is allowed a slash.
check "an absolute path title is refused"  "" "$(_clean "/home/u/dev/api" claude api)"
# The tilde is DATA here: this is the title an agent set, and expanding it would
# throw away the case under test.
# shellcheck disable=SC2088
check "a tilde path title is refused"      "" "$(_clean "~/dev/api" claude api)"
# The tilde is DATA here: this is the title an agent set, and expanding it would
# throw away the case under test.
# shellcheck disable=SC2088
check "a dot directory title is refused"   "" "$(_clean "~/.config" claude .config)"
check "a task with a slash is kept"        "Fix CI/CD pipeline" \
  "$(_clean "Fix CI/CD pipeline" claude myproj)"
# The tail rule reads a path, not a sentence that ends in one. This description
# ends in exactly the directory it works on, which is the case the whitespace
# guard exists for.
check "a description ending in the dir is kept" "Fix build for services/payments" \
  "$(_clean "Fix build for services/payments" claude payments)"
# The tilde is DATA here: this is the title an agent set, and expanding it would
# throw away the case under test.
# shellcheck disable=SC2088
check "a bare path with no slash left is refused" "" "$(_clean "~/.config" claude .config)"
# A trailing slash names the same directory, and the tail of a string that ends in
# one is empty -- which matches no directory and would walk the whole path past
# every refusal above.
check "a trailing slash does not walk a path past it" "" "$(_clean "/home/u/dev/api/" claude api)"
# The tilde is DATA here: this is the title an agent set, and expanding it would
# throw away the case under test.
# shellcheck disable=SC2088
check "nor does one on a tilde path"                  "" "$(_clean "~/dev/api/" claude api)"
# The tilde is DATA here: this is the title an agent set, and expanding it would
# throw away the case under test.
# shellcheck disable=SC2088
check "nor on a dot directory"                        "" "$(_clean "~/.config/" claude .config)"
# The guard trims ONE trailing slash, so a description is still read as a sentence.
check "a task ending in a slash is still kept" "Fix CI/CD pipeline/" \
  "$(_clean "Fix CI/CD pipeline/" claude myproj)"
# A pane herdr reports no directory for must not turn an empty comparison into a
# refusal: every title would match it and no agent tab would ever get a name.
check "no pane directory refuses nothing" "Squash merge command" \
  "$(_clean 'Squash merge command' claude '')"
# TITLE_IGNORE catches the rest, including titles that name an agent other than
# the one in the pane (an agent launched from a claude pane leaves one behind).
check "a TITLE_IGNORE entry is refused" "" "$(_clean 'New Session' claude api)"
check "a TITLE_IGNORE entry, any case" "" "$(_clean 'UNTITLED' claude api)"
check "another agent's name is still refused" "" "$(_clean 'opencode' claude api)"
# A non-ASCII title must not accidentally MATCH a refusal either: the fold is
# ASCII-only on both sides, exactly as jq's ascii_downcase is.
check "a multibyte title survives" "$uber" "$(_clean "$uber" claude api)"

# TITLE_IGNORE is compared against a title that is already lowercase, so the list
# is lowercased too rather than documented as case-sensitive: README and
# config.example.sh have always promised case-insensitive matching, and before the
# fold an entry a user wrote the way it reads matched nothing at all. Both checks
# need a fresh shell -- the list is guarded with `declare -p` (see
# IGNORED_PROGRAMS above) and folded once per run, so an assignment here would
# come too late for either.
got=$(bash -c 'SHELL_NAME=zsh; TITLE_IGNORE=(); . "$1"; ar_title_clean "New Session" "new session" api claude' _ "$here/../naming.sh")
check "empty TITLE_IGNORE override survives" "New Session" "$got"
got=$(bash -c 'SHELL_NAME=zsh; TITLE_IGNORE=("Ready To Code"); . "$1"; ar_title_clean "Ready to code" "ready to code" api claude' _ "$here/../naming.sh")
check "a mixed-case TITLE_IGNORE entry is folded" "" "$got"

# ---- ar_format with a title: the task IS the label ----
check "a title becomes the label" "Squash merge command" \
  "$(ar_format 'claude' '' 'Squash merge command')"
# The title is taken ahead of PROGRAM_ALIASES on purpose. An alias shortening
# "claude" to "cl" asks for a tidier program name, not for the work to be hidden;
# AGENT_TITLES=0 is the knob for wanting program names, and the pair below pins
# both directions of that.
check "a title beats an alias" "Squash merge command" \
  "$(
    PROGRAM_ALIASES=("claude=cl")
    ar_format 'claude' 'claude' 'Squash merge command'
  )"
check "with no title the alias still wins" "cl" \
  "$(
    PROGRAM_ALIASES=("claude=cl")
    ar_format 'claude' 'claude'
  )"
# Icons annotate the program the tab is running, which the title does not change:
# a task-named claude tab still reads as an agent tab in the tab bar.
check "a title still gets the program's icon" "$g_agent Squash merge command" \
  "$(ICONS_ENABLED=1 ar_format 'claude' '' 'Squash merge command')"

# A title is a sentence and needs more room than a command name, so it is cut at
# MAX_TITLE_LEN (28) rather than MAX_NAME_LEN (20). This one is 24 characters:
# under the command budget it would lose its last word for no reason.
check "a title gets the title budget" "Rebase onto main branch!" \
  "$(ar_format 'claude' '' 'Rebase onto main branch!')"
# Over the budget it is cut back to a word boundary, because "Investigate the
# flaky reconc" reads as a rendering bug where "Investigate the flaky" reads as a
# summary.
check "an over-long title is cut at a word" "Investigate the flaky" \
  "$(ar_format 'claude' '' 'Investigate the flaky reconcile test')"
# The word boundary is only worth it while most of the budget survives: one long
# word after a short one would leave "Fix", which says less than a cut word does.
check "a word boundary that leaves too little is not used" "Fix aaaaaaaaaaaaaaaa" \
  "$(MAX_TITLE_LEN=20 ar_format 'claude' '' 'Fix aaaaaaaaaaaaaaaaaaaaaa')"
# And the word cut belongs to titles alone: a command line is not prose, and
# dropping its last argument would be losing information, not tidying. The budget
# and the boundary here are the ones the rule WOULD fire on, so this fails if the
# cut ever escapes the title path.
check "a command line is still cut mid-word" "psql -c aaaaaaaaaaaaaaaaa bb" \
  "$(MAX_NAME_LEN=28 SHOW_PROGRAM_ARGS=1 ar_format 'psql' 'psql -c aaaaaaaaaaaaaaaaa bbbbbbbbbbbb')"

# The knob and the budget both default on/28 in naming.sh, so a user who has
# never heard of either gets task-named agent tabs. AGENT_TITLES is read by the
# engine (ar_tab_name), which is why ar_format takes the title as an argument
# instead: with the knob off no title is passed and every program rule applies as
# before, pinned by the alias check above and end to end in tests/test_reconcile.sh.
got=$(bash -c '. "$1"; printf %s "$AGENT_TITLES"' _ "$here/../naming.sh")
check "AGENT_TITLES defaults to on" "1" "$got"
got=$(bash -c '. "$1"; printf %s "$MAX_TITLE_LEN"' _ "$here/../naming.sh")
check "MAX_TITLE_LEN defaults to 28" "28" "$got"
# ... and that 28 is MAX_NAME_LEN + 8, not a number of its own: somebody who
# narrows the label budget for a narrow tab bar means the titles too, and a fixed
# default would have left them at 28 while command names shrank to 12.
got=$(bash -c 'MAX_NAME_LEN=12; . "$1"; printf %s "$MAX_TITLE_LEN"' _ "$here/../naming.sh")
check "MAX_TITLE_LEN follows MAX_NAME_LEN" "20" "$got"
# The derivation is only the DEFAULT, so a config that sets both still gets both.
got=$(bash -c 'MAX_NAME_LEN=12; MAX_TITLE_LEN=40; . "$1"; printf %s "$MAX_TITLE_LEN"' _ "$here/../naming.sh")
check "an explicit MAX_TITLE_LEN still wins" "40" "$got"

t_summary

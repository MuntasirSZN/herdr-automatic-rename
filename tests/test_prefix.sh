#!/usr/bin/env bash
# Unit tests for the pure "[N] " prefix helpers in automatic-rename.sh. Sourcing the
# engine defines every function but runs nothing (the ar_main guard), so these
# helpers can be exercised directly.

here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
. "$here/../automatic-rename.sh"

# ---- ar_strip_prefix: inverse of ar_index_prefix; only strips "[digits] " ----
check "strip single digit"          "api"        "$(ar_strip_prefix '[1] api')"
check "strip multi digit"           "web"        "$(ar_strip_prefix '[12] web')"
check "non-numeric bracket kept"    "[wip] foo"  "$(ar_strip_prefix '[wip] foo')"
check "no prefix untouched"         "plain"      "$(ar_strip_prefix 'plain')"
check "malformed bracket left"      "[1]x] foo"  "$(ar_strip_prefix '[1]x] foo')"
check "keeps inner brackets"        "api [2]"    "$(ar_strip_prefix '[1] api [2]')"
# "[3]" alone is the HIDE_SHELL label: a number with an empty base behind it.
check "strip number-only prefix"    ""           "$(ar_strip_prefix '[3]')"
check "empty bracket kept"          "[]"         "$(ar_strip_prefix '[]')"

# ---- ar_index_prefix: the carried-forward "[N] " or "" ----
check "index prefix present"        "[3] "       "$(ar_index_prefix '[3] nvim')"
check "index prefix absent"         ""           "$(ar_index_prefix 'nvim')"
check "index prefix non-numeric"    ""           "$(ar_index_prefix '[wip] x')"
check "index prefix number-only"    "[3] "       "$(ar_index_prefix '[3]')"

# ---- ar_is_placeholder: empty or all-digits ----
ar_is_placeholder "";     check_rc "empty is placeholder"    0 $?
ar_is_placeholder "3";    check_rc "integer is placeholder"  0 $?
ar_is_placeholder "42";   check_rc "42 is placeholder"       0 $?
ar_is_placeholder "nvim"; check_rc "name is not placeholder" 1 $?
ar_is_placeholder "3a";   check_rc "3a is not placeholder"   1 $?

# ---- ar_index_defaults: AUTO_INDEX supplies each scope's default ----
# Unset every knob per case: := only fills an unset/empty var, which is the whole
# mechanism under test. A subshell keeps each case from leaking into the next.
_idx() (
  unset AUTO_INDEX AUTO_INDEX_WORKSPACES AUTO_INDEX_TABS AUTO_INDEX_AGENTS
  eval "$1"
  ar_index_defaults
  printf '%s/%s/%s' "$AUTO_INDEX_WORKSPACES" "$AUTO_INDEX_TABS" "$AUTO_INDEX_AGENTS"
)
check "defaults: all unset -> on"   "1/1/1" "$(_idx ':')"
check "defaults: AUTO_INDEX=0"      "0/0/0" "$(_idx 'AUTO_INDEX=0')"
check "defaults: AUTO_INDEX=1"      "1/1/1" "$(_idx 'AUTO_INDEX=1')"
# Issue #8: numbered tabs, plain workspaces, from one line of config.
check "defaults: ws off alone"      "0/1/1" "$(_idx 'AUTO_INDEX_WORKSPACES=0')"
check "defaults: scope beats master" "1/0/0" "$(_idx 'AUTO_INDEX=0; AUTO_INDEX_WORKSPACES=1')"
check "defaults: agents off alone"  "1/1/0" "$(_idx 'AUTO_INDEX_AGENTS=0')"

# ---- ar_index_on: the single reader of the per-scope toggles ----
AUTO_INDEX_WORKSPACES=1 AUTO_INDEX_TABS=0 AUTO_INDEX_AGENTS=1
ar_index_on workspaces; check_rc "index_on workspaces"     0 $?
ar_index_on tabs;       check_rc "index_on tabs off"       1 $?
ar_index_on agents;     check_rc "index_on agents"         0 $?
ar_index_on nonsense;   check_rc "index_on unknown is off" 1 $?
# Anything but "1" reads as off, matching every other toggle in the plugin.
( AUTO_INDEX_TABS=yes; ar_index_on tabs ); check_rc "index_on non-1 is off" 1 $?

# ---- ar_desired: scope + position -> label under the toggles ----
CLEAR=0; AUTO_INDEX_WORKSPACES=1 AUTO_INDEX_TABS=1 AUTO_INDEX_AGENTS=1
check "desired pos 1"        "[1] api" "$(ar_desired tabs 1 api)"
check "desired pos 9"        "[9] api" "$(ar_desired tabs 9 api)"
check "desired pos 10 bare"  "api"     "$(ar_desired tabs 10 api)"
check "desired pos 0 bare"   "api"     "$(ar_desired workspaces 0 api)"  # hidden row, no keybind
check "desired empty base"   "[1]"     "$(ar_desired tabs 1 '')"   # HIDE_SHELL: number alone
AUTO_INDEX_TABS=0
check "desired index-off"    "api"     "$(ar_desired tabs 1 api)"
check "desired empty, index-off" ""    "$(ar_desired tabs 1 '')"
# The scopes are independent: tabs off does not disarm workspaces or agents.
check "desired ws on while tabs off" "[2] api" "$(ar_desired workspaces 2 api)"
check "desired agents on while tabs off" "[3] claude" "$(ar_desired agents 3 claude)"
# An unknown scope numbers nothing, however the toggles are set.
check "desired unknown scope bare" "api" "$(ar_desired nonsense 1 api)"
AUTO_INDEX_TABS=1; CLEAR=1
check "desired clear strips"  "api"    "$(ar_desired tabs 1 api)"
check "desired clear strips ws" "api"  "$(ar_desired workspaces 1 api)"
CLEAR=0

# ---- ar_unpark_base: recover a base frozen at a park-temp "[N] base <tid>" ----
check "unpark term_ suffix"     "claude"            "$(ar_unpark_base 'claude term_abc' 'claude')"
check "unpark ws:pane suffix"   "claude"            "$(ar_unpark_base 'claude w1:pA' 'claude')"
check "unpark keeps real name"  "claude session"    "$(ar_unpark_base 'claude session' 'claude')"
check "unpark non-park suffix"  "claude foo"        "$(ar_unpark_base 'claude foo' 'claude')"
check "unpark no detected"      "whatever term_x"   "$(ar_unpark_base 'whatever term_x' '')"

# ---- ar_version_lt: gates agent numbering on herdr < 0.7.5 ----
ar_version_lt 0.7.4 0.7.5; check_rc "0.7.4 < 0.7.5"        0 $?
ar_version_lt 0.7.5 0.7.5; check_rc "0.7.5 not < itself"   1 $?
ar_version_lt 0.8.0 0.7.5; check_rc "0.8.0 not < 0.7.5"    1 $?
ar_version_lt 0.7.1 0.7.5; check_rc "0.7.1 < 0.7.5"        0 $?
ar_version_lt 0.10.0 0.7.5; check_rc "numeric not lexical" 1 $?   # 10 > 7
ar_version_lt 1.0 0.7.5;   check_rc "short version 1.0"    1 $?   # missing field = 0
ar_version_lt 0.7 0.7.5;   check_rc "0.7 < 0.7.5"          0 $?
ar_version_lt 0.7.5 0.8;   check_rc "0.7.5 < 0.8"          0 $?
ar_version_lt "" 0.7.5;    check_rc "empty is not less"    1 $?
ar_version_lt junk 0.7.5;  check_rc "junk is not less"     1 $?
ar_version_lt 0.7.5-rc1 0.7.5; check_rc "non-numeric field bails" 1 $?

# ---- ar_herdr_version: parses `herdr --version`, rc 1 when unreadable ----
# $HERDR is whatever binary the engine calls, so a stub script stands in for it.
_vdir=$(mktemp -d "${TMPDIR:-/tmp}/hal-ver.XXXXXX")
_stub() {                        # _stub <name> <shell body>
  printf '#!/usr/bin/env bash\n%s\n' "$2" >"$_vdir/$1"
  chmod +x "$_vdir/$1"
}
_stub plain  'printf "herdr 0.8.0\n"'
_stub extra  'printf "herdr 0.9.2 (abcdef1 2026-08-04)\n"'
_stub suffix 'printf "herdr 0.8.0-rc1\n"'
_stub broken 'exit 1'
_stub silent 'printf "\n"'

check "version parsed"            "0.8.0" "$(HERDR=$_vdir/plain ar_herdr_version)"
check "version with build meta"   "0.9.2" "$(HERDR=$_vdir/extra ar_herdr_version)"
check "version suffix trimmed"    "0.8.0" "$(HERDR=$_vdir/suffix ar_herdr_version)"
( HERDR=$_vdir/broken ar_herdr_version >/dev/null 2>&1 ); check_rc "failed query is rc 1" 1 $?
( HERDR=$_vdir/silent ar_herdr_version >/dev/null 2>&1 ); check_rc "no version field is rc 1" 1 $?

# ---- ar_agent_prefix_ok: only an old-enough, readable version unlocks numbering ----
_stub v074 'printf "herdr 0.7.4\n"'
_stub v075 'printf "herdr 0.7.5\n"'
_stub v080 'printf "herdr 0.8.0\n"'
( HERDR=$_vdir/v074 ar_agent_prefix_ok ); check_rc "0.7.4 allows agent prefix"  0 $?
( HERDR=$_vdir/v075 ar_agent_prefix_ok ); check_rc "0.7.5 forbids agent prefix" 1 $?
( HERDR=$_vdir/v080 ar_agent_prefix_ok ); check_rc "0.8.0 forbids agent prefix" 1 $?
( HERDR=$_vdir/broken ar_agent_prefix_ok ); check_rc "unknown version forbids"  1 $?
rm -rf "$_vdir" 2>/dev/null || true

t_summary

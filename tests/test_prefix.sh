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

# ---- ar_index_prefix: the carried-forward "[N] " or "" ----
check "index prefix present"        "[3] "       "$(ar_index_prefix '[3] nvim')"
check "index prefix absent"         ""           "$(ar_index_prefix 'nvim')"
check "index prefix non-numeric"    ""           "$(ar_index_prefix '[wip] x')"

# ---- ar_is_placeholder: empty or all-digits ----
ar_is_placeholder "";     check_rc "empty is placeholder"    0 $?
ar_is_placeholder "3";    check_rc "integer is placeholder"  0 $?
ar_is_placeholder "42";   check_rc "42 is placeholder"       0 $?
ar_is_placeholder "nvim"; check_rc "name is not placeholder" 1 $?
ar_is_placeholder "3a";   check_rc "3a is not placeholder"   1 $?

# ---- ar_desired: position -> label under the toggles ----
CLEAR=0; AUTO_INDEX=1
check "desired pos 1"        "[1] api" "$(ar_desired 1 api)"
check "desired pos 9"        "[9] api" "$(ar_desired 9 api)"
check "desired pos 10 bare"  "api"     "$(ar_desired 10 api)"
check "desired pos 0 bare"   "api"     "$(ar_desired 0 api)"   # hidden row, no keybind
AUTO_INDEX=0
check "desired index-off"    "api"     "$(ar_desired 1 api)"
AUTO_INDEX=1; CLEAR=1
check "desired clear strips"  "api"    "$(ar_desired 1 api)"
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

#!/usr/bin/env bash
# Tests for TITLE_CONDENSE -- the keyword condensation layered on AGENT_TITLES.
#
# Two halves. The first is pure string in / string out against ar_condense_title,
# the way tests/test_naming.sh tests the rest of naming.sh. The second drives the
# real engine against the fake herdr, because the knob is only worth anything if
# it sits in the title path the reconcile actually walks, and a unit test cannot
# say whether it was wired in at all.
#
# This file is deliberately separate from the released suites rather than folded
# into them: TITLE_CONDENSE defaults to off, so every released expectation still
# describes the shipped behavior, and nothing here has to be re-resolved when
# those files change upstream.

set -o pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh"

SHELL_NAME=zsh
# shellcheck source=naming.sh
. "$here/../naming.sh"

# ---- what gets dropped ----
check "leading verb goes" "screensaver-timeout" \
  "$(ar_condense_title 'Adjust the screensaver timeout')"
check "filler goes throughout" "nightly-ETL-job-drops-rows" \
  "$(ar_condense_title 'Investigate why the nightly ETL job drops rows')"
# The list matches spelling, not part of speech, and the leading position is
# where that bites: "port" is the subject here and is dropped anyway. Taking the
# word out of TITLE_LEAD_VERBS is the answer where a title needs it.
check "a leading list word goes, verb or not" "forwarding-broken" \
  "$(ar_condense_title 'Port forwarding is broken')"
check "and dropping it from the list restores it" "port-forwarding-broken" \
  "$(TITLE_LEAD_VERBS=(review adjust fix); ar_condense_title 'Port forwarding is broken')"
check "a non-leading verb stays" "auth-rewrite-needs-review" \
  "$(ar_condense_title 'The auth rewrite needs review')"

# The order the agent wrote is the order kept: it put the salient words first,
# and re-ranking them by "distinctness" reads worse (see the note on the function).
check "word order is preserved" "RFC7-wording-clarity" \
  "$(ar_condense_title 'Review RFC7 wording for clarity')"

# ---- separators inside the title are word breaks ----
check "slash is a word break" "build-services-payments" \
  "$(ar_condense_title 'Fix build for services/payments')"
check "colon is a word break" "ADR-0028-step-3" \
  "$(ar_condense_title 'ADR 0028: step 3')"

# ---- an agent that badges its own title ----
# opencode writes "OC | <task>". A short all-caps token before a pipe is the
# agent naming itself and spends the budget saying nothing.
check "a badge is dropped" "reviewing-unpushed-commits" \
  "$(ar_condense_title 'OC | Reviewing unpushed commits')"
check "real content keeps its first word" "auth-login-flow" \
  "$(ar_condense_title 'auth | login flow')"

# ---- leading decoration ----
# The engine strips the spinner before ar_title_clean, but a title can lead with
# punctuation the strip does not reach, and a label must not open with one.
check "leading punctuation goes" "parser-rewrite" \
  "$(ar_condense_title '>>> Parser rewrite')"

# ---- casing ----
check "fold spares an identifier" "RFC7-wording-clarity" \
  "$(TITLE_CASE='fold' ar_condense_title 'Review RFC7 wording for clarity')"
check "lower folds it too" "rfc7-wording-clarity" \
  "$(TITLE_CASE='lower' ar_condense_title 'Review RFC7 wording for clarity')"
check "keep leaves the agent's casing" "RFC7-Wording-Clarity" \
  "$(TITLE_CASE='keep' ar_condense_title 'Review RFC7 Wording For Clarity')"
check "an unknown case behaves as fold" "RFC7-wording-clarity" \
  "$(TITLE_CASE='sideways' ar_condense_title 'Review RFC7 wording for clarity')"

# ---- separator ----
check "the separator is configurable" "screensaver timeout" \
  "$(TITLE_WORD_SEPARATOR=' ' ar_condense_title 'Adjust the screensaver timeout')"
check "and is charged to the budget" "nightly_ETL_job_drops" \
  "$(TITLE_WORD_SEPARATOR=_ MAX_TITLE_LEN=24 ar_condense_title 'Investigate why the nightly ETL job drops rows')"

# ---- the budget ----
# Whole words only, and it stops at the first that does not fit rather than
# skipping ahead to a shorter one: a later word reads as a non sequitur beside
# the ones before it.
check "stops at the first word that does not fit" "nightly-ETL-pipeline" \
  "$(MAX_TITLE_LEN=24 ar_condense_title 'Investigate why the nightly ETL pipeline drops duplicate rows')"
check "reserved text comes out of the budget" "nightly-ETL" \
  "$(MAX_TITLE_LEN=24 ar_condense_title 'Investigate why the nightly ETL pipeline drops duplicate rows' '            ')"
# A single word longer than the whole budget is cut rather than dropped, or the
# label would be empty and the sentence would come back instead.
check "an oversized lone word is cut" "supercalifragilisti" \
  "$(MAX_TITLE_LEN=19 ar_condense_title 'supercalifragilisticexpialidocious')"

# The budget is codepoints, not bytes. herdr may launch a plugin with no LC_*,
# where bash counts bytes and would cut a multibyte character in half. Counted as
# bytes this label stops after "funf" (5 bytes + 6 for the next word exceeds 11);
# counted as codepoints both words fit.
#
# The capital survives because the fold is ascii_downcase, which is jq's only
# case operation: its character CLASSES know Unicode, its case conversion does
# not. A non-ASCII capital therefore reaches the label as the agent wrote it.
check "the budget counts codepoints" "$(printf 'f\303\274nf-\303\204pfel')" \
  "$(LC_ALL=C MAX_TITLE_LEN=11 ar_condense_title "$(printf 'F\303\274nf \303\204pfel gefunden')")"

# ---- nothing to say ----
check "an empty title condenses to nothing" "" "$(ar_condense_title '')"
# All filler condenses to nothing, and the caller keeps the sentence rather than
# renaming the tab to an empty string.
check "an all-filler title condenses to nothing" "" "$(ar_condense_title 'to the of')"

# ======================================================================
# End to end: the real engine, the fake herdr, TITLE_CONDENSE=1.
# ======================================================================
ENGINE="$here/../automatic-rename.sh"
MOCK="$here/mocks/herdr"
chmod +x "$MOCK" 2>/dev/null || true

setup() {
  SB=$(mktemp -d "${TMPDIR:-/tmp}/hal-condense.XXXXXX")
  export HERDR_MOCK_DIR="$SB/fixtures"; mkdir -p "$HERDR_MOCK_DIR"
  export HERDR_MOCK_LOG="$SB/renames.log"; : >"$HERDR_MOCK_LOG"
  export HERDR_BIN_PATH="$MOCK"
  export XDG_STATE_HOME="$SB/state"
  export HERDR_AUTOMATIC_RENAME_CONFIG="$SB/none.sh"
  export HERDR_CONFIG_FILE="$SB/herdr.toml"
  printf 'agent_panel_sort = "spaces"\n' >"$HERDR_CONFIG_FILE"
  export HERDR_SOCKET_PATH="$SB/herdr.sock"
  export SHELL_NAME=zsh
  # A suite run from inside a live herdr pane inherits these, and a tab id no
  # fixture describes would reach the real session.
  unset HERDR_TAB_ID HERDR_PLUGIN_CONTEXT_JSON
  unset HERDR_MOCK_VERSION HERDR_MOCK_NO_VERSION HIDE_SHELL
  unset AUTO_INDEX_WORKSPACES AUTO_INDEX_TABS AUTO_INDEX_AGENTS
}
fixture() { cat >"$HERDR_MOCK_DIR/$1"; }
run_event() { /usr/bin/env bash "$ENGINE" "$1"; }
log() { cat "$HERDR_MOCK_LOG"; }
teardown() { rm -rf "$SB" 2>/dev/null || true; }

# ----------------------------------------------------------------------
# t1 is the ordinary case, spinner glyph included: the engine strips it, the
#    condensation gets prose, the tab gets keywords.
# t2 is a refusal. "Claude Code" never reaches the condensation at all, and the
#    tab falls back to the program name, exactly as with the knob off.
# t3 ships no procinfo fixture, so the mock serves "{}" and no program name can
#    be computed. A label here can only have come through the title path, which
#    is what pins the wiring rather than the function.
# ----------------------------------------------------------------------
setup
export NAME_TABS=1 AUTO_INDEX=0 TITLE_CONDENSE=1
fixture workspaces.json <<'JSON'
{"result":{"workspaces":[{"workspace_id":"w1","label":"api"}]}}
JSON
fixture tabs_w1.json <<'JSON'
{"result":{"tabs":[
  {"tab_id":"w1:t1","label":"1","pane_count":1,"focused":true},
  {"tab_id":"w1:t2","label":"2","pane_count":1,"focused":false},
  {"tab_id":"w1:t3","label":"3","pane_count":1,"focused":false}
]}}
JSON
fixture panes.json <<'JSON'
{"result":{"panes":[
  {"pane_id":"p1","tab_id":"w1:t1","focused":true,"agent":"claude","agent_status":"working",
   "terminal_title_stripped":"✳ Squash merge command","foreground_cwd":"/home/u/dev/api"},
  {"pane_id":"p2","tab_id":"w1:t2","focused":false,"agent":"claude","agent_status":"idle",
   "terminal_title_stripped":"Claude Code","foreground_cwd":"/home/u/dev/api"},
  {"pane_id":"p3","tab_id":"w1:t3","focused":false,"agent":"claude","agent_status":"working",
   "terminal_title_stripped":"Investigate why the nightly ETL job drops rows",
   "foreground_cwd":"/home/u/dev/api"}
]}}
JSON
fixture procinfo_p1.json <<'JSON'
{"result":{"process_info":{"foreground_process_group_id":1,
  "foreground_processes":[{"pid":1,"argv0":"claude","cmdline":"claude"}]}}}
JSON
fixture procinfo_p2.json <<'JSON'
{"result":{"process_info":{"foreground_process_group_id":2,
  "foreground_processes":[{"pid":2,"argv0":"claude","cmdline":"claude"}]}}}
JSON
out=$(run_event tab.created >/dev/null 2>&1; log)
check_contains "the title is condensed onto the tab" "$out" "tab rename w1:t1 squash-merge-command"
check_absent   "the sentence never reaches herdr"    "$out" "Squash merge command"
check_contains "a refused title still falls back"    "$out" "tab rename w1:t2 claude"
check_absent   "and is not condensed either"         "$out" "claude-code"
check_contains "a title needs no process lookup"     "$out" "tab rename w1:t3 nightly-ETL-job-drops-rows"
teardown

# ----------------------------------------------------------------------
# The knob is off unless asked for: the same fixtures, no TITLE_CONDENSE, and
# the label is the sentence the released plugin has always written.
# ----------------------------------------------------------------------
setup
export NAME_TABS=1 AUTO_INDEX=0
unset TITLE_CONDENSE
fixture workspaces.json <<'JSON'
{"result":{"workspaces":[{"workspace_id":"w1","label":"api"}]}}
JSON
fixture tabs_w1.json <<'JSON'
{"result":{"tabs":[{"tab_id":"w1:t1","label":"1","pane_count":1,"focused":true}]}}
JSON
fixture panes.json <<'JSON'
{"result":{"panes":[
  {"pane_id":"p1","tab_id":"w1:t1","focused":true,"agent":"claude","agent_status":"working",
   "terminal_title_stripped":"Squash merge command","foreground_cwd":"/home/u/dev/api"}
]}}
JSON
out=$(run_event tab.created >/dev/null 2>&1; log)
check_contains "off by default: the sentence survives" "$out" "tab rename w1:t1 Squash merge command"
teardown

# ----------------------------------------------------------------------
# The glyph and its space are prepended before ar_format truncates, so they come
# out of the same budget. Unreserved, a full-length label loses its tail to make
# room for them. MAX_NAME_LEN=20 puts MAX_TITLE_LEN at 28.
# ----------------------------------------------------------------------
setup
export NAME_TABS=1 AUTO_INDEX=0 TITLE_CONDENSE=1 ICONS_ENABLED=1
fixture workspaces.json <<'JSON'
{"result":{"workspaces":[{"workspace_id":"w1","label":"api"}]}}
JSON
fixture tabs_w1.json <<'JSON'
{"result":{"tabs":[{"tab_id":"w1:t1","label":"1","pane_count":1,"focused":true}]}}
JSON
fixture panes.json <<'JSON'
{"result":{"panes":[
  {"pane_id":"p1","tab_id":"w1:t1","focused":true,"agent":"claude","agent_status":"working",
   "terminal_title_stripped":"Investigate why the nightly ETL job drops rows",
   "foreground_cwd":"/home/u/dev/api"}
]}}
JSON
out=$(run_event tab.created >/dev/null 2>&1; log)
# Two fewer characters than the glyphless label above: "drops-rows" no longer fits.
check_contains "the glyph is reserved out of the budget" "$out" "nightly-ETL-job-drops"
check_absent   "so nothing is cut off the end"           "$out" "drops-row "
teardown

t_summary

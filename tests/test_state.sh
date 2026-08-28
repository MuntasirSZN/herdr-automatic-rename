#!/usr/bin/env bash
# Unit tests for the JSON state store and the manual-rename opt-out state
# machine (ar_name_eligible). State lives under $XDG_STATE_HOME, which we point
# at a throwaway dir BEFORE sourcing the engine so STATE_DIR/STATE_FILE resolve
# there and the real state is never touched.

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh"

SB=$(mktemp -d "${TMPDIR:-/tmp}/hal-state.XXXXXX")
export XDG_STATE_HOME="$SB/xdg"
# shellcheck source=automatic-rename.sh
. "$here/../automatic-rename.sh"
mkdir -p "$STATE_DIR"

# ---- ar_state_set / get / del ----
ar_state_set t1 nvim true
check "get auto after set"     "nvim" "$(ar_state_get t1 auto)"
check "get enabled after set"  "true" "$(ar_state_get t1 enabled)"
ar_state_set t1 claude false
check "overwrite auto"         "claude" "$(ar_state_get t1 auto)"
check "overwrite enabled"      "false"  "$(ar_state_get t1 enabled)"
ar_state_del t1
check "get after del"          "" "$(ar_state_get t1 auto)"

# ---- ar_state_prune: keep only listed tab ids ----
ar_state_set a x true
ar_state_set b y true
ar_state_set c z true
ar_state_prune a c
check "pruned entry gone"      "" "$(ar_state_get b auto)"
check "kept entry a"           "x" "$(ar_state_get a auto)"
check "kept entry c"           "z" "$(ar_state_get c auto)"

# ======================================================================
# ar_name_eligible state machine. rc 0 = eligible for auto-naming, 1 = leave it.
# ======================================================================
reset_state() { rm -f "$STATE_FILE"; }

# First sight of a placeholder label -> adopt (eligible), no state written yet.
reset_state
ar_name_eligible tX "3"; check_rc "first-seen placeholder adopts" 0 $?

# First sight of a hand-picked label -> opt out and remember it.
reset_state
ar_name_eligible tX "myproject"; check_rc "first-seen named opts out" 1 $?
check "opt-out recorded"       "false" "$(ar_state_get tX enabled)"

# We own it (enabled=true) and the base still matches -> keep updating.
reset_state
ar_state_set tX nvim true
ar_name_eligible tX "nvim"; check_rc "owned + unchanged stays eligible" 0 $?

# We own it but the base changed under us (user renamed) -> opt out.
reset_state
ar_state_set tX nvim true
ar_name_eligible tX "renamed-by-hand"; check_rc "owned + user-renamed opts out" 1 $?
check "owned->opt-out recorded" "false" "$(ar_state_get tX enabled)"

# We own it and the user cleared the label -> re-adopt.
reset_state
ar_state_set tX nvim true
ar_name_eligible tX ""; check_rc "owned + cleared re-adopts" 0 $?

# A HIDE_SHELL tab is owned with an EMPTY auto name. herdr handing its generated
# number back to such a label-less tab is not a hand rename -> stay eligible, so
# the tab is still named the moment a real program starts.
reset_state
ar_state_set tX "" true
ar_name_eligible tX "3"; check_rc "owned + empty auto keeps a number" 0 $?
ar_name_eligible tX "";  check_rc "owned + empty auto keeps empty"    0 $?
ar_name_eligible tX "notes"; check_rc "owned + empty auto still opts out on a name" 1 $?

# Opted out, still non-empty -> leave it.
reset_state
ar_state_set tX "" false
ar_name_eligible tX "3000"; check_rc "opted-out numeric stays out" 1 $?

# Opted out, but the label was cleared -> re-adopt.
reset_state
ar_state_set tX "" false
ar_name_eligible tX ""; check_rc "opted-out + cleared re-adopts" 0 $?

# reset action force: AR_FORCE_TAB wins over any opt-out.
reset_state
ar_state_set tX "" false
AR_FORCE_TAB=tX ar_name_eligible tX "still-named"; check_rc "force re-adopts" 0 $?

# ======================================================================
# ar_state_read: a file jq cannot parse is read as an empty one.
#
# Every writer starts from the file that is already there, so one jq could not
# read froze the whole store: the tab lost its ownership record, read as
# hand-renamed on the next pass, opted out, and the reset action could not bring
# it back either, because re-adopting it is another write. Naming was dead for
# the session with nothing said.
# ======================================================================
reset_state
check "a missing state file reads as empty" "{}" "$(ar_state_read)"

printf '{"t1": {"auto": "nvim", "enab' >"$STATE_FILE"
check "a truncated state file reads as empty" "{}" "$(ar_state_read)"

# The regression: with the file unparseable, a write has to land anyway.
ar_state_set t1 nvim true
check_rc "a truncated state file heals on write" 0 $?
check "and the entry reads back"  "nvim" "$(ar_state_get t1 auto)"
check "healthy state is not discarded" "nvim" "$(ar_state_read | jq -r '.t1.auto')"

# A valid JSON array parses but is not a state store, and assigning a key into
# one is not a write this file can come back from.
printf '["t1"]' >"$STATE_FILE"
check "a JSON array reads as empty" "{}" "$(ar_state_read)"

# jq reads top-level values as a STREAM, so a file holding two objects parses and
# would come back as the pair. The writers would then update each document and
# write both out, leaving the file multi-document for good, and ar_state_get would
# emit one value per document into a variable no comparison can match.
printf '{"t1": {"auto": "nvim", "enabled": true}}\n{"t2": {"auto": "vim", "enabled": true}}\n' >"$STATE_FILE"
check "two documents read as empty" "{}" "$(ar_state_read)"
ar_state_set t3 lazygit true
check_rc "and a write over them lands"  0 $?
check "leaving exactly one document"    "1" "$(jq -s 'length' "$STATE_FILE" 2>/dev/null)"
check "with only the new entry in it"   "lazygit" "$(ar_state_get t3 auto)"
check "and nothing from the stream"     "" "$(ar_state_get t1 auto)"

printf '{"a": {"auto": "x", "enab' >"$STATE_FILE"
ar_state_prune a
check "prune leaves a file that parses" "object" "$(jq -r 'type' "$STATE_FILE" 2>/dev/null)"

reset_state

# ---- a claim that could not be written is not a claim ----
# Ownership IS this file, so a write that fails and says nothing let the reset
# action report a re-adoption for a tab the next pass would find unowned and opt
# straight back out. An unwritable state directory is how that arrives in the
# field (a full disk is the other); the reconcile cannot be driven this way,
# because the same permissions stop it taking its lock, so the rule is pinned
# here on the two functions that carry it.
ar_state_set tW nvim true
AR_STATE_ENABLED=$(ar_state_get tW enabled)
AR_STATE_AUTO=$(ar_state_get tW auto)
AR_FORCE_TAB=tW AR_FORCE_ADOPTED="" ar_state_claim tW nvim 1
check_rc "an unchanged claim needs no write" 0 $?

chmod 555 "$STATE_DIR"
ar_state_set tZ nvim true
check_rc "a write into an unwritable dir fails" 1 $?
AR_STATE_ENABLED="" AR_STATE_AUTO="" ar_state_claim tZ nvim 1
check_rc "and the claim fails with it" 1 $?
AR_FORCE_ADOPTED=""
AR_FORCE_TAB=tZ AR_STATE_ENABLED="" AR_STATE_AUTO="" ar_state_claim tZ nvim 1 || true
check "a failed claim never reports an adoption" "" "$AR_FORCE_ADOPTED"
chmod 755 "$STATE_DIR"

AR_FORCE_ADOPTED=""
AR_FORCE_TAB=tZ AR_STATE_ENABLED="" AR_STATE_AUTO="" ar_state_claim tZ nvim 1
check "a claim that landed reports one" "1" "$AR_FORCE_ADOPTED"
check "and the tab is owned"            "nvim true" \
  "$(ar_state_get tZ auto) $(ar_state_get tZ enabled)"

# ======================================================================
# A state file we could not READ is left alone, not overwritten as empty.
#
# Every writer starts from ar_state_read, and a read that failed used to be
# indistinguishable from a file with nothing in it: the writer began at {} and
# moved a one-key file over the top, so every other tab's record went. Each of
# those tabs then carries a label state knows nothing about, which is what a
# name typed by hand looks like, so each one opts itself out. Unparseable is
# still healed -- only a read that failed is refused.
#
# The unreadable file is made with chmod, so the block is skipped wherever that
# does not actually take: as root, and under a sandbox or a filesystem that
# ignores the mode. Asserting on a file we can still read would fail for a
# reason that has nothing to do with the code.
# ======================================================================
printf '{"tR":{"auto":"nvim","enabled":true},"tS":{"auto":"vim","enabled":true}}' \
  >"$STATE_FILE"
chmod 000 "$STATE_FILE" 2>/dev/null
if ! cat "$STATE_FILE" >/dev/null 2>&1; then
  ar_state_read >/dev/null
  check_rc "an unreadable state file is not an empty store" 1 $?
  ar_state_set tT emacs true
  check_rc "and a write onto it is refused"                 1 $?
  chmod 644 "$STATE_FILE"
  check "so the records it held survive" "nvim vim" \
    "$(ar_state_get tR auto) $(ar_state_get tS auto)"
fi
chmod 644 "$STATE_FILE" 2>/dev/null       # readable again whether or not it ran

# A readable file holding only a newline is CORRUPT, not unreadable, so it heals
# like any other shape jq cannot use. It reads back empty, because command
# substitution strips trailing newlines, and it still has a byte in it -- so
# judging a read error by size rather than by cat's exit status refuses to heal
# it and freezes the store, which is the bug this whole path exists to fix.
# `echo > state.json` during a hand recovery makes one.
printf '\n' >"$STATE_FILE"
check "a blank state file reads as empty"  "{}" "$(ar_state_read)"
ar_state_set tU emacs true
check_rc "and a write onto it lands"       0 $?
check "so the store is usable again"       "emacs" "$(ar_state_get tU auto)"

# A file that went away between the test and the read is refused once, which the
# next pass reads as a missing store.
rm -f "$STATE_FILE"
check "a missing state file still reads as empty" "{}" "$(ar_state_read)"

# ======================================================================
# ar_state_fields: the one read behind both eligibility machines.
# ======================================================================
reset_state
ar_state_set t9 "api" true "web"
IFS=$AR_ROW_SEP read -r _en _au _ws <<< "$(ar_state_fields t9)"
check "fields: enabled" "true" "$_en"
check "fields: auto"    "api"  "$_au"
check "fields: ws"      "web"  "$_ws"
# A record written without a workspace has no ws key, and the field still has to
# arrive EMPTY rather than shifting the ones before it.
ar_state_set t9 "api" true
IFS=$AR_ROW_SEP read -r _en _au _ws <<< "$(ar_state_fields t9)"
check "fields: absent ws is empty" "" "$_ws"
check "fields: auto unshifted"     "api" "$_au"
# An opted-out tab reads back as false, not as the empty string `//` would give:
# empty is "never seen", which re-adopts a name somebody typed.
ar_state_set t9 "" false
IFS=$AR_ROW_SEP read -r _en _au _ws <<< "$(ar_state_fields t9)"
check "fields: false is not empty" "false" "$_en"

# Every caller must name a variable for EVERY field. bash gives the last variable
# the rest of the line INCLUDING the delimiters, so a caller reading two of three
# fields gets "api<SEP>" where it expects "api" -- and the comparison that keeps a
# workspace tracked its directory can then never be true again.
reset_state
ar_state_set "ws:w1" "project-a" true
check_rc "a tracked workspace stays tracked across a cd" 0 \
  "$(ar_ws_track_eligible w1 "project-a" "project-b"; echo $?)"

rm -rf "$SB" 2>/dev/null || true
t_summary

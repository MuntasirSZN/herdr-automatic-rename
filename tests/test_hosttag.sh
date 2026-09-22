#!/usr/bin/env bash
# Tests for the HOST_PREFIX host tag: the three review findings on PR #24, each
# pinned as the behavior a fix has to land on.
#
# Unit half: sourcing the engine defines ar_tab_strip_prefix without running
# anything (the ar_main guard), so the strip is checked strings in, strings out.
# Integration half: the real engine against tests/mocks/herdr, mirroring the
# harnesses of tests/test_prefix.sh and tests/test_reconcile.sh.
#
# The tag is whatever ar_host_tag derives on the machine running the suite
# (short uname -n + the default separator), computed here the same way, because
# the engine derives it live and the label fixtures have to carry the same
# spelling.

set -o pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh"
# shellcheck source=automatic-rename.sh
. "$here/../automatic-rename.sh"

TAG="$(uname -n 2>/dev/null)"; TAG="${TAG%%.*}: "

# ======================================================================
# Review finding: the through-the-marker cut must not reach a bracketed
# number in the middle of a hand name. The cut exists for an unspellable
# tag ahead of the plugin's own "[N] " marker, but its pattern let any
# text ahead of any bracket fire it, so "notes [2] draft" lost everything
# before the bracket -- while the knob was on, and under --clear on a
# session that never set it.
# ======================================================================
unset CLEAR
HOST_PREFIX=1
check "strip: exact tag + marker peels" "api" "$(ar_tab_strip_prefix "${TAG}[1] api" 1)"
check "strip: mid-label bracket kept, knob on" "notes [2] draft" "$(ar_tab_strip_prefix 'notes [2] draft' 1)"
unset HOST_PREFIX
CLEAR=1
check "strip: mid-label bracket kept under clear" "notes [2] draft" "$(ar_tab_strip_prefix 'notes [2] draft' 1)"
unset CLEAR

# ======================================================================
# Integration harness (see tests/test_reconcile.sh for the shape).
# ======================================================================
ENGINE="$here/../automatic-rename.sh"
MOCK="$here/mocks/herdr"
chmod +x "$MOCK" 2>/dev/null || true

setup() {
  SB=$(mktemp -d "${TMPDIR:-/tmp}/hal-tag.XXXXXX")
  export HERDR_MOCK_DIR="$SB/fixtures"; mkdir -p "$HERDR_MOCK_DIR"
  export HERDR_MOCK_LOG="$SB/renames.log"; : >"$HERDR_MOCK_LOG"; rm -f "$HERDR_MOCK_LOG.tabget"
  export HERDR_BIN_PATH="$MOCK"
  export XDG_STATE_HOME="$SB/state"
  export HERDR_AUTOMATIC_RENAME_CONFIG="$SB/none.sh"   # absent -> env toggles win
  export HERDR_CONFIG_FILE="$SB/herdr.toml"
  printf 'agent_panel_sort = "spaces"\n' >"$HERDR_CONFIG_FILE"
  export HERDR_SOCKET_PATH="$SB/herdr.sock"   # keeps herdr state reads (session.json) in the sandbox
  export SHELL_NAME=zsh
  export NAME_TABS=1 AUTO_INDEX=1 TAB_CONTEXT=0
  unset HOST_PREFIX HOST_PREFIX_SEP HOST_PREFIX_STRIP CLEAR   # per-scenario opt-in
  unset HIDE_SHELL
  unset AUTO_INDEX_WORKSPACES AUTO_INDEX_TABS AUTO_INDEX_AGENTS
  unset HERDR_TAB_ID HERDR_PANE_ID HERDR_PLUGIN_CONTEXT_JSON
  mkdir -p "$XDG_STATE_HOME/herdr-automatic-rename"
  export STATE="$XDG_STATE_HOME/herdr-automatic-rename/state.json"
}
fixture() { cat >"$HERDR_MOCK_DIR/$1"; }   # fixture <name>  (JSON on stdin)
run_engine() { /usr/bin/env bash "$ENGINE" "$@"; }
log() { cat "$HERDR_MOCK_LOG"; }
teardown() { rm -rf "$SB" 2>/dev/null || true; }

# ======================================================================
# Review finding: the fast path froze a tagged tab when the knob went
# off. The tag was written while HOST_PREFIX=1; the next preexec runs
# with it off. The carry guard tested the knob, so core kept the tag,
# slabel stopped matching the stored auto, and ar_name_eligible wrote
# the user-renamed opt-out: the tab wore the stale tag until reset. The
# tag must come off core either way, with only the carry for want=
# waiting on the knob.
# ======================================================================
setup
printf '{"t1":{"auto":"nvim","enabled":true}}\n' >"$STATE"
export HERDR_TAB_ID=t1 HERDR_PANE_ID=p1
fixture tab_t1.json <<JSON
{"result":{"tab":{"tab_id":"t1","label":"${TAG}[1] nvim"}}}
JSON
run_engine preexec "nvim README.md"
check "toggle off: tag comes off in the fast path" "tab rename t1 [1] nvim" "$(log)"
check "toggle off: tab not opted out" "true" "$(jq -r '.t1.enabled' "$STATE" 2>/dev/null)"
teardown

# ======================================================================
# Review finding: with the feature never on, a hand-typed host-looking
# name is not ours to take off. The user hand-renamed an owned tab to
# "<host>: fish"; ar_tab_strip_prefix peeled the tag with the knob off,
# the base matched the stored auto, and the reconcile renamed the tab to
# "fish". A tag nobody wrote must not be stripped: the label is the
# user's, and the mismatch with auto is the hand rename it records.
# AUTO_INDEX=0 keeps numbering out of the picture, so the assertion is
# exactly "no rename issued".
# ======================================================================
setup
export AUTO_INDEX=0
printf '{"w1:t1":{"auto":"fish","enabled":true}}\n' >"$STATE"
fixture workspaces.json <<'JSON'
{"result":{"workspaces":[{"workspace_id":"w1","label":"api"}]}}
JSON
fixture tabs_w1.json <<JSON
{"result":{"tabs":[{"tab_id":"w1:t1","label":"${TAG}fish","pane_count":1,"focused":true}]}}
JSON
fixture panes.json <<'JSON'
{"result":{"panes":[{"pane_id":"p1","tab_id":"w1:t1","focused":true}]}}
JSON
run_engine tab.focused
check "hand host name kept, feature never on" "" "$(log)"
teardown

t_summary

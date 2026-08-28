#!/usr/bin/env bash
# Integration tests for the CONTEXT half of a label: the directory a pane sits
# in, the branch it has checked out, and the machine it reached over ssh -- plus
# the transcript an agent names its own session in. Same fake-herdr harness as
# tests/test_reconcile.sh, kept in its own file because these scenarios all turn
# on what a pane's DIRECTORY says rather than on numbering or ownership.

set -o pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh"

ENGINE="$here/../automatic-rename.sh"
MOCK="$here/mocks/herdr"
chmod +x "$MOCK" 2>/dev/null || true

SEP=$(printf ' \342\200\272 ')   # the CONTEXT_SEP default, U+203A

setup() {
  SB=$(mktemp -d "${TMPDIR:-/tmp}/hal-ctx.XXXXXX")
  export HERDR_MOCK_DIR="$SB/fixtures"; mkdir -p "$HERDR_MOCK_DIR"
  export HERDR_MOCK_LOG="$SB/renames.log"; : >"$HERDR_MOCK_LOG"
  export HERDR_BIN_PATH="$MOCK"
  export XDG_STATE_HOME="$SB/state"
  export HERDR_AUTOMATIC_RENAME_CONFIG="$SB/none.sh"
  export HERDR_CONFIG_FILE="$SB/herdr.toml"
  export HERDR_SOCKET_PATH="$SB/herdr.sock"
  export SHELL_NAME=zsh
  export NAME_TABS=1 AUTO_INDEX=0
  unset HERDR_MOCK_VERSION HERDR_MOCK_NO_VERSION HERDR_MOCK_FAIL_RENAME
  unset HIDE_SHELL AUTO_INDEX_WORKSPACES AUTO_INDEX_TABS AUTO_INDEX_AGENTS
  unset AGENT_TITLES SHOW_PROGRAM_ARGS TAB_CONTEXT MAX_CONTEXT_LEN
  unset SHOW_BRANCH MAX_BRANCH_LEN AGENT_TRANSCRIPT CLAUDE_CONFIG_DIR
  unset HERDR_TAB_ID HERDR_PANE_ID HERDR_PLUGIN_CONTEXT_JSON
}
fixture() { cat >"$HERDR_MOCK_DIR/$1"; }
run_event() { /usr/bin/env bash "$ENGINE" "$1"; }
log() { cat "$HERDR_MOCK_LOG"; }
teardown() { rm -rf "$SB" 2>/dev/null || true; }

# ======================================================================
# Scenario 1: the directory names the tab, and the workspace name does not
#   repeat itself.
#   t1 sits in a directory of its own      -> "web › nvim"
#   t2 sits in the workspace's directory   -> "nvim" alone
#   t3 sits at $HOME                       -> "zsh" alone (home says nothing)
# ======================================================================
setup
fixture snapshot.json <<'JSON'
{"result":{"snapshot":{
  "workspaces":[{"workspace_id":"w1","label":"api"}],
  "tabs":[
    {"tab_id":"w1:t1","label":"1","pane_count":1,"focused":true,"workspace_id":"w1"},
    {"tab_id":"w1:t2","label":"2","pane_count":1,"focused":false,"workspace_id":"w1"},
    {"tab_id":"w1:t3","label":"3","pane_count":1,"focused":false,"workspace_id":"w1"}
  ],
  "panes":[
    {"pane_id":"p1","tab_id":"w1:t1","focused":true,"cwd":"/home/u/dev/web"},
    {"pane_id":"p2","tab_id":"w1:t2","focused":true,"cwd":"/home/u/dev/api"},
    {"pane_id":"p3","tab_id":"w1:t3","focused":true,"cwd":"/home/u"}
  ],
  "layouts":[
    {"tab_id":"w1:t1","focused_pane_id":"p1"},
    {"tab_id":"w1:t2","focused_pane_id":"p2"},
    {"tab_id":"w1:t3","focused_pane_id":"p3"}
  ]
}}}
JSON
fixture procinfo_p1.json <<'JSON'
{"result":{"process_info":{"foreground_process_group_id":100,
  "foreground_processes":[{"pid":100,"argv0":"nvim","cmdline":"nvim README.md"}]}}}
JSON
fixture procinfo_p2.json <<'JSON'
{"result":{"process_info":{"foreground_process_group_id":200,
  "foreground_processes":[{"pid":200,"argv0":"nvim","cmdline":"nvim main.go"}]}}}
JSON
fixture procinfo_p3.json <<'JSON'
{"result":{"process_info":{"foreground_process_group_id":300,
  "foreground_processes":[{"pid":300,"argv0":"-zsh","cmdline":"-zsh"}]}}}
JSON
HOME=/home/u run_event tab.focused
out=$(log)
check_contains "the pane's directory leads the label" "$out" "tab rename w1:t1 web${SEP}nvim"
check_contains "the workspace's own directory is not repeated" "$out" "tab rename w1:t2 nvim"
check_contains "the home directory says nothing" "$out" "tab rename w1:t3 zsh"
teardown

# ======================================================================
# Scenario 2: TAB_CONTEXT=0 names by the program alone, as before the context
#   existed. Same fixtures as Scenario 1's t1.
# ======================================================================
setup
export TAB_CONTEXT=0
fixture snapshot.json <<'JSON'
{"result":{"snapshot":{
  "workspaces":[{"workspace_id":"w1","label":"api"}],
  "tabs":[{"tab_id":"w1:t1","label":"1","pane_count":1,"focused":true,"workspace_id":"w1"}],
  "panes":[{"pane_id":"p1","tab_id":"w1:t1","focused":true,"cwd":"/home/u/dev/web"}],
  "layouts":[{"tab_id":"w1:t1","focused_pane_id":"p1"}]
}}}
JSON
fixture procinfo_p1.json <<'JSON'
{"result":{"process_info":{"foreground_process_group_id":100,
  "foreground_processes":[{"pid":100,"argv0":"nvim","cmdline":"nvim README.md"}]}}}
JSON
HOME=/home/u run_event tab.focused
out=$(log)
check_contains "TAB_CONTEXT=0 names by the program alone" "$out" "tab rename w1:t1 nvim"
check_absent   "TAB_CONTEXT=0 adds no separator"          "$out" "$SEP"
teardown

# ======================================================================
# Scenario 3: the per-list fallback path (no snapshot.json) carries the context
#   too. The lists are what an older herdr answers with, and a tab named there
#   must read the same as one named from a snapshot.
# ======================================================================
setup
fixture workspaces.json <<'JSON'
{"result":{"workspaces":[{"workspace_id":"w1","label":"api"}]}}
JSON
fixture tabs_w1.json <<'JSON'
{"result":{"tabs":[{"tab_id":"w1:t1","label":"1","pane_count":1,"focused":true}]}}
JSON
fixture panes.json <<'JSON'
{"result":{"panes":[{"pane_id":"p1","tab_id":"w1:t1","focused":true,"cwd":"/home/u/dev/web"}]}}
JSON
fixture procinfo_p1.json <<'JSON'
{"result":{"process_info":{"foreground_process_group_id":100,
  "foreground_processes":[{"pid":100,"argv0":"nvim","cmdline":"nvim README.md"}]}}}
JSON
HOME=/home/u run_event tab.focused
out=$(log)
check_contains "the list path names the context too" "$out" "tab rename w1:t1 web${SEP}nvim"
teardown

# ======================================================================
# Scenario 4: the shell hook. It renames the tab on every command, so it has to
#   reach the SAME label the reconcile does -- a hook that dropped the context
#   would flip the tab on every prompt, which is the flicker the fast path
#   exists to avoid.
#
#   Its directory is the shell's own $PWD (the hook backgrounds the engine from
#   the pane), and the workspace name it dedupes against is the one the last
#   reconcile recorded on the tab.
# ======================================================================
setup
export HERDR_TAB_ID=t1 HERDR_PANE_ID=p1
mkdir -p "$XDG_STATE_HOME/herdr-automatic-rename" "$SB/dev/web" "$SB/dev/api"
printf '{"t1":{"auto":"zsh","enabled":true,"ws":"api"}}\n' \
  >"$XDG_STATE_HOME/herdr-automatic-rename/state.json"
fixture tab_t1.json <<'JSON'
{"result":{"tab":{"tab_id":"t1","label":"zsh"}}}
JSON
( cd "$SB/dev/web" && /usr/bin/env bash "$ENGINE" precmd zsh )
out=$(log)
check_contains "the hook names the context from \$PWD" "$out" "tab rename t1 web${SEP}zsh"
: >"$HERDR_MOCK_LOG"
( cd "$SB/dev/api" && /usr/bin/env bash "$ENGINE" precmd zsh )
out=$(log)
check_absent "the hook dedupes the workspace it was told" "$out" "api${SEP}"
teardown

# ======================================================================
# Scenario 5: the workspace a tab dedupes against is recorded on the tab, so the
#   hook can read it back without a herdr call of its own.
# ======================================================================
setup
fixture snapshot.json <<'JSON'
{"result":{"snapshot":{
  "workspaces":[{"workspace_id":"w1","label":"[1] api"}],
  "tabs":[{"tab_id":"w1:t1","label":"1","pane_count":1,"focused":true,"workspace_id":"w1"}],
  "panes":[{"pane_id":"p1","tab_id":"w1:t1","focused":true,"cwd":"/home/u/dev/web"}],
  "layouts":[{"tab_id":"w1:t1","focused_pane_id":"p1"}]
}}}
JSON
fixture procinfo_p1.json <<'JSON'
{"result":{"process_info":{"foreground_process_group_id":100,
  "foreground_processes":[{"pid":100,"argv0":"nvim","cmdline":"nvim README.md"}]}}}
JSON
HOME=/home/u run_event tab.focused
got=$(jq -r '."w1:t1".ws' "$XDG_STATE_HOME/herdr-automatic-rename/state.json" 2>/dev/null)
# Recorded WITHOUT the numbering prefix: it is compared against a directory name,
# and "[1] api" is not one.
check "the workspace base is recorded on the tab" "api" "$got"
teardown

t_summary

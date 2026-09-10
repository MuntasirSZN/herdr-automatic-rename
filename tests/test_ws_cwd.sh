#!/usr/bin/env bash
# Integration test: a numbered workspace still follows its directory (issue #13).
#
# herdr labels a workspace after identity_cwd, its own tracked directory: the
# repository that directory belongs to, or the directory itself outside a repo.
# The FIRST `workspace rename` freezes that derivation for good -- herdr keeps
# identity_cwd up to date and never re-labels from it again -- so numbering a
# workspace used to stop its label tracking cd, permanently.
#
# The engine takes the base from identity_cwd (session.json, next to
# $HERDR_SOCKET_PATH, the file ar_collapsed_spaces already reads) instead of
# recycling the label it wrote last pass. Ownership gates it: a label that is
# neither herdr's derivation nor our own last write was typed by somebody, so it
# is left alone -- the same promise the tab opt-out makes.

set -o pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib.sh
. "$here/lib.sh"

ENGINE="$here/../automatic-rename.sh"
MOCK="$here/mocks/herdr"
chmod +x "$MOCK" 2>/dev/null || true

# ======================================================================
# ar_project_base: the derivation itself, against real directories. Sourcing the
# engine loads the functions and runs nothing.
# ======================================================================
# shellcheck source=automatic-rename.sh
. "$ENGINE"
# ar_ws_subst lives beside its rule list in the pure module, which the engine
# only sources once a pass starts.
# shellcheck source=naming.sh
. "$here/../naming.sh"

PB=$(mktemp -d "${TMPDIR:-/tmp}/hal-pbase.XXXXXX")
mkdir -p "$PB/plain/sub" "$PB/co/src/deep" "$PB/wt"
: >"$PB/co/.git"                       # a checkout: `.git` as a FILE, as a linked worktree has
mkdir -p "$PB/repo/.git" "$PB/repo/pkg"   # and as a directory, as a main checkout has
check "repo root itself"        "co"    "$(ar_project_base "$PB/co")"
check "inside the checkout"     "co"    "$(ar_project_base "$PB/co/src/deep")"
check "git dir, not file"       "repo"  "$(ar_project_base "$PB/repo/pkg")"
check "outside any repo"        "sub"   "$(ar_project_base "$PB/plain/sub")"
check "trailing slash ignored"  "sub"   "$(ar_project_base "$PB/plain/sub/")"
check "relative path: basename" "notes" "$(ar_project_base "some/notes")"
check "empty path: empty base"  ""      "$(ar_project_base "")"
mkdir -p "$PB/plain/$(printf 'ta\tb')"
check "control char scrubbed" "ta b" "$(ar_project_base "$PB/plain/$(printf 'ta\tb')")"
check "double space collapsed" "a b" "$(ar_project_base "some/a  b")"
rm -rf "$PB"

# ar_ws_subst: the rewrite itself, rules in, label out.
WORKSPACE_SUBSTITUTE_SETS=('s|^worktree-|wt-|')
check "rule applied"     "wt-feature" "$(ar_ws_subst "worktree-feature")"
check "rule matches not" "project-a"  "$(ar_ws_subst "project-a")"
WORKSPACE_SUBSTITUTE_SETS=('s|^worktree-|wt-|' 's|-feature$|-f|')
check "rules run in order" "wt-f" "$(ar_ws_subst "worktree-feature")"
WORKSPACE_SUBSTITUTE_SETS=()
check "no rules, no rewrite" "worktree-feature" "$(ar_ws_subst "worktree-feature")"

# Numbering only (NAME_TABS off, no tab/pane fixtures), so the rename log holds
# workspace renames alone. State is NOT sandboxed per scenario on purpose in the
# multi-pass ones: ownership has to survive from one event to the next.
setup() {
  SB=$(mktemp -d "${TMPDIR:-/tmp}/hal-wscwd.XXXXXX")
  export HERDR_MOCK_DIR="$SB/fixtures"; mkdir -p "$HERDR_MOCK_DIR"
  export HERDR_MOCK_LOG="$SB/renames.log"; : >"$HERDR_MOCK_LOG"
  export HERDR_BIN_PATH="$MOCK"
  export XDG_STATE_HOME="$SB/state"
  export HERDR_AUTOMATIC_RENAME_CONFIG="$SB/none.sh"   # absent -> env toggles win
  export HERDR_CONFIG_FILE="$SB/herdr.toml"
  printf 'agent_panel_sort = "spaces"\n' >"$HERDR_CONFIG_FILE"
  export HERDR_SOCKET_PATH="$SB/herdr.sock"            # session.json sits beside it
  export SHELL_NAME=zsh
  export NAME_TABS=0 AUTO_INDEX=1
  unset AUTO_INDEX_WORKSPACES CLEAR
}
fixture() { cat >"$HERDR_MOCK_DIR/$1"; }
# ws <id> <label>  -- one workspace, no worktree (its own sidebar row).
ws() { printf '{"workspace_id":"%s","label":"%s","focused":false}' "$1" "$2"; }
workspaces() { printf '{"result":{"workspaces":[%s]}}\n' "$(printf '%s' "$*")" \
  >"$HERDR_MOCK_DIR/workspaces.json"; }
# repo <path>  -- make <path> (under $SB) a checkout: a directory with a `.git`
# in it, which is what ar_project_base walks for. A `.git` FILE, as a linked
# worktree has, since that is the case a `-d` test would miss.
repo() { mkdir -p "$SB$1" && : >"$SB$1/.git"; }
# session <"id=cwd" ...>  -- the session file herdr persists, with identity_cwd.
# The directories are made real (rooted at $SB) because ar_project_base walks them
# looking for a repo, so a fictional path would only ever exercise the non-repo arm.
session() {
  local rows="" e p
  for e in "$@"; do
    p=$SB${e#*=}
    mkdir -p "$p"
    rows="$rows${rows:+,}$(printf '{"id":"%s","label":null,"identity_cwd":"%s"}' \
      "${e%%=*}" "$p")"
  done
  printf '{"version":7,"collapsed_space_keys":[],"workspaces":[%s]}\n' "$rows" \
    >"$SB/session.json"
}
run_event() { /usr/bin/env bash "$ENGINE" "$1"; }
log() { cat "$HERDR_MOCK_LOG"; }
clear_log() { : >"$HERDR_MOCK_LOG"; }
teardown() { rm -rf "$SB" 2>/dev/null || true; }

# ======================================================================
# Scenario 1: the bug. A fresh workspace is numbered, its pane cds elsewhere,
#   and the next event must re-label it from the new directory.
# ======================================================================
setup
workspaces "$(ws w1 project-a)"
session "w1=/home/u/project-a"
run_event workspace.created
check_contains "fresh ws numbered" "$(log)" "workspace rename w1 [1] project-a"

clear_log
workspaces "$(ws w1 '[1] project-a')"
session "w1=/home/u/project-b"
run_event pane.focused
check_contains "label follows cd" "$(log)" "workspace rename w1 [1] project-b"

# ...and settles: a second event over the same state renames nothing.
clear_log
workspaces "$(ws w1 '[1] project-b')"
run_event pane.focused
check "settled: no rename" "" "$(log)"
teardown

# ======================================================================
# Scenario 2: cd INSIDE the repo keeps the repo's name. herdr labels a workspace
#   after the repository its directory belongs to, so walking down into src/ is
#   not a rename -- taking the directory's own basename would rename the
#   workspace on every cd inside the project.
# ======================================================================
setup
repo /repos/herdr
workspaces "$(ws w1 '[1] herdr')"
session "w1=/repos/herdr/docs/deep"
run_event pane.focused
check "cd within the repo: no rename" "" "$(log)"

# ...and leaving the repo for a plain directory takes that directory's name.
clear_log
session "w1=/elsewhere/notes"
run_event pane.focused
check_contains "leaving the repo tracks the directory" "$(log)" "workspace rename w1 [1] notes"
teardown

# ======================================================================
# Scenario 3: a label nobody derived is a label somebody typed. The plugin
#   numbers it and never touches the base again, even as identity_cwd moves.
# ======================================================================
setup
workspaces "$(ws w1 'incident room')"
session "w1=/home/u/project-a"
run_event workspace.created
check_contains "hand-named ws still numbered" "$(log)" "workspace rename w1 [1] incident room"

clear_log
workspaces "$(ws w1 '[1] incident room')"
session "w1=/home/u/project-b"
run_event pane.focused
check "hand-named base survives a cd" "" "$(log)"
teardown

# ======================================================================
# Scenario 4: a rename typed over a label we owned opts the workspace out from
#   then on -- the tab promise, for workspaces.
# ======================================================================
setup
workspaces "$(ws w1 project-a)"
session "w1=/home/u/project-a"
run_event workspace.created                       # adopt at project-a

clear_log
workspaces "$(ws w1 '[1] war room')"              # typed over our label
session "w1=/home/u/project-b"
run_event pane.focused
check "typed-over label is left alone" "" "$(log)"

clear_log
workspaces "$(ws w1 '[1] war room')"
session "w1=/home/u/project-c"
run_event pane.focused
check "and stays left alone after another cd" "" "$(log)"
teardown

# ======================================================================
# Scenario 5: renaming a workspace back to what herdr would call it hands
#   tracking back. That is the recovery path, since a workspace has no `reset`.
# ======================================================================
setup
workspaces "$(ws w1 '[1] war room')"
session "w1=/home/u/project-a"
run_event pane.focused                            # opts out (nobody derived that)

clear_log
workspaces "$(ws w1 '[1] project-a')"             # renamed back by hand
session "w1=/home/u/project-a"
run_event pane.focused
check "matching label is not renamed" "" "$(log)"

clear_log
workspaces "$(ws w1 '[1] project-a')"
session "w1=/home/u/project-b"
run_event pane.focused
check_contains "tracking resumes" "$(log)" "workspace rename w1 [1] project-b"
teardown

# ======================================================================
# Scenario 6: no identity_cwd to read -- no session file at all (herdr older
#   than the field, an unreadable file) -- falls back to recycling the label,
#   which is what the plugin did before it read this. Numbering still works.
# ======================================================================
setup
workspaces "$(ws w1 project-a)"
rm -f "$SB/session.json"
run_event workspace.created
check_contains "no session file: still numbered" "$(log)" "workspace rename w1 [1] project-a"

clear_log
workspaces "$(ws w1 '[1] project-a')"
run_event pane.focused
check "no session file: label recycled, no churn" "" "$(log)"
teardown

# ======================================================================
# Scenario 7: --clear only strips. It is the uninstall path, so it must not
#   rewrite a base to the directory name on its way out.
# ======================================================================
setup
workspaces "$(ws w1 '[1] war room')"
session "w1=/home/u/project-b"
/usr/bin/env bash "$ENGINE" --clear >/dev/null 2>&1
check_contains "clear strips the prefix only" "$(log)" "workspace rename w1 war room"
check_absent   "clear does not retitle"       "$(log)" "project-b"
teardown

# ======================================================================
# Scenario 8: numbering off but explicitly named (AUTO_INDEX_WORKSPACES=0) asks
#   for the prefix to be stripped, and the base still tracks the directory.
# ======================================================================
setup
export AUTO_INDEX_WORKSPACES=0
workspaces "$(ws w1 '[1] project-a')"
session "w1=/home/u/project-a"
run_event pane.focused                            # adopt, and strip the prefix
check_contains "numbering off: prefix stripped" "$(log)" "workspace rename w1 project-a"

clear_log
workspaces "$(ws w1 project-a)"
session "w1=/home/u/project-b"
run_event pane.focused
check_contains "numbering off: bare base tracks cd" "$(log)" "workspace rename w1 project-b"
teardown

# ======================================================================
# Scenario 9: a rename that FAILS records no ownership. A base we did not land
#   is indistinguishable, one pass later, from a name typed by hand.
# ======================================================================
setup
export HERDR_MOCK_FAIL_RENAME=1
workspaces "$(ws w1 project-a)"
session "w1=/home/u/project-a"
run_event workspace.created
unset HERDR_MOCK_FAIL_RENAME
check "failed rename claims nothing" \
  "" "$(jq -r '."ws:w1".auto // ""' "$XDG_STATE_HOME/herdr-automatic-rename/state.json" 2>/dev/null)"
teardown

# ======================================================================
# Scenario 10: a workspace that closes takes its ownership record with it, so a
#   long session does not grow one entry per workspace it ever had.
# ======================================================================
setup
workspaces "$(ws w1 project-a)" , "$(ws w2 project-b)"
session "w1=/home/u/project-a" "w2=/home/u/project-b"
run_event workspace.created
state=$XDG_STATE_HOME/herdr-automatic-rename/state.json
check "both owned" "project-a project-b" \
  "$(jq -r '[."ws:w1".auto, ."ws:w2".auto] | join(" ")' "$state" 2>/dev/null)"

workspaces "$(ws w1 '[1] project-a')"             # w2 closed
session "w1=/home/u/project-a"
run_event workspace.closed
check "closed ws pruned"  "null"       "$(jq -r '."ws:w2" | tostring' "$state" 2>/dev/null)"
check "open ws kept"      "project-a"  "$(jq -r '."ws:w1".auto' "$state" 2>/dev/null)"
teardown

# ======================================================================
# Scenario 11: the tab pass must not prune the workspace records. Both kinds
#   live in one state file, and a tab keep-list never names a workspace: pruning
#   on it alone dropped every "ws:" record on the pass after it was written, so
#   each workspace read as first-seen against a label that was no longer herdr's
#   derivation and opted itself out -- the same bug, one layer down. Found live,
#   not in the suite, which is why it is pinned here.
# ======================================================================
setup
export NAME_TABS=1
workspaces "$(ws w1 project-a)"
session "w1=/home/u/project-a"
fixture tabs_w1.json <<'JSON'
{"result":{"tabs":[{"tab_id":"w1:t1","label":"1","pane_count":1,"focused":true}]}}
JSON
fixture panes.json <<'JSON'
{"result":{"panes":[{"pane_id":"p1","tab_id":"w1:t1","focused":true}]}}
JSON
fixture procinfo_p1.json <<'JSON'
{"result":{"process_info":{"foreground_process_group_id":100,
  "foreground_processes":[{"pid":100,"argv0":"nvim","cmdline":"nvim README.md"}]}}}
JSON
run_event tab.focused
state=$XDG_STATE_HOME/herdr-automatic-rename/state.json
check "ws record survives the tab prune" "project-a" \
  "$(jq -r '."ws:w1".auto // ""' "$state" 2>/dev/null)"
check "tab record written too"           "nvim" \
  "$(jq -r '."w1:t1".auto // ""' "$state" 2>/dev/null)"

clear_log
workspaces "$(ws w1 '[1] project-a')"
session "w1=/home/u/project-b"
run_event tab.focused
check_contains "and tracking still works" "$(log)" "workspace rename w1 [1] project-b"
teardown

# ======================================================================
# Scenario 12: the workspace herdr has not persisted yet, which is EVERY new
#   one for up to five seconds. It is in no copy of session.json, so a pass
#   numbering it seconds after it opened used to read "a label nobody derived",
#   opt it out for good, and leave it on its creation name forever -- the very
#   bug, surviving the fix. The pane's own directory settles the comparison at
#   creation, where herdr's label and the pane agree. Snapshot path, since that
#   is what herdr >= 0.7.2 gives every pass.
# ======================================================================
setup
mkdir -p "$SB/home/project-a" "$SB/home/project-b"
snapshot() {   # snapshot <ws label> <pane cwd under $SB>
  cat >"$HERDR_MOCK_DIR/snapshot.json" <<JSON
{"result":{"snapshot":{"workspaces":[
  {"workspace_id":"w1","label":"$1","focused":true,"active_tab_id":"w1:t1"}
],"tabs":[],"panes":[
  {"pane_id":"w1:p1","workspace_id":"w1","tab_id":"w1:t1","focused":true,
   "foreground_cwd":"$SB$2"}
],"agents":[]}}}
JSON
}
session "w9=/home/other"                          # the file exists, without w1 in it
snapshot project-a /home/project-a
run_event workspace.created
check_contains "unpersisted ws numbered" "$(log)" "workspace rename w1 [1] project-a"
state=$XDG_STATE_HOME/herdr-automatic-rename/state.json
check "and claimed from its pane" "project-a" \
  "$(jq -r '."ws:w1".auto // ""' "$state" 2>/dev/null)"

# The pane cds while herdr still has not written the file: tracking already works.
clear_log
snapshot '[1] project-a' /home/project-b
run_event pane.focused
check_contains "tracks before herdr persists it" "$(log)" "workspace rename w1 [1] project-b"
teardown

# ======================================================================
# Scenario 13: the create prompt (`prompt_new_workspace_name`) types the name
#   before the plugin ever sees the workspace, and that name is not what the
#   pane's directory would give. It gets numbered and nothing else, which is the
#   promise the README makes.
# ======================================================================
setup
mkdir -p "$SB/home/project-a" "$SB/home/project-b"
session "w9=/home/other"
snapshot 'incident room' /home/project-a
run_event workspace.created
check_contains "typed name numbered" "$(log)" "workspace rename w1 [1] incident room"

clear_log
snapshot '[1] incident room' /home/project-b
run_event pane.focused
check "typed name never retitled" "" "$(log)"
teardown

# ======================================================================
# Scenario 14: once herdr HAS persisted the workspace, its identity_cwd wins
#   over the pane directory. herdr moves identity with the workspace's active
#   pane and answering which pane that is takes the layout, so the file is the
#   answer and the panes are only the stand-in for a workspace missing from it.
# ======================================================================
setup
mkdir -p "$SB/home/from-identity" "$SB/home/from-pane"
cat >"$HERDR_MOCK_DIR/snapshot.json" <<JSON
{"result":{"snapshot":{"workspaces":[
  {"workspace_id":"w1","label":"[1] stale","focused":true,"active_tab_id":"w1:t1"}
],"tabs":[],"panes":[
  {"pane_id":"w1:p1","workspace_id":"w1","tab_id":"w1:t1","focused":true,
   "foreground_cwd":"$SB/home/from-pane"}
],"agents":[]}}}
JSON
session "w1=/home/from-identity"
printf '{"ws:w1":{"auto":"stale","enabled":true}}\n' \
  >"$XDG_STATE_HOME/herdr-automatic-rename/state.json" 2>/dev/null \
  || { mkdir -p "$XDG_STATE_HOME/herdr-automatic-rename"; \
       printf '{"ws:w1":{"auto":"stale","enabled":true}}\n' \
         >"$XDG_STATE_HOME/herdr-automatic-rename/state.json"; }
run_event pane.focused
check_contains "identity_cwd wins" "$(log)" "workspace rename w1 [1] from-identity"
check_absent   "pane dir ignored"  "$(log)" "from-pane"
teardown

# ======================================================================
# Scenario 15: a cd in the shell moves the workspace name (issue #20). herdr
#   emits no event for a cd, so the workspace label sat on the directory the
#   workspace was created in until some unrelated event arrived, while the tab
#   beside it followed every prompt: the shell hook renames the tab and nothing
#   else. The hook knows the directory (its own $PWD) and the state file already
#   says which base we own, so the same ownership rules apply from there.
#   NAME_TABS is off here, which is the file's default: workspace tracking is
#   governed by the workspace knobs, not by whether tabs are named.
# ======================================================================
setup
mkdir -p "$SB/home/project-a" "$SB/home/project-b"
export HERDR_TAB_ID=w1:t1 HERDR_PANE_ID=w1:p1
workspaces "$(ws w1 project-a)"
session "w1=/home/project-a"
run_event workspace.created                       # adopt at project-a

clear_log
workspaces "$(ws w1 '[1] project-a')"             # as the adopt left it
( cd "$SB/home/project-b" && /usr/bin/env bash "$ENGINE" precmd zsh )
check_contains "the hook moves the workspace" "$(log)" "workspace rename w1 [1] project-b"

# ...and settles: the next prompt in the same directory renames nothing.
clear_log
workspaces "$(ws w1 '[1] project-b')"
( cd "$SB/home/project-b" && /usr/bin/env bash "$ENGINE" precmd zsh )
check "settled: the next prompt is quiet" "" "$(log)"
teardown

# ======================================================================
# Scenario 16: the hook obeys the same ownership rule the reconcile does. A name
#   somebody typed is numbered and never retitled, and a prompt is not the place
#   that changes.
# ======================================================================
setup
mkdir -p "$SB/home/project-a" "$SB/home/project-b"
export HERDR_TAB_ID=w1:t1 HERDR_PANE_ID=w1:p1
workspaces "$(ws w1 'incident room')"
session "w1=/home/project-a"
run_event workspace.created                       # numbered, and opted out

clear_log
workspaces "$(ws w1 '[1] incident room')"
( cd "$SB/home/project-b" && /usr/bin/env bash "$ENGINE" precmd zsh )
check "the hook leaves a typed name alone" "" "$(log)"
teardown

# ======================================================================
# Scenario 17: the tab beside the workspace must not repeat its new name. The
#   tab dedupes its context against the workspace base recorded on the tab, so
#   naming the tab first and moving the workspace afterwards leaves the tab
#   saying "project-b > zsh" under a workspace called project-b, at every prompt
#   until a full reconcile refreshes the record. The workspace half runs first
#   and hands the base it applied to the tab half.
# ======================================================================
setup
export NAME_TABS=1 TAB_CONTEXT=1 HERDR_TAB_ID=w1:t1 HERDR_PANE_ID=w1:p1
mkdir -p "$SB/home/project-a" "$SB/home/project-b"
workspaces "$(ws w1 project-a)"
session "w1=/home/project-a"
fixture tabs_w1.json <<'JSON'
{"result":{"tabs":[{"tab_id":"w1:t1","label":"1","pane_count":1,"focused":true}]}}
JSON
fixture panes.json <<'JSON'
{"result":{"panes":[{"pane_id":"w1:p1","tab_id":"w1:t1","focused":true}]}}
JSON
fixture procinfo_w1:p1.json <<'JSON'
{"result":{"process_info":{"foreground_process_group_id":100,
  "foreground_processes":[{"pid":100,"argv0":"-zsh","cmdline":"-zsh"}]}}}
JSON
fixture "tab_w1:t1.json" <<'JSON'
{"result":{"tab":{"tab_id":"w1:t1","label":"[1] zsh"}}}
JSON
run_event tab.focused                             # adopt both at project-a

clear_log
workspaces "$(ws w1 '[1] project-a')"
( cd "$SB/home/project-b" && /usr/bin/env bash "$ENGINE" precmd zsh )
state=$XDG_STATE_HOME/herdr-automatic-rename/state.json
check_contains "the workspace moves" "$(log)" "workspace rename w1 [1] project-b"
check "the tab records the new workspace base" "project-b" \
  "$(jq -r '."w1:t1".ws // ""' "$state" 2>/dev/null)"
check_absent "and does not repeat it in its own label" "$(log)" "tab rename w1:t1 [1] project-b"
teardown

# ======================================================================
# Scenario 18: a prompt drawn in a tab the workspace is not on says nothing
#   about where the workspace is. herdr moves identity_cwd with the active pane,
#   so a background tab's cd would rename the workspace away from where the user
#   is standing, and the next reconcile would undo it.
# ======================================================================
setup
mkdir -p "$SB/home/project-a" "$SB/home/project-b"
export HERDR_TAB_ID=w1:t2 HERDR_PANE_ID=w1:p2
workspaces "$(ws w1 project-a)"
session "w1=/home/project-a"
run_event workspace.created                       # adopt at project-a

clear_log
# The workspace is on t1; this prompt is drawn in t2.
printf '{"result":{"workspaces":[{"workspace_id":"w1","label":"[1] project-a","focused":false,"active_tab_id":"w1:t1"}]}}\n' \
  >"$HERDR_MOCK_DIR/workspaces.json"
( cd "$SB/home/project-b" && /usr/bin/env bash "$ENGINE" precmd zsh )
check "a background tab does not move the workspace" "" "$(log)"

# The active tab's own prompt still does.
clear_log
HERDR_TAB_ID=w1:t1 HERDR_PANE_ID=w1:p1 \
  bash -c 'cd "$1" && /usr/bin/env bash "$2" precmd zsh' _ "$SB/home/project-b" "$ENGINE"
check_contains "the active tab still does" "$(log)" "workspace rename w1 [1] project-b"
teardown

# ======================================================================
# Scenario 19: the pass must not revert what the prompt just applied. herdr
#   saves session.json on a 5-second debounce and our own workspace rename is an
#   event we subscribe to, so the reconcile that rename triggers reads the
#   directory the workspace LEFT and used to rename it straight back, once per
#   prompt for as long as the file lagged. Where the panes still say what we last
#   wrote, the file is behind rather than right.
#   The counterpart is scenario 14, where the pane agrees with neither the file
#   nor the record and the file stays the answer.
# ======================================================================
setup
mkdir -p "$SB/home/project-a" "$SB/home/project-b"
cat >"$HERDR_MOCK_DIR/snapshot.json" <<JSON
{"result":{"snapshot":{"workspaces":[
  {"workspace_id":"w1","label":"[1] project-b","focused":true,"active_tab_id":"w1:t1"}
],"tabs":[],"panes":[
  {"pane_id":"w1:p1","workspace_id":"w1","tab_id":"w1:t1","focused":true,
   "foreground_cwd":"$SB/home/project-b"}
],"agents":[]}}}
JSON
session "w1=/home/project-a"                      # the file has not caught up
mkdir -p "$XDG_STATE_HOME/herdr-automatic-rename"
printf '{"ws:w1":{"auto":"project-b","enabled":true}}\n' \
  >"$XDG_STATE_HOME/herdr-automatic-rename/state.json"
run_event workspace.renamed
check "the prompt's name survives the debounce" "" "$(log)"

# Once herdr writes the file, both agree and nothing changes either.
clear_log
session "w1=/home/project-b"
run_event pane.focused
check "and still nothing once it catches up" "" "$(log)"
teardown

# ======================================================================
# Scenario 20: the same on the fallback path. herdr 0.7.1 has no `api snapshot`,
#   and a snapshot call can fail on any version, so the per-list path is a
#   supported one rather than a curiosity. The panes were fetched there only
#   where tabs were being named, which left the workspace pass with no pane rows
#   at all: no directory for a workspace herdr has not persisted yet, and no way
#   to tell the debounce apart from a stale name. NAME_TABS is off here.
# ======================================================================
setup
mkdir -p "$SB/home/project-a" "$SB/home/project-b"
workspaces "$(ws w1 '[1] project-b')"
fixture panes.json <<JSON
{"result":{"panes":[{"pane_id":"w1:p1","workspace_id":"w1","tab_id":"w1:t1","focused":true,
  "foreground_cwd":"$SB/home/project-b"}]}}
JSON
session "w1=/home/project-a"                      # the file has not caught up
mkdir -p "$XDG_STATE_HOME/herdr-automatic-rename"
printf '{"ws:w1":{"auto":"project-b","enabled":true}}\n' \
  >"$XDG_STATE_HOME/herdr-automatic-rename/state.json"
run_event workspace.renamed
check "no snapshot: the prompt's name still survives" "" "$(log)"
teardown

# ======================================================================
# Scenario 21: the debounce rule asks for a pane herdr named, not a pane we
#   picked. A background workspace has no focused pane to read, so a split
#   active tab leaves the pane rows naming whichever pane came first. Letting
#   that override identity_cwd would prefer an arbitrary pane over the real one
#   for as long as the two disagreed, which is a wrong name that never corrects
#   itself rather than a late file that does. So identity still wins, and the
#   label goes back to what herdr says.
# ======================================================================
setup
mkdir -p "$SB/home/project-a" "$SB/home/project-b"
cat >"$HERDR_MOCK_DIR/snapshot.json" <<JSON
{"result":{"snapshot":{"workspaces":[
  {"workspace_id":"w1","label":"[1] project-b","focused":false,"active_tab_id":"w1:t1"}
],"tabs":[],"panes":[
  {"pane_id":"w1:p1","workspace_id":"w1","tab_id":"w1:t1",
   "foreground_cwd":"$SB/home/project-b"},
  {"pane_id":"w1:p2","workspace_id":"w1","tab_id":"w1:t1",
   "foreground_cwd":"$SB/home/project-a"}
],"agents":[]}}}
JSON
session "w1=/home/project-a"
mkdir -p "$XDG_STATE_HOME/herdr-automatic-rename"
printf '{"ws:w1":{"auto":"project-b","enabled":true}}\n' \
  >"$XDG_STATE_HOME/herdr-automatic-rename/state.json"
run_event workspace.renamed
check_contains "a guessed pane does not outrank identity" "$(log)" \
  "workspace rename w1 [1] project-a"
teardown

# ======================================================================
# Scenario 22: a tab dragged into another workspace keeps the id it was created
#   with, so the workspace in front of its colon is the one it LEFT. A prompt in
#   that tab says nothing about the workspace it is no longer in.
# ======================================================================
setup
mkdir -p "$SB/home/project-a" "$SB/home/project-b"
export HERDR_TAB_ID=w1:t1 HERDR_PANE_ID=w1:p1
workspaces "$(ws w1 project-a)"
session "w1=/home/project-a"
run_event workspace.created                       # adopt w1 at project-a

clear_log
# t1 now heads w2; w1 is left with no active tab of its own.
printf '{"result":{"workspaces":[
  {"workspace_id":"w1","label":"[1] project-a","focused":false},
  {"workspace_id":"w2","label":"[2] other","focused":true,"active_tab_id":"w1:t1"}]}}\n' \
  >"$HERDR_MOCK_DIR/workspaces.json"
( cd "$SB/home/project-b" && /usr/bin/env bash "$ENGINE" precmd zsh )
check "a moved tab does not rename the workspace it left" "" "$(log)"
teardown

# ======================================================================
# Scenario 18: WORKSPACE_SUBSTITUTE_SETS rewrites the label a workspace takes
#   from its directory, and only the label. The rewrite composes with numbering
#   in the one rename, and then settles.
# ======================================================================
setup
rule() { printf "WORKSPACE_SUBSTITUTE_SETS=('s|^worktree-|wt-|')\n" \
  >"$HERDR_AUTOMATIC_RENAME_CONFIG"; }
rule
workspaces "$(ws w1 worktree-feature)"
session "w1=/home/u/worktree-feature"
run_event workspace.created
check_contains "the derived label is rewritten" "$(log)" "workspace rename w1 [1] wt-feature"

clear_log
workspaces "$(ws w1 '[1] wt-feature')"
run_event pane.focused
check "the rewrite settles" "" "$(log)"

# ...and it follows a cd like any other derived label: the new directory is
# derived first and rewritten second.
clear_log
session "w1=/home/u/worktree-parser"
run_event pane.focused
check_contains "the rewrite follows the cd" "$(log)" "workspace rename w1 [1] wt-parser"
teardown

# ======================================================================
# Scenario 19: the rewrite runs on a config that never asked for numbering.
#   Numbering and rewriting are separate reasons for the workspace pass to
#   exist, and AUTO_INDEX=0 switches off only the first.
# ======================================================================
setup
export AUTO_INDEX=0
rule
workspaces "$(ws w1 worktree-feature)"
session "w1=/home/u/worktree-feature"
run_event workspace.created
check_contains "no numbering, still rewritten" "$(log)" "workspace rename w1 wt-feature"

# A workspace no rule touches is renamed nothing at all -- the pass runs, and
# leaves a label that already reads as it should.
clear_log
workspaces "$(ws w1 wt-feature),$(ws w2 project-a)"
session "w1=/home/u/worktree-feature" "w2=/home/u/project-a"
run_event pane.focused
check "a label no rule matches is left alone" "" "$(log)"
teardown

# ======================================================================
# Scenario 20: a name somebody typed is not rewritten, even when a rule matches
#   it. Ownership is the same promise the tab opt-out makes: a label that is
#   neither herdr's derivation nor our own last write belongs to whoever typed
#   it. (herdr exposes no way to tell a typed name from the derivation it
#   happens to match exactly, which config.example.sh says out loud.)
# ======================================================================
setup
export AUTO_INDEX=0
rule
workspaces "$(ws w1 worktree-incident)"
session "w1=/home/u/project-a"
run_event workspace.created
check "a hand-typed name is not rewritten" "" "$(log)"
teardown

# ======================================================================
# Scenario 21: deleting the rules puts the derived names back, and then lets go.
#   With numbering off there is nothing else to bring the workspace pass round
#   again, so an owned workspace keeps it alive for exactly one more pass: the
#   one that hands the derivation back and drops the record. herdr labels the
#   workspace from its directory again from there, which it only does for a
#   workspace nobody has renamed.
# ======================================================================
setup
export AUTO_INDEX=0
state=$XDG_STATE_HOME/herdr-automatic-rename/state.json
rule
workspaces "$(ws w1 worktree-feature)"
session "w1=/home/u/worktree-feature"
run_event workspace.created
check_contains "adopted at the rewrite" "$(log)" "workspace rename w1 wt-feature"

clear_log
: >"$HERDR_AUTOMATIC_RENAME_CONFIG"                # the rules are deleted
workspaces "$(ws w1 wt-feature)"
run_event pane.focused
check_contains "deleting the rules restores the derived name" "$(log)" \
  "workspace rename w1 worktree-feature"
check "and the record is let go" "false" "$(jq -r 'has("ws:w1")' "$state" 2>/dev/null)"

clear_log
workspaces "$(ws w1 worktree-feature)"
run_event pane.focused
check "and the pass stops running at all" "" "$(log)"
teardown

# ======================================================================
# Scenario 22: an unwind touches only what this plugin owns. It runs on a config
#   that never named workspace numbering, so a "[3] " on a row it does not own
#   is somebody's own text -- and the number on a row it DOES own is carried
#   over rather than stripped, for the same reason.
# ======================================================================
setup
export AUTO_INDEX=0
state=$XDG_STATE_HOME/herdr-automatic-rename/state.json
mkdir -p "$XDG_STATE_HOME/herdr-automatic-rename"
printf '{"ws:w1":{"auto":"wt-feature","enabled":true}}\n' >"$state"
workspaces "$(ws w1 '[3] wt-feature'),$(ws w2 '[9] notes')"
session "w1=/home/u/worktree-feature" "w2=/home/u/elsewhere"
run_event pane.focused
check_contains "the number is carried over the restore" "$(log)" \
  "workspace rename w1 [3] worktree-feature"
check_absent "a row we do not own is untouched" "$(log)" "w2"
teardown

# ======================================================================
# Scenario 23: `clear` takes the rewrite back too, not just the number. It is
#   documented as the last step before uninstall, after which the plugin that
#   could have restored the label is gone -- so it hands back the derived base
#   and strips the prefix off THAT.
# ======================================================================
setup
rule
workspaces "$(ws w1 worktree-feature)"
session "w1=/home/u/worktree-feature"
run_event workspace.created
check_contains "adopted and numbered" "$(log)" "workspace rename w1 [1] wt-feature"

clear_log
workspaces "$(ws w1 '[1] wt-feature')"
/usr/bin/env bash "$ENGINE" --clear
check_contains "clear restores the derived base" "$(log)" \
  "workspace rename w1 worktree-feature"
teardown

# ======================================================================
# Scenario 24: the shell hook rewrites too, and stays quiet where the rewrite
#   already stands. The hook's whole guard is "the base I own is the base this
#   prompt derives"; comparing the DERIVED name against a record holding the
#   REWRITTEN one is never equal, and would fetch `workspace list` on every
#   prompt for as long as a rule matched the workspace.
# ======================================================================
setup
export AUTO_INDEX=0
export HERDR_TAB_ID=w1:t1 HERDR_PANE_ID=w1:p1
mkdir -p "$SB/home/worktree-feature" "$SB/home/worktree-parser"
rule
workspaces "$(ws w1 worktree-feature)"
session "w1=/home/worktree-feature"
run_event workspace.created                        # adopt at the rewrite
check_contains "adopted at the rewrite" "$(log)" "workspace rename w1 wt-feature"

clear_log
workspaces "$(ws w1 wt-feature)"
( cd "$SB/home/worktree-parser" && /usr/bin/env bash "$ENGINE" precmd zsh )
check_contains "the hook applies the rewrite" "$(log)" "workspace rename w1 wt-parser"

clear_log
workspaces "$(ws w1 wt-parser)"
trace=$SB/trace.log
( cd "$SB/home/worktree-parser" \
  && AR_TRACE=1 AR_TRACE_FILE="$trace" /usr/bin/env bash "$ENGINE" precmd zsh )
check "the next prompt renames nothing" "" "$(log)"
check_contains "and asked herdr nothing" "$(cat "$trace" 2>/dev/null)" \
  "quiet prompt: not owned, or base already [wt-parser]"
teardown

# ======================================================================
# Scenario 25: the hook unwinds as the reconcile does. Whichever half reaches a
#   workspace first once the rules are gone hands the derivation back and drops
#   the record, so the other has nothing left to wake it.
# ======================================================================
setup
export AUTO_INDEX=0
export HERDR_TAB_ID=w1:t1 HERDR_PANE_ID=w1:p1
state=$XDG_STATE_HOME/herdr-automatic-rename/state.json
mkdir -p "$SB/home/worktree-feature"
rule
workspaces "$(ws w1 worktree-feature)"
session "w1=/home/worktree-feature"
run_event workspace.created

clear_log
: >"$HERDR_AUTOMATIC_RENAME_CONFIG"                # the rules are deleted
workspaces "$(ws w1 wt-feature)"
( cd "$SB/home/worktree-feature" && /usr/bin/env bash "$ENGINE" precmd zsh )
check_contains "the hook restores the derived name" "$(log)" \
  "workspace rename w1 worktree-feature"
check "and lets the workspace go" "false" "$(jq -r 'has("ws:w1")' "$state" 2>/dev/null)"
teardown

t_summary

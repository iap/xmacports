#!/usr/bin/env bash
# Tests for scripts/check-merge-gates.sh - the CI-side gate on whether an MR's
# merge gates are armed and its review conversation is resolved.
#
# Why this needs its own suite: the merge trigger is not a repo-side property.
# It lives in forge settings (which allow the merge button at all) and in the
# conversation state (whether anything is left to resolve). Neither is visible
# to git, so the only thing a local test can defend is the gate's own behavior
# when those reads succeed, fail, or half-succeed. Each case below drives one of
# those outcomes.
#
# A stub API server stands in for GitLab so the cases do not depend on a live
# MR, a real token, or network access. It routes by path - project, MR,
# discussions, protected branch - and reads each body from a file at request
# time, so a case can change the forge's answer without restarting the server.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/check-merge-gates.sh"

pass=0
fail=0
TMP=""
PORT=""
SERVER_PID=""

ok() {
  pass=$((pass + 1))
  echo "  ok   $1"
}

no() {
  fail=$((fail + 1))
  echo "  FAIL $1"
}

setup() {
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/mrgates-test.XXXXXX")"
}

teardown() {
  stop_server
  [ -n "$TMP" ] && [ -d "$TMP" ] && find "$TMP" -mindepth 1 -delete 2> /dev/null
  [ -n "$TMP" ] && [ -d "$TMP" ] && rmdir "$TMP" 2> /dev/null
  return 0
}

# start_server serves <dir>/{project,mr,disc,prot}.json, routing by request path.
# A missing file answers 404, which is how the "cannot fetch" cases are driven.
#
# The port is read from a FILE, never from command substitution: a backgrounded
# server inside $(...) keeps the substitution's pipe open, so the shell blocks
# until the server dies.
start_server() {
  local dir="$1"
  local port_file="$TMP/port"

  rm -f "$port_file"
  python3 - "$dir" "$port_file" << 'PY' &
import http.server, json, os, re, socketserver, sys
from urllib.parse import urlparse

root, port_file = sys.argv[1], sys.argv[2]


def body(name):
    path = os.path.join(root, name + ".json")
    if not os.path.exists(path):
        return None
    return open(path).read()


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlparse(self.path).path
        # Optional: reject any request carrying an auth header with 401, so a
        # case can exercise the authenticated-fails / anonymous-succeeds path.
        if os.path.exists(os.path.join(root, "auth401")) and (
            self.headers.get("PRIVATE-TOKEN") or self.headers.get("Authorization")
        ):
            self.send_response(401)
            self.end_headers()
            return
        if path.endswith("/discussions"):
            payload = body("disc")
        elif re.search(r"/merge_requests/[^/]+$", path):
            payload = body("mr")
        elif "/protected_branches/" in path:
            payload = body("prot")
        elif re.search(r"/projects/[^/]+$", path):
            payload = body("project")
        else:
            payload = None
        if payload is None:
            self.send_response(404)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(payload.encode())

    def log_message(self, *a):
        pass


with socketserver.TCPServer(("127.0.0.1", 0), Handler) as srv:
    with open(port_file, "w") as fh:
        fh.write(str(srv.server_address[1]))
    srv.serve_forever()
PY

  local waited=0
  while [ ! -s "$port_file" ] && [ "$waited" -lt 100 ]; do
    sleep 0.1
    waited=$((waited + 1))
  done

  [ -s "$port_file" ] || return 1
  PORT="$(cat "$port_file")"
  [ -n "$PORT" ] || return 1
  # Keep the PID so the server can actually be stopped. The socket number is not
  # a process id; using it as one leaks the server between cases.
  SERVER_PID=$!
  return 0
}

stop_server() {
  if [ -n "${SERVER_PID:-}" ]; then
    kill "$SERVER_PID" 2> /dev/null
    wait "$SERVER_PID" 2> /dev/null
    SERVER_PID=""
  fi
  PORT=""
  return 0
}

# run <want-rc> <label> - runs the gate against the stub and asserts the EXACT
# exit code.
#
# Exact, not merely non-zero: 1 means a gate is violated and 2 means it could not
# be verified. A test that only checked non-zero let a fetch failure masquerade
# as a rejection, which is the one distinction this gate exists to keep honest.
run() {
  local want="$1" label="$2"
  local got=0
  GITLAB_API_URL="http://127.0.0.1:${PORT}/api/v4" GITLAB_API_TOKEN=x \
    sh "$SCRIPT" 1 7 > /dev/null 2>&1 || got=$?
  if [ "$got" -eq "$want" ]; then
    ok "$label (rc=$got)"
  else
    no "$label (rc=$got, want $want)"
  fi
}

# write_json <name> <json> - (re)writes one stub response body.
write_json() {
  printf '%s' "$2" > "$TMP/$1.json"
}

# A clean forge: both settings armed, conversation resolved, force push off.
# Every case starts from here and changes exactly one thing, so a failure names
# the cause instead of "something in the fixture".
prime_clean() {
  write_json project '{"id":1,"only_allow_merge_if_all_discussions_are_resolved":true,"only_allow_merge_if_pipeline_succeeds":true}'
  write_json mr '{"iid":7,"target_branch":"main","blocking_discussions_resolved":true}'
  write_json prot '{"name":"main","allow_force_push":false}'
  write_json disc '[{"id":"d1","notes":[{"author":{"username":"bot"},"resolvable":true,"resolved":true,"body":"answered"}]}]'
}

echo "Running merge-gates (conversation-resolved trigger) tests..."
setup
trap teardown EXIT

if [ -x "$SCRIPT" ]; then ok "check-merge-gates.sh is executable"; else no "check-merge-gates.sh is executable"; fi

# --- usage / argument errors fail closed ------------------------------------
if sh "$SCRIPT" > /dev/null 2>&1; then
  no "no args exits non-zero"
else
  ok "no args exits non-zero (fail-closed)"
fi
if sh "$SCRIPT" 1 > /dev/null 2>&1; then
  no "missing MR iid exits non-zero"
else
  ok "missing MR iid exits non-zero (fail-closed)"
fi

# --- explicit override ------------------------------------------------------
# The gate must be opt-out, not opt-in: an unrunnable gate in a fork MR or a
# local dry run needs an escape, and it has to be greppable.
if SKIP_MERGE_GATES_CHECK=1 sh "$SCRIPT" 1 7 > /dev/null 2>&1; then
  ok "SKIP_MERGE_GATES_CHECK=1 opts out"
else
  no "SKIP_MERGE_GATES_CHECK=1 opts out"
fi
# Only the exact value opts out - a stray "true" must not disable a gate.
if SKIP_MERGE_GATES_CHECK=true sh "$SCRIPT" 1 7 > /dev/null 2>&1; then
  no "SKIP_MERGE_GATES_CHECK=true does NOT opt out (exact match only)"
else
  ok "SKIP_MERGE_GATES_CHECK=true does NOT opt out (exact match only)"
fi

# --- no credentials ---------------------------------------------------------
# Without a token the settings cannot be read. Reading the public subset is not
# enough: anonymous responses omit the merge settings entirely, so a tokenless
# run would have to guess that they hold.
if env -u GITLAB_API_TOKEN -u CI_JOB_TOKEN sh "$SCRIPT" 1 7 > /dev/null 2>&1; then
  no "no token fails closed"
else
  ok "no token fails closed"
fi

# --- unreachable API must NOT pass ------------------------------------------
GITLAB_API_URL="http://127.0.0.1:1/api/v4" GITLAB_API_TOKEN=x \
  sh "$SCRIPT" 1 7 > /dev/null 2>&1
if [ $? -eq 2 ]; then
  ok "unreachable API fails closed with rc=2 (cannot-verify, not violation)"
else
  no "unreachable API fails closed with rc=2"
fi

if ! start_server "$TMP"; then
  no "stub server started"
else
  # --- the clean case is the baseline ---------------------------------------
  prime_clean
  run 0 "gates armed and conversation resolved PASSES"

  # --- the trigger itself: an open thread blocks the merge ------------------
  # This is the property the whole policy exists for. CI green is not enough,
  # and neither is an empty conversation - the answer has to be resolved.
  write_json mr '{"iid":7,"target_branch":"main","blocking_discussions_resolved":false}'
  run 1 "MR with unresolved discussions is BLOCKED"
  prime_clean

  # The summary field and the listing are independent reads. A green summary
  # beside an open thread in the listing must resolve in favour of the concrete
  # evidence, or the gate would pass on a stale field.
  write_json disc '[{"id":"d1","notes":[{"author":{"username":"bot"},"resolvable":true,"resolved":false,"body":"still open"}]}]'
  run 1 "open thread in the listing beats a resolved summary field"
  prime_clean

  # A non-resolvable note is not a thread to resolve. Counting it would block
  # every MR forever on a note nobody can resolve.
  write_json disc '[{"id":"d1","notes":[{"author":{"username":"bot"},"resolvable":false,"resolved":null,"body":"a plain comment"}]},{"id":"d2","notes":[{"author":{"username":"bot"},"resolvable":true,"resolved":true,"body":"answered"}]}]'
  run 0 "non-resolvable notes do not count as open threads"
  prime_clean

  # --- disarmed project policy ----------------------------------------------
  # The forge setting is the gate. If it is off, the merge button no longer
  # depends on the conversation, and the repo must notice rather than assume.
  write_json project '{"id":1,"only_allow_merge_if_all_discussions_are_resolved":false,"only_allow_merge_if_pipeline_succeeds":true}'
  run 1 "conversations-resolved requirement switched OFF is caught"
  prime_clean

  write_json project '{"id":1,"only_allow_merge_if_all_discussions_are_resolved":true,"only_allow_merge_if_pipeline_succeeds":false}'
  run 1 "pipeline-succeeds requirement switched OFF is caught"
  prime_clean

  write_json prot '{"name":"main","allow_force_push":true}'
  run 1 "force push enabled on the target branch is caught"
  prime_clean

  # --- unverifiable is a failure, not a pass -------------------------------
  # Absent fields are not "false" and not "true": the API stopped telling us.
  write_json project '{"id":1}'
  run 2 "project response missing the merge settings is rc=2"
  prime_clean

  write_json mr '{"iid":7,"target_branch":"main"}'
  run 2 "MR response missing blocking_discussions_resolved is rc=2"
  prime_clean

  write_json disc '{"error":"not an array"}'
  run 2 "discussions response that is not an array is rc=2"
  prime_clean

  # A full page may be truncated, so "clean" cannot be claimed from it.
  python3 - "$TMP/disc.json" << 'PY'
import json, sys
notes = [{"id": "d%d" % i, "notes": [{"author": {"username": "bot"}, "resolvable": True,
                                     "resolved": True, "body": "ok"}]} for i in range(100)]
json.dump(notes, open(sys.argv[1], "w"))
PY
  run 2 "a full page of discussions (possible truncation) is rc=2, not clean"
  prime_clean

  # A protected branch that cannot be read leaves published history unguarded.
  rm -f "$TMP/prot.json"
  run 2 "unreadable protected-branch settings are rc=2"
  prime_clean

  # --- a failed token must stay diagnosable --------------------------------
  # Both fetch attempts used to redirect into the SAME $err, so when the
  # authenticated request 401'd and the anonymous retry succeeded, the retry
  # overwrote the evidence and fetch returned 0 with nothing printed. An invalid
  # or expired CI_JOB_TOKEN then produced a clean-looking run and no clue why -
  # which is the state a real pipeline was stuck in. The authenticated error is
  # now kept and reported even when the anonymous read succeeds.
  touch "$TMP/auth401"
  # run() discards output, so invoke the gate directly to inspect stderr.
  OUT=$(GITLAB_API_URL="http://127.0.0.1:${PORT}/api/v4" GITLAB_API_TOKEN=x \
    sh "$SCRIPT" 1 7 2>&1) || true
  case "$OUT" in
    *401* | *"authenticated read"*) ok "a failed token attempt is still reported" ;;
    *) no "a failed token attempt is still reported" ;;
  esac
  rm -f "$TMP/auth401"
  prime_clean

  # And the fail-closed path must survive that change: when BOTH attempts fail,
  # fetch still has to return 2, or an unreadable gate would read as clean.
  #
  rm -f "$TMP/project.json"
  run 2 "unreadable project with no anonymous fallback is rc=2 (fail-closed kept)"
  prime_clean

  # A violation must not be masked by an unverifiable check in the same run:
  # the known violation is the more actionable finding.
  write_json mr '{"iid":7,"target_branch":"main","blocking_discussions_resolved":false}'
  rm -f "$TMP/prot.json"
  run 1 "a known violation outranks an unverifiable check (rc=1)"
  prime_clean

  stop_server
fi

teardown
trap - EXIT

echo "  ---"
echo "  Total: $((pass + fail))  Passed: $pass  Failed: $fail"
[ "$fail" -eq 0 ]

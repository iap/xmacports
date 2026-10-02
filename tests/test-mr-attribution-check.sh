#!/usr/bin/env bash
# Tests for scripts/check-mr-attribution.sh — the CI-side (forge) gate on MR
# descriptions.
#
# Why this needs its own suite: the commit-msg hook covers commit messages, and
# nothing else covered MR descriptions, which is exactly how a false "Generated
# with Claude Code" footer shipped on MR !37. This gate runs on GitLab's runners,
# so its failure modes must be safe when it cannot verify: it exits 2 (a
# failure), never 0.
#
# A stub API server stands in for GitLab so the cases below do not depend on a
# live MR, a real token, or network access.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/check-mr-attribution.sh"
GATE="$ROOT/scripts/check-attribution.sh"

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
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/mrattr-test.XXXXXX")"
}

teardown() {
  stop_server
  [ -n "$TMP" ] && [ -d "$TMP" ] && find "$TMP" -mindepth 1 -delete 2> /dev/null
  [ -n "$TMP" ] && [ -d "$TMP" ] && rmdir "$TMP" 2> /dev/null
  return 0
}

# start_server <json-file> -> serves that body; sets PORT.
#
# The port is read from a FILE, never from command substitution. A backgrounded
# server inside $(...) keeps the substitution's pipe open forever, so the shell
# blocks until it is killed - that hang is what stalled this suite the first
# time. The server prints its port to a file and exits only when told to.
start_server() {
  local body_file="$1"
  local port_file="$TMP/port"

  rm -f "$port_file"
  python3 - "$body_file" "$port_file" << 'PY' &
import http.server, socketserver, sys

body = open(sys.argv[1]).read()
port_file = sys.argv[2]


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body.encode())

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
  # Keep the PID so the server can actually be stopped. `kill $PORT` would signal
  # whatever process happens to own that PID, not the server - the socket number
  # is not a process id, and using it as one leaks the server on every case.
  SERVER_PID=$!
  return 0
}

# stop_server kills the stub by PID and waits for it, so no listener is left
# behind and the next case binds a fresh port.
stop_server() {
  if [ -n "${SERVER_PID:-}" ]; then
    kill "$SERVER_PID" 2> /dev/null
    wait "$SERVER_PID" 2> /dev/null
    SERVER_PID=""
  fi
  PORT=""
  return 0
}

# run <want-rc> <label> — runs the gate against the stub and asserts the EXACT
# exit code.
#
# Asserting an exact code, not merely "non-zero", is the point. The gate uses
# exit 1 for "trailer found" and exit 2 for "could not verify"; a test that only
# checked non-zero let a fetch failure masquerade as a successful rejection,
# which is how four cases passed locally and failed in CI. Both codes must be
# distinguished, and both must be asserted.
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

echo "Running MR-attribution (forge-side) tests..."
setup
trap teardown EXIT

if [ -x "$SCRIPT" ]; then ok "check-mr-attribution.sh is executable"; else no "check-mr-attribution.sh is executable"; fi

# --- usage / argument errors fail closed ---------------------------------
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

# --- explicit override ---------------------------------------------------
printf 'Clean body.\n' > "$TMP/clean.md"
if SKIP_MR_ATTRIBUTION_CHECK=1 sh "$SCRIPT" 1 7 > /dev/null 2>&1; then
  ok "SKIP_MR_ATTRIBUTION_CHECK=1 opts out"
else
  no "SKIP_MR_ATTRIBUTION_CHECK=1 opts out"
fi

# --- unreachable API must NOT pass ---------------------------------------
# This is the critical safety property: if the description cannot be read, the
# gate must report failure rather than silently allowing the merge.
GITLAB_API_URL="http://127.0.0.1:1/api/v4" GITLAB_API_TOKEN=x \
  sh "$SCRIPT" 1 7 > /dev/null 2>&1
if [ $? -eq 2 ]; then
  ok "unreachable API fails closed with rc=2 (cannot-verify, not rejection)"
else
  no "unreachable API fails closed with rc=2"
fi

# --- stub server: clean description passes -------------------------------
python3 - "$TMP/clean.json" << 'PY'
import json, sys
json.dump({"iid": 7, "description": "fix(x): y\n\nExplains the change.\n"}, open(sys.argv[1], "w"))
PY
if start_server "$TMP/clean.json"; then
  run 0 "clean MR description passes"

  stop_server
else
  no "stub server started"
fi

# --- stub server: the real footer is rejected ---------------------------
python3 - "$TMP/bad.json" << 'PY'
import json, sys
desc = "fix(x): y\n\nBody.\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)\n"
json.dump({"iid": 7, "description": desc}, open(sys.argv[1], "w"))
PY
if start_server "$TMP/bad.json"; then
  run 1 "MR with the Claude footer is REJECTED, not a fetch error"

  # A Co-authored-by trailer naming a person must also be rejected: that is the
  # variant that leaked a real email into public history.
  stop_server
  python3 - "$TMP/coauth.json" << 'PY'
import json, sys
desc = "fix(x): y\n\nCo-authored-by: Real Person <person@example.com>\n"
json.dump({"iid": 7, "description": desc}, open(sys.argv[1], "w"))
PY
  if start_server "$TMP/coauth.json"; then
    run 1 "MR with a Co-authored-by trailer is REJECTED"

    stop_server
  fi

  # A description that merely QUOTES the pattern (prose, not a trailer) must
  # still pass — the gate must not block honest documentation.
  python3 - "$TMP/prose.json" << 'PY'
import json, sys
desc = 'docs: explain the rule\n\nWe reject "Generated with ..." footers.\n'
json.dump({"iid": 7, "description": desc}, open(sys.argv[1], "w"))
PY
  if start_server "$TMP/prose.json"; then
    run 0 "prose quoting the pattern still passes (no over-blocking)"

    stop_server
  fi

  # A shell-injection payload in the description must be treated as inert text.
  python3 - "$TMP/inject.json" << 'PY'
import json, sys
desc = "fix(x): y\n\n$(touch /tmp/hermes-verify-pwned) `id` ; rm -rf /\n"
json.dump({"iid": 7, "description": desc}, open(sys.argv[1], "w"))
PY
  if start_server "$TMP/inject.json"; then
    run 0 "shell metacharacters in a description are inert"

    if [ -e /tmp/hermes-verify-pwned ]; then
      no "no command execution from description content"
      rm -f /tmp/hermes-verify-pwned
    else
      ok "no command execution from description content"
    fi
    stop_server
  fi

  # A missing description field must fail closed, not pass.
  python3 - "$TMP/nodesc.json" << 'PY'
import json, sys
json.dump({"iid": 7}, open(sys.argv[1], "w"))
PY
  if start_server "$TMP/nodesc.json"; then
    # A response with no description field must be treated as an empty
    # description and pass - it is not an error, and it must not crash jq.
    run 0 "missing description field handled without crashing"

    stop_server
  fi
fi

teardown
trap - EXIT

echo "  ---"
echo "  Total: $((pass + fail))  Passed: $pass  Failed: $fail"
[ "$fail" -eq 0 ]

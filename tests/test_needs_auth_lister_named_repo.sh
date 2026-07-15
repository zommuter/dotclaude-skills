#!/usr/bin/env bash
# roadmap:b8c2 — `gather-human-backlog.sh --needs-auth <repo>` (EXPLICIT repo-name arg)
# must not crash. Follow-up defect on the shipped id:1750 offline lister.
#
# WHY (dead-letters routed:2365 + routed:8653, surfaced by relay-doctor 2026-07-15): the
# named-arg branch of `run_needs_auth_lister` calls
#   list_needs_auth_repo "$name" "${PATH_OF[$name]:-$SRC_DIR/$name}"
# and `list_needs_auth_repo` opens with the single-line declaration
#   local name="$1" path="$2" file="$path/REVIEW_ME.md"
# Bash expands ALL the RHS words of one `local` command BEFORE any of its assignments take
# effect, so `$path` in the `file=` word resolves against the CALLER's scope, not the
# just-assigned local. The default (no-arg) branch happens to have a `path` loop variable
# in scope (leaked), so it survives; the named-arg branch (`for name in "$@"`) has NO
# `path` in scope, so under `set -u` the run dies with
#   line 362: path: unbound variable
# Only the no-arg all-repos form works; every explicit `--needs-auth <repo>` invocation
# crashes. Fix: assign `path` before referencing it (split the `local`).
#
# Asserts (hermetic — temp relay.toml + temp own repos, mirrors test_needs_auth_lister.sh):
#   (1) `--needs-auth repoNA` (explicit repo name) exits 0 (no unbound-variable crash);
#   (2) it lists that repo's conforming @needs-auth box with all four field values;
#   (3) stderr carries NO `unbound variable` diagnostic.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/relay/scripts/gather-human-backlog.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SCRIPT" ]] || fail "gather-human-backlog.sh not found/executable at $SCRIPT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/src/repoNA"
cat >"$tmp/src/repoNA/REVIEW_ME.md" <<'MD'
# REVIEW_ME

- [ ] Link the Signal linked device @needs-auth <!-- id:e588 -->
  - what-secret: SENTINEL_SIGNAL_QR the linked-device QR code
  - where-it-goes: SENTINEL_WHERE scanned by signal-cli on zomni
  - exact-command: `signal-cli link -n SENTINEL_CMD_relay`
  - why: SENTINEL_WHY zkm-signal ingest strands without a linked device
MD

cat >"$tmp/relay.toml" <<'TOML'
[repos.repoNA]
classification = "own"
confirmed = "2026-01-01"
TOML

out="$(RELAY_TOML="$tmp/relay.toml" SRC_DIR="$tmp/src" bash "$SCRIPT" --needs-auth repoNA 2>"$tmp/err")" && rc=0 || rc=$?

# (1) exit 0 — no unbound-variable crash on the explicit repo-name arg.
[[ $rc -eq 0 ]] || fail "--needs-auth repoNA should exit 0, got $rc (stderr: $(cat "$tmp/err"))"

# (3) no unbound-variable diagnostic on stderr.
if grep -qi 'unbound variable' "$tmp/err"; then
  fail "--needs-auth repoNA crashed with an unbound-variable error (stderr: $(cat "$tmp/err"))"
fi

# (2) the box surfaces with its four field values (same content as the no-arg form).
grep -q 'repoNA'             <<<"$out" || fail "repo name not shown for the @needs-auth box (out: $out)"
grep -q 'SENTINEL_SIGNAL_QR' <<<"$out" || fail "what-secret value missing (out: $out)"
grep -q 'SENTINEL_WHERE'     <<<"$out" || fail "where-it-goes value missing (out: $out)"
grep -q 'SENTINEL_CMD_relay' <<<"$out" || fail "exact-command value missing (out: $out)"
grep -q 'SENTINEL_WHY'       <<<"$out" || fail "why value missing (out: $out)"

pass "b8c2: --needs-auth <repo> lists the repo's @needs-auth box without an unbound-variable crash"
echo "ok"

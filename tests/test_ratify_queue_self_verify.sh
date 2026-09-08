#!/usr/bin/env bash
# id:4d65 — seam of id:7408 (option A+D, owner-ratified 2026-09-02).
#
# fails-against: ratify-queue.sh's `list` before this seam reports EVERY pending entry as
# pending, even one whose recorded merge sha the remote has ALREADY published (e.g. the
# owner pushed by hand without ever running `resolve`) — a self-verifiable false positive.
#
# NO `# roadmap:` HEADER ON PURPOSE: this is a seam of a decomposed HARD item (id:7408),
# not itself gated on a still-open ROADMAP checkbox, so a failure here always counts.
#
# WHAT IS UNDER TEST. `list` must self-verify each PENDING entry's recorded merge sha
# against its repo's remote(s), using the SAME read-only path `resolve` already uses
# (_verify_remote/_verify_pending) — WITHOUT mutating the queue file. An entry the remote
# demonstrably carries is reported as landed (excluded from the default pending listing,
# not counted, not boxed for the human backlog) rather than pending. An entry the remote
# does NOT carry still reports pending exactly as before. The queue's stored `status`
# field itself is untouched either way — `resolve` remains the only writer.
#
# Hermetic: mktemp -d for everything, bare remotes on local paths, RELAY_RATIFICATION_QUEUE
# overridden. Never touches ~/.config/relay, ~/.claude, real repos, or the network.
# fails-against-rev: 7db19a37cbbb0b874ac96fc03211c431a004fba7 -- relay/scripts/ratify-queue.sh
# fails-against-assertion: list --tsv still boxes a self-verified-landed entry
#   (This file is a non-exiting ACCUMULATOR: against the pre-seam ratify-queue.sh four
#   assertions fire, and the repo rule is that the declaration must match the LAST one, not
#   the first -- matching any-of degrades the guarantee to little more than exit status.
#   The intuitive choice here is the default-listing assertion, which fires FIRST; it is
#   wrong for that reason. Verified by running verify-negative-cases.py on this file once
#   id:4d65 was ticked and the roadmap carve-out lifted.)

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RQ="$ROOT/relay/scripts/ratify-queue.sh"

fails=0
pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; fails=$((fails + 1)); }

[[ -x "$RQ" ]] || { echo "FAIL: ratify-queue.sh missing/not executable: $RQ"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# fixture git repos must be immune to the developer's global hooksPath / identity
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null

git_q() { git "$@" >/dev/null 2>&1; }

make_repo() {
  local n="$1" r="$T/$1"
  git_q init --bare "$T/$1.git"
  git_q init -b main "$r"
  git_q -C "$r" config user.email fixture@example.invalid
  git_q -C "$r" config user.name fixture
  echo base > "$r/f"
  git_q -C "$r" add -A
  git_q -C "$r" commit -m base
  git_q -C "$r" remote add origin "$T/$1.git"
  git_q -C "$r" push origin main
  printf '%s' "$r"
}

# record <repo> <path> <merged> <ckpt> [status] [pending_remotes-csv]
# The exact shape integrate.sh step 8b writes.
record() {
  python3 - "$1" "$2" "$3" "$4" "${5:-pending}" "${6:-}" <<'PYEOF'
import json, sys
repo, path, merged, ckpt, status, pending = sys.argv[1:7]
rec = {
    "kind": "ratification-pending", "id": "id:4d44",
    "ts": "2026-09-02T09:00:00Z", "status": status,
    "repo": repo, "path": path, "branch": "relay/x", "worktree": path + "/.wt",
    "merged": merged, "ckpt": ckpt, "run": "relay-20260902-090000",
    "verdict": "execute", "ids": ["id:aaaa", "id:bbbb"], "bump": "",
    "substantive": "yes", "summary": "closed the thing", "label": "reviewer (claude-opus-5)",
    "push": "deferred",
    "action": "review the merge, then push it: git -C %s push --follow-tags" % path,
}
if pending:
    rec["pending_remotes"] = [r for r in pending.split(",") if r]
print(json.dumps(rec, ensure_ascii=False))
PYEOF
}

field_of() { # <queue> <merged-sha> <field>
  python3 - "$1" "$2" "$3" <<'PYEOF'
import json, sys
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    try:
        r = json.loads(line)
    except Exception:
        continue
    if r.get("merged") == sys.argv[2]:
        print(r.get(sys.argv[3], "<missing>"))
        break
else:
    print("<no-such-record>")
PYEOF
}

# ─────────────────────────────────────────────────────────────────────────────
# FIXTURES.
#   alpha (M1): merge already PUSHED to origin by hand -- self-verifiably landed.
#   beta  (M2): merge still LOCAL-ONLY -- must keep reporting pending.
# ─────────────────────────────────────────────────────────────────────────────
R1="$(make_repo alpha)"
echo one >> "$R1/f"; git_q -C "$R1" commit -am work1
M1="$(git -C "$R1" rev-parse HEAD)"
CK1="relay-ckpt-20260902-1000"
git_q -C "$R1" tag -a -m ckpt "$CK1"
git_q -C "$R1" push origin main --tags   # the owner already pushed by hand

R2="$(make_repo beta)"
echo two >> "$R2/f"; git_q -C "$R2" commit -am work2
M2="$(git -C "$R2" rev-parse HEAD)"
CK2="relay-ckpt-20260902-1100"
git_q -C "$R2" tag -a -m ckpt "$CK2"
# deliberately NOT pushed

Q="$T/q.jsonl"; export RELAY_RATIFICATION_QUEUE="$Q"
{ record alpha "$R1" "$M1" "$CK1" pending origin
  record beta  "$R2" "$M2" "$CK2" pending origin
} > "$Q"
BEFORE_Q="$(cat "$Q")"

# ─────────────────────────────────────────────────────────────────────────────
# 1. DEFAULT `list` -- the landed entry is reported landed and EXCLUDED from the
#    pending listing; the still-unpushed neighbour still reports pending.
# ─────────────────────────────────────────────────────────────────────────────
out="$("$RQ" list 2>&1)"; rc=$?
[[ $rc -eq 0 ]] || fail "list exited $rc: $out"

grep -q "$CK1" <<< "$out" \
  && fail "a self-verified-landed entry still shows in the default pending listing:"$'\n'"$out" \
  || pass "the self-verified-landed entry is excluded from the default pending listing"

grep -q "$CK2" <<< "$out" \
  && pass "the still-unpushed neighbour still reports pending" \
  || fail "the genuinely-pending neighbour vanished from list:"$'\n'"$out"

grep -q '1 pending entr' <<< "$out" \
  && pass "the pending COUNT reflects only the genuinely-outstanding entry (1, not 2)" \
  || fail "pending count did not drop to 1:"$'\n'"$out"

# ─────────────────────────────────────────────────────────────────────────────
# 2. `list --all` -- the landed entry is still VISIBLE (never vanished) but marked
#    distinctly from a genuinely-outstanding pending row.
# ─────────────────────────────────────────────────────────────────────────────
all_out="$("$RQ" list --all 2>&1)"
grep -q "$CK1" <<< "$all_out" \
  && pass "list --all still shows the self-verified-landed entry" \
  || fail "list --all lost the self-verified-landed entry:"$'\n'"$all_out"
grep -q 'self-verified LANDED' <<< "$all_out" \
  && pass "list --all distinguishes it as self-verified LANDED" \
  || fail "list --all does not distinguish the self-verified entry:"$'\n'"$all_out"

# ─────────────────────────────────────────────────────────────────────────────
# 3. `list --tsv` (the /relay human backlog feed) -- no box for a landed entry.
# ─────────────────────────────────────────────────────────────────────────────
tsv="$("$RQ" list --tsv 2>&1)"
grep -q "$CK1" <<< "$tsv" \
  && fail "list --tsv still boxes a self-verified-landed entry: $tsv" \
  || pass "list --tsv emits no box for the self-verified-landed entry"
grep -q "${M2:0:12}" <<< "$tsv" \
  && pass "list --tsv still boxes the genuinely-pending neighbour" \
  || fail "list --tsv lost the genuinely-pending neighbour: $tsv"

# ─────────────────────────────────────────────────────────────────────────────
# 4. READ-ONLY -- list never mutates the queue file, in either invocation. The
#    stored `status` field is untouched; only `resolve` may write it (file header).
# ─────────────────────────────────────────────────────────────────────────────
AFTER_Q="$(cat "$Q")"
[[ "$AFTER_Q" == "$BEFORE_Q" ]] \
  && pass "the queue file is byte-identical after list/list --all/list --tsv (list never writes)" \
  || fail "list mutated the queue file"
[[ "$(field_of "$Q" "$M1" status)" == pending ]] \
  && pass "the self-verified-landed entry's stored status is STILL pending (resolve is the only writer)" \
  || fail "list itself flipped the stored status to $(field_of "$Q" "$M1" status)"

# ─────────────────────────────────────────────────────────────────────────────
# 5. `resolve` still works normally on the self-verified-landed entry (this seam
#    only changes what `list` REPORTS, not the resolve path itself).
# ─────────────────────────────────────────────────────────────────────────────
out="$("$RQ" resolve "$CK1" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] \
  && pass "resolve still succeeds on the (already-landed) entry" \
  || fail "resolve failed on a genuinely-landed entry: rc=$rc $out"
[[ "$(field_of "$Q" "$M1" status)" == resolved ]] \
  && pass "after an explicit resolve, the stored status is resolved" \
  || fail "resolve did not update status: $(field_of "$Q" "$M1" status)"

printf '\n'
if (( fails )); then
  printf '%d assertion(s) FAILED\n' "$fails"
  exit 1
fi
printf 'all assertions passed\n'

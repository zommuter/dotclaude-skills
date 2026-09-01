#!/usr/bin/env bash
# id:99b7 half (b) — the ratification queue's RETIRE path.
#
# fails-against: relay/scripts/ratify-queue.sh with only `list|show|verify|resolve`.
#
# NO `# roadmap:` HEADER ON PURPOSE: this is defect/feature work with no ROADMAP item, so
# there is no checkbox for the runner's expected-red rule to consult and its failures must
# always count as real failures.
#
# WHAT IS UNDER TEST. `resolve` verifies the remote actually carries the recorded merge sha
# and REFUSES otherwise. That is correct and load-bearing — but it leaves no way to close an
# entry whose sha can NEVER land (a read-only `git://` upstream that is not a publish target;
# a merge commit that no longer exists in any object store). Six such entries exist in the
# real queue today. The sanctioned close is a SEPARATE verb, `retire <key> --reason TEXT`:
#   * `--reason` is MANDATORY — an unexplained close is what makes the queue untrustworthy.
#   * it is NOT `resolve --force` — a forced resolve would let a real UN-PUSHED merge be
#     marked ratified, the single thing this queue exists to prevent. So this file also
#     re-asserts the resolve guard, to prove it was not weakened as a side effect.
#   * a retired entry is DISTINGUISHABLE from a resolved one, in the store and in `--all`.
#
# Hermetic: mktemp -d for everything, bare remotes on local paths, RELAY_RATIFICATION_QUEUE
# overridden. Never touches ~/.config/relay, ~/.claude, real repos, or the network.
# fails-against-rev: ecfbd0b77630 -- relay/SKILL.md relay/scripts/ratify-queue.sh
# fails-against-assertion: relay/SKILL.md still describes only resolve

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
    "ts": "2026-08-21T09:00:00Z", "status": status,
    "repo": repo, "path": path, "branch": "relay/x", "worktree": path + "/.wt",
    "merged": merged, "ckpt": ckpt, "run": "relay-20260821-090000",
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

REASON='the merge commit is a read-only dangling object; ids landed via other paths'

# ─────────────────────────────────────────────────────────────────────────────
# 0. FIXTURE — one pending entry whose merge is local-only (the remote does NOT
#    carry it). This is deliberately the SAME shape resolve must keep refusing.
# ─────────────────────────────────────────────────────────────────────────────
R1="$(make_repo alpha)"
echo one >> "$R1/f"; git_q -C "$R1" commit -am work1
M1="$(git -C "$R1" rev-parse HEAD)"
CK1="relay-ckpt-20260826-1309"
git_q -C "$R1" tag -a -m ckpt "$CK1"

Q="$T/q.jsonl"; export RELAY_RATIFICATION_QUEUE="$Q"
record alpha "$R1" "$M1" "$CK1" pending origin > "$Q"

# ─────────────────────────────────────────────────────────────────────────────
# 1. THE GUARD IS NOT WEAKENED — resolve still refuses an unlanded merge.
#    Asserted BEFORE retire exists in the flow, and again after retiring, so a
#    `resolve --force` smuggled in under another name would be caught here.
# ─────────────────────────────────────────────────────────────────────────────
out="$("$RQ" resolve "$CK1" 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" == *"NOT LANDED"* ]] \
  && pass "resolve STILL refuses an entry the remote does not carry (guard intact)" \
  || fail "resolve accepted an unlanded merge — the guard was weakened: rc=$rc $out"

# and there is no --force escape hatch on resolve
out="$("$RQ" resolve "$CK1" --force 2>&1)"; rc=$?
[[ $rc -ne 0 ]] \
  && pass "resolve has no --force escape hatch (rejected, rc=$rc)" \
  || fail "resolve --force succeeded — a real un-pushed merge can be marked ratified"

# ─────────────────────────────────────────────────────────────────────────────
# 2. --reason IS MANDATORY.
# ─────────────────────────────────────────────────────────────────────────────
out="$("$RQ" retire "$CK1" 2>&1)"; rc=$?
[[ $rc -ne 0 ]] \
  && pass "retire without --reason is REFUSED (rc=$rc)" \
  || fail "retire closed an entry with no stated reason — the queue becomes untrustworthy"
[[ "$out" == *reason* ]] \
  && pass "the refusal names --reason" \
  || fail "refusal does not mention --reason: $out"
[[ "$(field_of "$Q" "$M1" status)" == pending ]] \
  && pass "a refused retire leaves the entry PENDING (queue untouched)" \
  || fail "refused retire mutated the record to $(field_of "$Q" "$M1" status)"

# an empty --reason is the same thing wearing a flag
out="$("$RQ" retire "$CK1" --reason "" 2>&1)"; rc=$?
[[ $rc -ne 0 ]] \
  && pass "retire --reason '' is REFUSED too (an empty reason is no reason)" \
  || fail "retire accepted an empty --reason"
[[ "$(field_of "$Q" "$M1" status)" == pending ]] \
  && pass "the empty-reason refusal also left the entry PENDING" \
  || fail "empty-reason retire mutated the record"

# ─────────────────────────────────────────────────────────────────────────────
# 3. KEY DISCIPLINE — unknown and ambiguous keys refuse loudly, never guess.
# ─────────────────────────────────────────────────────────────────────────────
out="$("$RQ" retire nosuchkey --reason "$REASON" 2>&1)"; rc=$?
[[ $rc -ne 0 ]] \
  && pass "retire refuses an UNKNOWN key (rc=$rc)" \
  || fail "retire accepted an unknown key: $out"

Q2="$T/q2.jsonl"
{ record alpha "$R1" "$M1" "$CK1" pending origin
  record beta  "$R1" "$M1" "relay-ckpt-20260826-1403" pending origin
} > "$Q2"
out="$(RELAY_RATIFICATION_QUEUE="$Q2" "$RQ" retire "${M1:0:8}" --reason "$REASON" 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" == *AMBIGUOUS* ]] \
  && pass "an AMBIGUOUS key is refused loudly, never guessed" \
  || fail "ambiguous key not refused: rc=$rc $out"
[[ "$(grep -c 'retired' "$Q2")" -eq 0 ]] \
  && pass "the ambiguous refusal retired NOTHING" \
  || fail "an ambiguous retire mutated a record"

# a queue this consumer cannot fully read is not acted on at all
Q3="$T/q3.jsonl"
{ printf '%s\n' 'this is not json at all'; record alpha "$R1" "$M1" "$CK1" pending origin; } > "$Q3"
out="$(RELAY_RATIFICATION_QUEUE="$Q3" "$RQ" retire "$CK1" --reason "$REASON" 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" == *MALFORMED* ]] \
  && pass "retire refuses to act on a queue holding unreadable records" \
  || fail "retire acted on a partially-unreadable queue: rc=$rc $out"
[[ "$(grep -c . "$Q3")" -eq 2 ]] \
  && pass "the malformed neighbour survives verbatim" \
  || fail "queue lost lines: $(grep -c . "$Q3") of 2 remain"

# ─────────────────────────────────────────────────────────────────────────────
# 4. THE HAPPY PATH — retire records status, reason and a timestamp.
# ─────────────────────────────────────────────────────────────────────────────
out="$("$RQ" retire "$CK1" --reason "$REASON" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] \
  && pass "retire SUCCEEDS with a reason (rc=0)" \
  || fail "retire failed: rc=$rc $out"
[[ "$out" == *RETIRED* ]] \
  && pass "retire says RETIRED on stdout (not 'resolved')" \
  || fail "retire output does not say RETIRED: $out"
[[ "$(field_of "$Q" "$M1" status)" == retired ]] \
  && pass "the record's status is 'retired' — DISTINCT from 'resolved'" \
  || fail "status after retire is $(field_of "$Q" "$M1" status), want retired"
[[ "$(field_of "$Q" "$M1" retire_reason)" == "$REASON" ]] \
  && pass "the stated reason is recorded verbatim (retire_reason)" \
  || fail "retire_reason: $(field_of "$Q" "$M1" retire_reason)"
[[ "$(field_of "$Q" "$M1" retired_at)" =~ ^20[0-9]{2}- ]] \
  && pass "retire stamps retired_at (durable trace of WHEN it was written off)" \
  || fail "retired_at missing/odd: $(field_of "$Q" "$M1" retired_at)"

# a retire must NEVER leave evidence that looks like a verified landing
for f in verified_sha resolved_at resolved_remote resolved_ref verification; do
  [[ "$(field_of "$Q" "$M1" "$f")" == "<missing>" ]] \
    || fail "retire wrote '$f' — a retired entry must not carry landing evidence"
done
pass "retire writes NO landing evidence (no verified_sha/resolved_* /verification)"

# the record survives — marked, not deleted
[[ "$(grep -c . "$Q")" -eq 1 ]] \
  && pass "the entry is MARKED in place, never vanished" \
  || fail "queue line count after retire: $(grep -c . "$Q")"

# ─────────────────────────────────────────────────────────────────────────────
# 5. VISIBILITY — gone from `list`, distinguishable in `list --all`.
# ─────────────────────────────────────────────────────────────────────────────
pend_out="$("$RQ" list 2>&1)"; prc=$?
[[ $prc -eq 0 ]] || fail "list exited $prc after a retire"
grep -q "$CK1" <<< "$pend_out" \
  && fail "a retired entry still shows in the default (pending) listing" \
  || pass "a retired entry no longer shows as pending"

all_out="$("$RQ" list --all 2>&1)"
grep -q "$CK1" <<< "$all_out" \
  && pass "a retired entry is still visible under --all (marked, not vanished)" \
  || fail "retired entry lost from --all:"$'\n'"$all_out"
grep -q 'retired' <<< "$all_out" \
  && pass "list --all names the RETIRED status — distinguishable from resolved" \
  || fail "list --all does not distinguish retired from resolved:"$'\n'"$all_out"
grep -q 'read-only' <<< "$all_out" \
  && pass "list --all surfaces the recorded reason (auditable at a glance)" \
  || fail "list --all does not show the retire reason:"$'\n'"$all_out"

# --tsv is the /relay human collector contract: a retired entry must not be a human box
tsv="$("$RQ" list --tsv 2>/dev/null)"
[[ -z "$(tr -d '[:space:]' <<< "$tsv")" ]] \
  && pass "list --tsv emits no row for a retired entry (not human backlog any more)" \
  || fail "list --tsv still emits a row for a retired entry: $tsv"

# `show` must surface the retirement, not present it as an outstanding push
sh_out="$("$RQ" show "$CK1" 2>&1)"; src=$?
[[ $src -eq 0 ]] \
  && pass "show still finds a retired entry (rc=0)" \
  || fail "show could not find a retired entry: rc=$src $sh_out"
[[ "$sh_out" == *retired* && "$sh_out" == *"read-only"* ]] \
  && pass "show reports status=retired together with the reason" \
  || fail "show does not surface the retirement:"$'\n'"$sh_out"

# ─────────────────────────────────────────────────────────────────────────────
# 6. A SECOND RETIRE IS A LOUD REFUSAL, and so is resolving a retired entry.
# ─────────────────────────────────────────────────────────────────────────────
before="$(cat "$Q")"
out="$("$RQ" retire "$CK1" --reason "some other reason" 2>&1)"; rc=$?
[[ $rc -ne 0 ]] \
  && pass "a SECOND retire of the same entry is refused (rc=$rc)" \
  || fail "retire silently re-retired an already-retired entry: $out"
[[ "$out" == *retired* ]] \
  && pass "the refusal says the entry is already retired (not 'no such key')" \
  || fail "second-retire refusal is unclear: $out"
[[ "$(cat "$Q")" == "$before" ]] \
  && pass "the second retire changed NOTHING (reason not overwritten)" \
  || fail "a second retire rewrote the record"

out="$("$RQ" resolve "$CK1" 2>&1)"; rc=$?
[[ $rc -ne 0 ]] \
  && pass "resolve refuses an already-RETIRED entry (rc=$rc)" \
  || fail "resolve re-opened a retired entry as resolved: $out"

# ─────────────────────────────────────────────────────────────────────────────
# 7. RETIRE NEVER TOUCHES A NEIGHBOUR — including a malformed one, and including
#    an entry that is genuinely still pending.
# ─────────────────────────────────────────────────────────────────────────────
R2="$(make_repo beta)"
echo w >> "$R2/f"; git_q -C "$R2" commit -am work
M2="$(git -C "$R2" rev-parse HEAD)"
CK2="relay-ckpt-20260826-1454"
git_q -C "$R2" tag -a -m ckpt "$CK2"

Q4="$T/q4.jsonl"; export RELAY_RATIFICATION_QUEUE="$Q4"
{ record alpha "$R1" "$M1" "$CK1" pending origin
  record beta  "$R2" "$M2" "$CK2" pending origin
} > "$Q4"
"$RQ" retire "$CK1" --reason "$REASON" >/dev/null 2>&1
[[ "$(field_of "$Q4" "$M2" status)" == pending ]] \
  && pass "the untouched neighbour is still PENDING after a retire" \
  || fail "retiring one entry mutated its neighbour to $(field_of "$Q4" "$M2" status)"
[[ "$(grep -c . "$Q4")" -eq 2 ]] \
  && pass "both lines survive the rewrite (no entry silently dropped)" \
  || fail "queue lost lines: $(grep -c . "$Q4") of 2 remain"
pend2="$("$RQ" list 2>&1)"
grep -q "$CK2" <<< "$pend2" \
  && pass "the pending neighbour is still reported by list" \
  || fail "the pending neighbour vanished from list:"$'\n'"$pend2"

# ...and the guard still holds for that neighbour: it is unpushed, so resolve refuses.
out="$("$RQ" resolve "$CK2" 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" == *"NOT LANDED"* ]] \
  && pass "resolve STILL refuses the unlanded neighbour AFTER a retire landed nearby" \
  || fail "the retire path weakened resolve's remote check: rc=$rc $out"

# ─────────────────────────────────────────────────────────────────────────────
# 8. USAGE / DISCOVERABILITY — retire is documented where the owner will look.
# ─────────────────────────────────────────────────────────────────────────────
help_out="$("$RQ" --help 2>&1)"
[[ "$help_out" == *"retire"* && "$help_out" == *"--reason"* ]] \
  && pass "--help documents retire and its mandatory --reason" \
  || fail "retire is absent from the usage block:"$'\n'"$help_out"
bad="$("$RQ" nosuchsubcommand 2>&1)"
[[ "$bad" == *retire* ]] \
  && pass "the unknown-subcommand error lists retire" \
  || fail "unknown-subcommand error does not list retire: $bad"
grep -q 'ratify-queue.sh retire' "$ROOT/relay/SKILL.md" \
  && pass "relay/SKILL.md's human-mode bullet names the retire path" \
  || fail "relay/SKILL.md still describes only resolve"

printf '\n'
if (( fails )); then
  printf '%d assertion(s) FAILED\n' "$fails"
  exit 1
fi
printf 'all assertions passed\n'

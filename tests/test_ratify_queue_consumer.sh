#!/usr/bin/env bash
# fails-against: relay/scripts/ratify-queue.sh absent (the id:4d44 ratification queue had a
# producer — integrate.sh step 8b — and NO consumer), and against gather-human-backlog.sh
# without its `ratification_pending` emitter.
#
# NO `# roadmap:` HEADER ON PURPOSE: the consumer is not a ROADMAP item, so there is no
# checkbox for the runner's expected-red rule to consult. Its failures must therefore
# always count as real failures — which is what omitting the header buys.
#
# What is under test — the failure that matters is marking an entry RESOLVED when the push
# did not actually land. `git-lock-push.sh` can exit 0 having pushed nothing (id:f5d9(a),
# id:dc4f), so resolution here is not allowed to trust any exit code: it must interrogate
# the remote with `git ls-remote` and compare against the RECORDED sha.
#
# Hermetic: mktemp -d for everything, bare remotes on local paths, RELAY_RATIFICATION_QUEUE
# and RELAY_TOML/SRC_DIR overridden. Never touches ~/.config/relay, ~/.claude, real repos,
# or the network.
# fails-against-rev: 3c13d2c8df57 -- Makefile relay/SKILL.md relay/references/human.md relay/scripts/gather-human-backlog.sh relay/scripts/ratify-queue.sh
# fails-against-assertion: ratify-queue.sh missing/not executable:

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RQ="$ROOT/relay/scripts/ratify-queue.sh"
GATHER="$ROOT/relay/scripts/gather-human-backlog.sh"

fails=0
pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; fails=$((fails + 1)); }

[[ -x "$RQ" ]] || { echo "FAIL: ratify-queue.sh missing/not executable: $RQ"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# fixture git repos must be immune to the developer's global hooksPath / identity
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null

git_q() { git "$@" >/dev/null 2>&1; }

# make_repo <name> -> $T/<name> (with a bare remote at $T/<name>.git, main pushed)
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

# record <repo> <path> <merged> <ckpt> [status] -> one JSON line, exactly the shape
# integrate.sh step 8b writes (read from that producer, not invented here).
record() {
  python3 - "$1" "$2" "$3" "$4" "${5:-pending}" <<'PYEOF'
import json, sys
repo, path, merged, ckpt, status = sys.argv[1:6]
print(json.dumps({
    "kind": "ratification-pending", "id": "id:4d44",
    "ts": "2026-08-21T09:00:00Z", "status": status,
    "repo": repo, "path": path, "branch": "relay/x", "worktree": path + "/.wt",
    "merged": merged, "ckpt": ckpt, "run": "relay-20260821-090000",
    "verdict": "execute", "ids": ["id:aaaa", "id:bbbb"], "bump": "",
    "substantive": "yes", "summary": "closed the thing", "label": "reviewer (claude-opus-5)",
    "push": "deferred",
    "action": "review the merge, then push it: git -C %s push --follow-tags" % path,
}, ensure_ascii=False))
PYEOF
}

status_of() { # <queue> <merged-sha> -> the record's status field
  python3 - "$1" "$2" <<'PYEOF'
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
        print(r.get("status"))
        break
else:
    print("<no-such-record>")
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
# 1. EMPTY QUEUE — no file at all, and an existing-but-empty file.
# ─────────────────────────────────────────────────────────────────────────────
export RELAY_RATIFICATION_QUEUE="$T/empty/q.jsonl"
out="$("$RQ" list 2>&1)"; rc=$?
if [[ $rc -eq 0 && "$out" == *"no pending"* ]]; then
  pass "list on a MISSING queue file is a clean empty report (rc=0)"
else
  fail "list on a missing queue file: rc=$rc out=$out"
fi
mkdir -p "$T/empty"; : > "$RELAY_RATIFICATION_QUEUE"
out="$("$RQ" list 2>&1)"; rc=$?
[[ $rc -eq 0 && "$out" == *"no pending"* ]] \
  && pass "list on an EMPTY queue file is a clean empty report (rc=0)" \
  || fail "list on an empty queue file: rc=$rc out=$out"

# ─────────────────────────────────────────────────────────────────────────────
# 2. LISTING A PENDING ENTRY — repo, ids, ckpt, merged sha, age all present.
# ─────────────────────────────────────────────────────────────────────────────
R1="$(make_repo alpha)"
echo one >> "$R1/f"; git_q -C "$R1" commit -am work1
M1="$(git -C "$R1" rev-parse HEAD)"
CK1="relay-ckpt-20260821-0900"
# ANNOTATED, like ckpt-tag.sh's real checkpoint tags — `push --follow-tags` carries only
# annotated tags, so a lightweight fixture tag would make the tag-presence check untestable.
git_q -C "$R1" tag -a -m ckpt "$CK1"

export RELAY_RATIFICATION_QUEUE="$T/q.jsonl"
record alpha "$R1" "$M1" "$CK1" > "$RELAY_RATIFICATION_QUEUE"

out="$("$RQ" list 2>&1)"; rc=$?
ok=1
[[ $rc -eq 0 ]] || ok=0
for want in alpha "$CK1" "${M1:0:12}" id:aaaa; do
  [[ "$out" == *"$want"* ]] || { ok=0; echo "  (list output missing '$want')"; }
done
grep -qE 'age=[0-9]+[mhd]' <<< "$out" || { ok=0; echo "  (list output has no age= field)"; }
(( ok )) && pass "list shows the pending entry with repo/ckpt/merged/ids/age" \
         || fail "list of a pending entry incomplete: rc=$rc"$'\n'"$out"

# --tsv keeps the 4-column gather contract
tsv="$("$RQ" list --tsv 2>/dev/null)"
cols="$(awk -F'\t' 'NR==1{print NF}' <<< "$tsv")"
[[ "$cols" == 4 ]] \
  && pass "list --tsv emits exactly 4 tab-separated columns (gather contract)" \
  || fail "list --tsv emitted $cols columns, want 4: $tsv"
[[ "$(awk -F'\t' 'NR==1{print $3}' <<< "$tsv")" == ratification_pending ]] \
  && pass "list --tsv kind column is ratification_pending" \
  || fail "list --tsv kind column: $(awk -F'\t' 'NR==1{print $3}' <<< "$tsv")"
[[ "$(awk -F'\t' 'NR==1{print $4}' <<< "$tsv")" == *"push --follow-tags"* ]] \
  && pass "list --tsv box_summary carries the owner's exact push command" \
  || fail "list --tsv box_summary lacks the push command: $tsv"

# ─────────────────────────────────────────────────────────────────────────────
# 3. REFUSAL — the remote does NOT carry the recorded sha. THE test that matters.
# ─────────────────────────────────────────────────────────────────────────────
out="$("$RQ" resolve "$CK1" 2>&1)"; rc=$?
[[ $rc -ne 0 ]] \
  && pass "resolve REFUSES (rc=$rc) while the merge is still local-only" \
  || fail "resolve returned 0 for a merge the remote does NOT carry — this is the failure that matters"
[[ "$out" == *"NOT LANDED"* ]] \
  && pass "the refusal is LOUD and says NOT LANDED" \
  || fail "refusal message unclear: $out"
[[ "$(status_of "$RELAY_RATIFICATION_QUEUE" "$M1")" == pending ]] \
  && pass "a refused resolve leaves the entry PENDING (queue untouched)" \
  || fail "refused resolve mutated the record to $(status_of "$RELAY_RATIFICATION_QUEUE" "$M1")"

# verify is the read-only twin and agrees
"$RQ" verify "$CK1" >/dev/null 2>&1; vrc=$?
[[ $vrc -ne 0 ]] \
  && pass "verify (read-only) also reports NOT landed (rc=$vrc)" \
  || fail "verify returned 0 for an unpushed merge"

# ─────────────────────────────────────────────────────────────────────────────
# 3b. REFUSAL — remote reachable and moved, but WITHOUT this merge.
#     (an unrelated commit sits on the remote head; the recorded sha is absent)
# ─────────────────────────────────────────────────────────────────────────────
SIDE="$T/alpha-side"
git_q clone "$T/alpha.git" "$SIDE"
git_q -C "$SIDE" config user.email fixture@example.invalid
git_q -C "$SIDE" config user.name fixture
echo other > "$SIDE/side-file"   # a DIFFERENT file: the later merge must not conflict
git_q -C "$SIDE" add -A; git_q -C "$SIDE" commit -m unrelated
git_q -C "$SIDE" push origin main
out="$("$RQ" resolve "$CK1" 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" == *"NOT LANDED"* ]] \
  && pass "resolve REFUSES when the remote moved to a DIFFERENT sha (not our merge)" \
  || fail "resolve accepted a remote that advanced without carrying the recorded merge: rc=$rc $out"

# ─────────────────────────────────────────────────────────────────────────────
# 3c. REFUSAL — the ckpt TAG was pushed but the BRANCH was not.
#     An annotated tag peels to the merge commit, so `refs/tags/<ckpt>^{}` in ls-remote
#     equals the recorded sha the instant the tag is pushed — while the merge is still
#     absent from the published trunk. Accepting that would be a false resolve.
# ─────────────────────────────────────────────────────────────────────────────
git_q -C "$R1" push origin "$CK1"          # tag only; main deliberately not pushed
lsr="$(git -C "$R1" ls-remote origin 2>/dev/null)"
grep -q "refs/tags/$CK1" <<< "$lsr" \
  || echo "  (note: fixture did not publish the tag; case 3c is weakened)"
out="$("$RQ" resolve "$CK1" 2>&1)"; rc=$?
[[ $rc -ne 0 ]] \
  && pass "resolve REFUSES when only the ckpt TAG reached the remote, not the branch" \
  || fail "resolve accepted a tag-only push as landed — the merge is NOT on the trunk: $out"

# ─────────────────────────────────────────────────────────────────────────────
# 4. RESOLVE AFTER A REAL, VERIFIED PUSH.
# ─────────────────────────────────────────────────────────────────────────────
# The recorded merge must actually reach the remote. (The fixture pushes; the consumer
# never pushes — pushing IS the owner's ratification act.)
git_q -C "$R1" fetch origin
git -C "$R1" merge --no-edit -m merge-side origin/main >/dev/null 2>&1 \
  || { echo "FIXTURE BROKEN: merge failed in $R1"; exit 1; }
M1b="$(git -C "$R1" rev-parse HEAD)"
[[ "$M1b" != "$M1" ]] || { echo "FIXTURE BROKEN: merge produced no new commit"; exit 1; }
CK1b="relay-ckpt-20260821-0930"
git_q -C "$R1" tag -a -m ckpt "$CK1b"
record alpha "$R1" "$M1b" "$CK1b" > "$RELAY_RATIFICATION_QUEUE"
git_q -C "$R1" push --follow-tags origin main

out="$("$RQ" resolve "$CK1b" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] \
  && pass "resolve SUCCEEDS once the remote demonstrably carries the merge (rc=0)" \
  || fail "resolve failed after a real push: rc=$rc $out"
[[ "$(status_of "$RELAY_RATIFICATION_QUEUE" "$M1b")" == resolved ]] \
  && pass "the record is MARKED resolved (kept, not deleted — the merge's audit trail)" \
  || fail "record status after resolve: $(status_of "$RELAY_RATIFICATION_QUEUE" "$M1b")"
[[ "$(field_of "$RELAY_RATIFICATION_QUEUE" "$M1b" verified_sha)" == "$M1b" ]] \
  && pass "resolve records verified_sha — the evidence, not just a status flip" \
  || fail "verified_sha missing/wrong: $(field_of "$RELAY_RATIFICATION_QUEUE" "$M1b" verified_sha)"
[[ -n "$(field_of "$RELAY_RATIFICATION_QUEUE" "$M1b" resolved_at)" ]] \
  && pass "resolve stamps resolved_at (durable trace of the human sign-off)" \
  || fail "resolved_at missing"
# and it drops out of the pending listing but survives --all
pend_out="$("$RQ" list 2>/dev/null)"
grep -q "$CK1b" <<< "$pend_out" \
  && fail "a resolved entry still shows in the default (pending) listing" \
  || pass "a resolved entry no longer shows as pending"
all_out="$("$RQ" list --all 2>/dev/null)"
grep -q "$CK1b" <<< "$all_out" \
  && pass "a resolved entry is still visible under --all (marked, not vanished)" \
  || fail "resolved entry lost from --all — it was deleted, not marked"

# 4b. ANCESTOR CASE — the remote advanced PAST our merge, which is no longer any ref tip.
echo more >> "$R1/f"; git_q -C "$R1" commit -am later
M1c="$(git -C "$R1" rev-parse HEAD)"      # untagged, so it can only match via ancestry
echo evenmore >> "$R1/f"; git_q -C "$R1" commit -am later2
git_q -C "$R1" push origin main
record alpha "$R1" "$M1c" "" > "$RELAY_RATIFICATION_QUEUE"
out="$("$RQ" resolve "$M1c" 2>&1)"; rc=$?
[[ $rc -eq 0 && "$out" == *ancestor* ]] \
  && pass "resolve accepts a merge the remote carries as an ANCESTOR of its head" \
  || fail "ancestor-of-remote-head merge not accepted: rc=$rc $out"

# ─────────────────────────────────────────────────────────────────────────────
# 5. HALF-PUBLISHED — merge pushed, ckpt TAG not. Refused unless explicitly allowed.
# ─────────────────────────────────────────────────────────────────────────────
R2="$(make_repo beta)"
echo w >> "$R2/f"; git_q -C "$R2" commit -am work
M2="$(git -C "$R2" rev-parse HEAD)"
CK2="relay-ckpt-20260821-1000"
git_q -C "$R2" tag -a -m ckpt "$CK2"
git_q -C "$R2" push origin main          # branch only, tag deliberately withheld
record beta "$R2" "$M2" "$CK2" > "$RELAY_RATIFICATION_QUEUE"
out="$("$RQ" resolve "$CK2" 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" == *PARTIAL* ]] \
  && pass "resolve REFUSES a half-published unit (merge on remote, ckpt tag missing)" \
  || fail "resolve accepted a unit whose ckpt tag never reached the remote: rc=$rc $out"
out="$("$RQ" resolve "$CK2" --allow-missing-tag 2>&1)"; rc=$?
[[ $rc -eq 0 ]] \
  && pass "--allow-missing-tag is the explicit, opt-in escape hatch" \
  || fail "--allow-missing-tag did not resolve: rc=$rc $out"

# ─────────────────────────────────────────────────────────────────────────────
# 6. MALFORMED RECORDS ARE SURFACED, NEVER SKIPPED.
# ─────────────────────────────────────────────────────────────────────────────
Q="$T/mal.jsonl"; export RELAY_RATIFICATION_QUEUE="$Q"
{
  printf '%s\n' 'this is not json at all'
  record alpha "$R1" "$M1b" "$CK1b"
  printf '%s\n' '{"kind":"ratification-pending","repo":"gamma","status":"pending"}'
  printf '%s\n' '{"kind":"something-else","repo":"delta"}'
} > "$Q"
out="$("$RQ" list 2>&1)"; rc=$?
[[ $rc -ne 0 ]] \
  && pass "list EXITS NONZERO (rc=$rc) when the queue holds unreadable records" \
  || fail "list returned 0 over malformed records — a bad line read as 'nothing pending'"
n_mal="$(grep -c '^MALFORMED:' <<< "$out")"
[[ "$n_mal" -eq 3 ]] \
  && pass "all 3 bad records are named individually on stderr (unparseable, missing fields, unknown kind)" \
  || fail "expected 3 MALFORMED lines, got $n_mal:"$'\n'"$out"
grep -q "$CK1b" <<< "$out" \
  && pass "the VALID neighbour is still listed alongside the malformed report" \
  || fail "a malformed line suppressed the valid entries — silent truncation"

# resolving is refused outright while the queue cannot be fully read...
out="$("$RQ" resolve "$CK1b" 2>&1)"; rc=$?
[[ $rc -ne 0 ]] \
  && pass "resolve refuses to act on a queue containing records it cannot read" \
  || fail "resolve acted on a partially-unreadable queue: $out"
# ...and nothing was rewritten, so the malformed lines are still there byte-for-byte
[[ "$(grep -c . "$Q")" -eq 4 ]] \
  && pass "the malformed lines survive verbatim (no entry is ever silently dropped)" \
  || fail "queue lost lines: $(grep -c . "$Q") of 4 remain"

# ─────────────────────────────────────────────────────────────────────────────
# 7. KEY DISCIPLINE — unknown key and ambiguous key both refuse loudly.
# ─────────────────────────────────────────────────────────────────────────────
export RELAY_RATIFICATION_QUEUE="$T/q2.jsonl"
record alpha "$R1" "$M1" "$CK1" > "$RELAY_RATIFICATION_QUEUE"
"$RQ" resolve nosuchkey >/dev/null 2>&1 \
  && fail "resolve accepted an unknown key" \
  || pass "resolve refuses an unknown key"
# two entries sharing a 7-char sha prefix would be ambiguous; force it with a short key
record beta "$R2" "$M1" "$CK2" >> "$RELAY_RATIFICATION_QUEUE"
out="$("$RQ" show "${M1:0:8}" 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" == *AMBIGUOUS* ]] \
  && pass "an ambiguous key is refused loudly, never guessed" \
  || fail "ambiguous key not refused: rc=$rc $out"

# ─────────────────────────────────────────────────────────────────────────────
# 8. /relay human BUCKET — gather-human-backlog.sh emits ratification_pending rows
#    without disturbing the fixed column contract or the review_me-is-last ordering.
# ─────────────────────────────────────────────────────────────────────────────
STORE="$T/store"; mkdir -p "$STORE/src" "$STORE/cfg"
GR="$STORE/src/gamma"; mkdir -p "$GR"
cat > "$GR/REVIEW_ME.md" <<'EOF'
# REVIEW_ME
- [ ] a real human-judgment box
EOF
cat > "$STORE/cfg/relay.toml" <<EOF
[repos.gamma]
classification = "own"
path = "$GR"
EOF
record gamma "$GR" "$M1" "$CK1" > "$STORE/cfg/ratification-queue.jsonl"

gout="$(SRC_DIR="$STORE/src" RELAY_TOML="$STORE/cfg/relay.toml" \
        env -u RELAY_RATIFICATION_QUEUE -u FABLES_CONFIG bash "$GATHER" 2>"$T/gerr")"; grc=$?
[[ $grc -eq 0 ]] \
  && pass "gather still exits 0 with a ratification queue present" \
  || { fail "gather exited $grc"; cat "$T/gerr"; }
rat_rows="$(awk -F'\t' '$3=="ratification_pending"' <<< "$gout")"
[[ -n "$rat_rows" ]] \
  && pass "gather emits a ratification_pending row for the repo" \
  || fail "no ratification_pending row emitted:"$'\n'"$gout"
badcols="$(awk -F'\t' 'NF!=4 {c++} END{print c+0}' <<< "$gout")"
[[ "$badcols" == 0 ]] \
  && pass "every gather row still has exactly 4 columns (contract intact)" \
  || fail "$badcols gather rows have != 4 columns"
# review_me must remain the LAST bucket (id:da87): a ratification row must never come after it
last_rm="$(awk -F'\t' '$3=="review_me"{n=NR} END{print n+0}' <<< "$gout")"
last_rt="$(awk -F'\t' '$3=="ratification_pending"{n=NR} END{print n+0}' <<< "$gout")"
if [[ "$last_rm" -gt 0 && "$last_rt" -gt 0 && "$last_rt" -lt "$last_rm" ]]; then
  pass "ratification rows precede review_me — the id:da87 'review_me is last' ordering holds"
else
  fail "ordering broken: last review_me row=$last_rm, last ratification row=$last_rt"
fi
# the queue path is derived from RELAY_TOML's dir, so a fixture run can never read the
# real ~/.config/relay/ratification-queue.jsonl
grep -q "$HOME/.config/relay" <<< "$gout" \
  && fail "gather output references the REAL relay config dir — not hermetic" \
  || pass "gather resolved the queue inside the fixture (never the real ~/.config/relay)"

# a malformed queue must make /relay human LOUD, not quietly short
printf '%s\n' 'not json' >> "$STORE/cfg/ratification-queue.jsonl"
gout2="$(SRC_DIR="$STORE/src" RELAY_TOML="$STORE/cfg/relay.toml" \
         env -u RELAY_RATIFICATION_QUEUE -u FABLES_CONFIG bash "$GATHER" 2>"$T/gerr2")"; grc2=$?
[[ $grc2 -ne 0 ]] \
  && pass "gather exits NONZERO when the ratification queue holds an unreadable record" \
  || fail "gather exited 0 over a malformed ratification queue"
grep -q 'MALFORMED' "$T/gerr2" \
  && pass "gather replays the MALFORMED detail on stderr" \
  || { fail "gather did not surface the malformed detail"; cat "$T/gerr2"; }
rm_rows2="$(awk -F'\t' '$3=="review_me"' <<< "$gout2")"
[[ -n "$rm_rows2" ]] \
  && pass "the review_me rows still come through despite the queue failure (id:da87 isolation)" \
  || fail "a failing ratification emitter truncated the review_me rows"

printf '\n'
if (( fails )); then
  printf '%d assertion(s) FAILED\n' "$fails"
  exit 1
fi
printf 'all assertions passed\n'

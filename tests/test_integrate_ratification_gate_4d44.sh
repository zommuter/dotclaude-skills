#!/usr/bin/env bash
# id:4d44 — the RATIFICATION GATE: the pool merges locally; the human ratifies and pushes.
# id:f5d9(a) — and wherever a push DOES still happen, it is VERIFIED against the remote ref.
#
# NO `# roadmap:` header ON PURPOSE: this is not a ROADMAP item. It specs an owner-DECIDED
# design change filed in TODO.md (id:4d44) plus a defect fix (id:f5d9(a)), so its failures
# must ALWAYS count — the expected-red carve-out must never apply to it.
#
# fails-against: c9c7fc0 — VERIFIED, not asserted. Run against a mirrored relay/scripts via
#   $INT_OVERRIDE with integrate.sh + relay-loop.js reverted to c9c7fc0, sections
#   (1),(2),(4),(6),(7) go RED: the substantive unit was PUSHED (origin moved, the ckpt tag
#   leaked to the remote), stdout said push=pushed with no ratification key, no queue file
#   existed, a silently-failed push exited 0 claiming success, and the parser rejected the
#   new keys. Section (3)'s PUSH half is a genuine unchanged-behaviour control — GREEN on
#   both sides, which is exactly what it is for; only its `ratification=none` line is
#   new-contract and red before.
#
#   Section (5) is red against neither c9c7fc0 nor the fix, because the OLD code really did
#   push, so its push-keyed `landed` marker happened to be correct. Its guard was verified
#   against a TARGETED MUTATION of the fixed script instead — deleting the one `landed=1`
#   in the deferred branch of step 8 (i.e. implementing the deferral but leaving id:5fe2's
#   land point on the push): all four (5) assertions go RED, proving the assertion tests the
#   seam and not the fixture.
#
# What each section ASSERTS (behaviour against real fixture repos, never a grep):
#   (1) SUBSTANTIVE unit    — merges, ticks, tags, retires, writes relay.toml, and does NOT
#                             push: the fixture's bare origin is BYTE-UNMOVED afterwards.
#   (2) SUBSTANTIVE unit    — is queued in the durable append-only ratification queue with the
#                             merged sha + ckpt tag, and stdout says push=deferred /
#                             ratification=pending.
#   (3) NON-SUBSTANTIVE     — still pushes; origin DOES move. (unchanged-behaviour control)
#   (4) SILENT PUSH FAILURE — a git-lock-push stub that exits 0 having pushed nothing is
#                             reported push=FAILED and a handback, NOT push=pushed (id:f5d9(a)).
#   (5) POST-LAND tail failure on a DEFERRED unit is LANDED-BUT-UNFINISHED, not a retryable
#                             defer — the land point is the ckpt tag, not the push (seam 3).
#   (6) relay-loop.js's parseIntegrateResult understands push=deferred / ratification=pending
#                             and never defaults a deferred tail failure to 'pushed'.
#   (7) LOCAL-AHEAD ACROSS RUNS — a second integrate on a main left local-ahead by the first
#                             still merges: sync-origin says `ok` and classify-verdict does
#                             NOT call it diverged (seam 2).
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INT="${INT_OVERRIDE:-$SRC_DIR/relay/scripts/integrate.sh}"
INT_DIR="$(cd "$(dirname "$INT")" && pwd)"
LOOP="$INT_DIR/relay-loop.js"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ERRLOG="$TMP/integrate.stderr"
: >"$ERRLOG"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; [[ -s "$ERRLOG" ]] && { echo "       last integrate.sh stderr:"; tail -n 30 "$ERRLOG" | sed 's/^/       | /'; }; exit 1; }

[[ -x "$INT" ]] || fail "integrate.sh not found/executable at $INT"

# A git-lock-push stub that REALLY pushes (the honest helper).
REAL_PUSH="$TMP/push-real.sh"
cat > "$REAL_PUSH" <<'EOF'
#!/usr/bin/env bash
# args: --ff-only <path>
set -euo pipefail
p=""
for a in "$@"; do case "$a" in --ff-only) ;; *) p="$a" ;; esac; done
git -C "$p" push --follow-tags origin HEAD >/dev/null 2>&1
EOF
chmod +x "$REAL_PUSH"

# The id:dc4f LIAR: exits 0 having pushed NOTHING. This is the observed real-world defect.
LIAR_PUSH="$TMP/push-liar.sh"
cat > "$LIAR_PUSH" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$LIAR_PUSH"

build() { # <suffix> [roadmap-content-file] → prints the main checkout path
  local sfx="$1" roadmap="${2:-}"
  local origin seed main
  origin="$TMP/o-$sfx.git"; seed="$TMP/s-$sfx"; main="$TMP/m-$sfx"
  git init --bare -b main -q "$origin"
  git clone -q "$origin" "$seed" 2>/dev/null
  git -C "$seed" config user.email t@e.st
  git -C "$seed" config user.name t
  echo base > "$seed/f"
  [[ -n "$roadmap" ]] && cp "$roadmap" "$seed/ROADMAP.md"
  git -C "$seed" add -A
  git -C "$seed" commit -qm base
  git -C "$seed" push -q -u origin main
  git clone -q "$origin" "$main" 2>/dev/null
  git -C "$main" config user.email t@e.st
  git -C "$main" config user.name t
  printf '%s' "$main"
}

child() { # <main> <name> → prints the worktree path
  local main="$1" name="$2"
  local wt="$TMP/wt-$name"
  git -C "$main" worktree add -q -b "relay/$name" "$wt" main
  echo "work-$name" > "$wt/g-$name"
  git -C "$wt" add -A
  git -C "$wt" commit -qm "child work $name"
  printf '%s' "$wt"
}

cfg() { # <suffix> <repo-name> → prints the config dir with a [repos.<name>] block
  local d="$TMP/cfg-$1"
  mkdir -p "$d"
  printf '[repos.%s]\nstatus = "active"\n' "$2" > "$d/relay.toml"
  printf '%s' "$d"
}

origin_head() { git -C "$1" rev-parse refs/heads/main 2>/dev/null || echo NONE; }

cat > "$TMP/rm.md" <<'EOF'
# Roadmap

- [ ] [ROUTINE] the worked item <!-- id:aaaa -->
- [ ] [ROUTINE] an untouched item <!-- id:bbbb -->
EOF

# =====================================================================================
# (1) SUBSTANTIVE — every step runs EXCEPT the push; the remote is byte-unmoved
# =====================================================================================
M1="$(build sub "$TMP/rm.md")"; R1="$(basename "$M1")"; O1="$TMP/o-sub.git"
W1="$(child "$M1" sub)"
C1="$(cfg sub "$R1")"
CHILD1_SHA="$(git -C "$M1" rev-parse relay/sub)"   # captured BEFORE retire deletes the branch
ORIGIN_BEFORE="$(origin_head "$O1")"
rc=0
out1="$(FABLES_CONFIG="$C1" INTEGRATE_GIT_LOCK_PUSH="$REAL_PUSH" \
  "$INT" --repo "$R1" --path "$M1" --worktree "$W1" --branch relay/sub \
         --summary "close aaaa" --run r1 --label "executor (claude-sonnet-4-5, relay-loop)" \
         --ids aaaa --verdict execute --substantive true 2>"$ERRLOG")" || rc=$?
[[ $rc -eq 0 ]] || fail "(1) substantive integrate exited $rc — the deferral must be a SUCCESS path, not a handback"

# the merge really landed locally
git -C "$M1" merge-base --is-ancestor "$CHILD1_SHA" HEAD 2>/dev/null \
  || fail "(1) the child commit $CHILD1_SHA is NOT an ancestor of main — the merge did not land"
# the ckpt tag really exists locally
CKPT1="$(awk -F'=' '/^ckpt=/{print substr($0, 6); exit}' <<<"$out1")"
[[ -n "$CKPT1" ]] || fail "(1) no ckpt= line on stdout"
git -C "$M1" rev-parse -q --verify "refs/tags/$CKPT1" >/dev/null \
  || fail "(1) ckpt tag '$CKPT1' does not exist locally — tagging was skipped along with the push"
# the tick + relay.toml write + retire all still ran
grep -q '^- \[x\].*id:aaaa' "$M1/ROADMAP.md" || fail "(1) the ROADMAP tick did not run"
grep -q "last_ckpt = \"$CKPT1\"" "$C1/relay.toml" || fail "(1) relay.toml last_ckpt was not written"
[[ ! -d "$W1" ]] || fail "(1) the worktree was not retired"
# …AND THE REMOTE NEVER MOVED — the whole point.
[[ "$(origin_head "$O1")" == "$ORIGIN_BEFORE" ]] \
  || fail "(1) THE PUSH HAPPENED: origin moved from $ORIGIN_BEFORE to $(origin_head "$O1") for a SUBSTANTIVE unit (id:4d44 ratification gate did not fire)"
git -C "$O1" rev-parse -q --verify "refs/tags/$CKPT1" >/dev/null \
  && fail "(1) the ckpt tag reached the remote — the ratification gate leaked a tag"
pass "(1) id:4d44 a SUBSTANTIVE unit merges+ticks+tags+retires+state-writes LOCALLY and does NOT push"

# =====================================================================================
# (2) SUBSTANTIVE — durable ratification queue + the stdout keys
# =====================================================================================
grep -q '^push=deferred$' <<<"$out1" || fail "(2) stdout is missing push=deferred: $(grep '^push=' <<<"$out1")"
grep -q '^ratification=pending$' <<<"$out1" || fail "(2) stdout is missing ratification=pending"
Q1="$C1/ratification-queue.jsonl"
[[ -s "$Q1" ]] || fail "(2) no durable ratification queue at $Q1 — the deferred merge is invisible to the next attended session"
MERGED1="$(awk '/^merged=/{print substr($0, 8); exit}' <<<"$out1")"
python3 - "$Q1" "$R1" "$MERGED1" "$CKPT1" <<'PYEOF' || fail "(2) the ratification queue entry is missing/incomplete (see message above)"
import json, sys
q, repo, merged, ckpt = sys.argv[1:5]
lines = [l for l in open(q).read().splitlines() if l.strip()]
assert len(lines) == 1, "expected exactly 1 queue line, got %d" % len(lines)
r = json.loads(lines[0])          # MUST be valid JSON, one record per line
for k, want in (("repo", repo), ("merged", merged), ("ckpt", ckpt),
                ("status", "pending"), ("push", "deferred")):
    assert r.get(k) == want, "queue field %r = %r, want %r" % (k, r.get(k), want)
assert r.get("ids") == ["aaaa"], "queue lost the worked ids: %r" % (r.get("ids"),)
assert r.get("path"), "queue entry has no repo path — the owner cannot act on it"
PYEOF
pass "(2) id:4d44 the deferred unit is recorded in the durable append-only ratification queue"

# =====================================================================================
# (3) NON-SUBSTANTIVE — UNCHANGED: it still pushes. (control: green before AND after)
# =====================================================================================
M3="$(build nonsub)"; R3="$(basename "$M3")"; O3="$TMP/o-nonsub.git"
W3="$(child "$M3" nonsub)"
C3="$(cfg nonsub "$R3")"
BEFORE3="$(origin_head "$O3")"
rc=0
out3="$(FABLES_CONFIG="$C3" INTEGRATE_GIT_LOCK_PUSH="$REAL_PUSH" \
  "$INT" --repo "$R3" --path "$M3" --worktree "$W3" --branch relay/nonsub \
         --summary "no substantive close" --run r1 --label "reviewer (claude-opus-5, relay-loop)" \
         --verdict review --substantive false --strong-model claude-opus-5 2>"$ERRLOG")" || rc=$?
[[ $rc -eq 0 ]] || fail "(3) non-substantive integrate exited $rc"
grep -q '^push=pushed$' <<<"$out3" || fail "(3) a NON-substantive unit must still report push=pushed: $(grep '^push=' <<<"$out3")"
grep -q '^ratification=none$' <<<"$out3" || fail "(3) a NON-substantive unit must report ratification=none"
[[ "$(origin_head "$O3")" != "$BEFORE3" ]] \
  || fail "(3) the non-substantive unit did NOT push — the gate over-fired and now blocks work it was never meant to touch"
[[ ! -s "$C3/ratification-queue.jsonl" ]] \
  || fail "(3) a pushed unit was queued for ratification — nothing to ratify, the queue must stay clean"
pass "(3) a NON-substantive unit is UNCHANGED: it pushes, and is not queued"

# =====================================================================================
# (4) id:f5d9(a) — a push that silently did nothing is FAILED, never 'pushed'
# =====================================================================================
M4="$(build liar)"; R4="$(basename "$M4")"; O4="$TMP/o-liar.git"
W4="$(child "$M4" liar)"
C4="$(cfg liar "$R4")"
BEFORE4="$(origin_head "$O4")"
rc=0
out4="$(FABLES_CONFIG="$C4" INTEGRATE_GIT_LOCK_PUSH="$LIAR_PUSH" \
  "$INT" --repo "$R4" --path "$M4" --worktree "$W4" --branch relay/liar \
         --summary "nothing reaches the remote" --run r1 --label "reviewer (claude-opus-5, relay-loop)" \
         --verdict review --substantive false --strong-model claude-opus-5 2>"$ERRLOG")" || rc=$?
[[ $rc -ne 0 ]] || fail "(4) integrate exited 0 while the remote never moved (id:f5d9(a) false-success push): stdout=$out4"
[[ $rc -eq 27 ]] || fail "(4) expected the push exit code 27, got $rc"
grep -q '^push=FAILED$' "$ERRLOG" || fail "(4) no push=FAILED line on stderr: $(cat "$ERRLOG")"
grep -q '^landed=false$' "$ERRLOG" || fail "(4) a failed push must stay PRE-LAND (landed=false) so a retry is correct"
grep -q '^merged=' "$ERRLOG" && fail "(4) a merged= line on a pre-land exit would advertise a landed merge"
grep -q '^push=pushed$' <<<"$out4" && fail "(4) stdout claimed push=pushed while origin is still at $BEFORE4 — the exact defect"
[[ "$(origin_head "$O4")" == "$BEFORE4" ]] || fail "(4) fixture bug: the liar stub actually pushed"
pass "(4) id:f5d9(a) a push verified NOT to have landed is reported push=FAILED, not success"

# =====================================================================================
# (5) SEAM 3 — a POST-LAND tail failure on a DEFERRED unit is LANDED-BUT-UNFINISHED
#     The land point moved from the push to the ckpt tag. With the OLD (push-keyed)
#     discriminator a substantive tail failure reported landed=false, i.e. "safe to
#     retry" — which re-merges an already-merged branch. This asserts it does not.
# =====================================================================================
M5="$(build tail)"; R5="$(basename "$M5")"
W5="$(child "$M5" tail)"
C5="$(cfg tail "$R5")"
RETIRE_FAIL="$TMP/retire-fail.sh"
cat > "$RETIRE_FAIL" <<'EOF'
#!/usr/bin/env bash
echo "simulated retire failure" >&2
exit 1
EOF
chmod +x "$RETIRE_FAIL"
rc=0
out5="$(FABLES_CONFIG="$C5" INTEGRATE_GIT_LOCK_PUSH="$REAL_PUSH" INTEGRATE_WORKTREE_RETIRE="$RETIRE_FAIL" \
  "$INT" --repo "$R5" --path "$M5" --worktree "$W5" --branch relay/tail \
         --summary "tail fails after the local land" --run r1 --label "executor (claude-sonnet-4-5, relay-loop)" \
         --verdict execute --substantive true 2>"$ERRLOG")" || rc=$?
[[ $rc -eq 28 ]] || fail "(5) expected the worktree-retire exit code 28, got $rc"
grep -q '^landed=true$' "$ERRLOG" \
  || fail "(5) SEAM 3 REGRESSION: a tail failure AFTER a deferred-push land reported landed=false — the caller would re-merge an already-merged branch. stderr: $(cat "$ERRLOG")"
grep -q '^push=deferred$' "$ERRLOG" || fail "(5) the handback block must report push=deferred, never a publish that never happened"
grep -q '^ratification=pending$' "$ERRLOG" || fail "(5) the handback block must carry ratification=pending"
grep -q '^merged=' "$ERRLOG" || fail "(5) a post-land handback must name the merged sha"
[[ -s "$C5/ratification-queue.jsonl" ]] \
  || fail "(5) the ratification entry must be written BEFORE the tail steps — a tail failure must not lose the record"
pass "(5) seam 3: the land point is the CKPT TAG, so a deferred unit's tail failure is LANDED-BUT-UNFINISHED"

# =====================================================================================
# (6) relay-loop.js parseIntegrateResult understands the new keys
# =====================================================================================
[[ -f "$LOOP" ]] || fail "(6) relay-loop.js not found at $LOOP"
node --input-type=module -e "
const src = await import('node:fs').then(m => m.readFileSync('$LOOP', 'utf8'));
const m = src.match(/function parseIntegrateResult\(raw\)\s*\{[\s\S]*?\n\}/);
if (!m) { console.error('parseIntegrateResult not found'); process.exit(1); }
const parseIntegrateResult = new Function('return ' + m[0])();
const ok = parseIntegrateResult('merged=abc123\nckpt=relay-ckpt-x\npush=deferred\nratification=pending\nts=T\npostSig=\nopenRoutine=0\nopenHard=0\n');
if (ok.merged !== true) { console.error('deferred success not parsed as merged'); process.exit(1); }
if (ok.pushStatus !== 'deferred') { console.error('pushStatus=' + ok.pushStatus); process.exit(1); }
if (ok.ratification !== 'pending') { console.error('ratification=' + ok.ratification); process.exit(1); }
const tail = parseIntegrateResult('handback=worktree-retire\nlanded=true\nmerged=abc123\nckpt=relay-ckpt-x\npush=deferred\nratification=pending\nremaining=x\nckptRecorded=true\n');
if (tail.landedUnfinished !== true) { console.error('deferred tail failure not landedUnfinished'); process.exit(1); }
if (tail.deferred === true) { console.error('deferred tail failure was marked retryable'); process.exit(1); }
if (tail.pushStatus !== 'deferred') { console.error('tail pushStatus defaulted to ' + tail.pushStatus + ' — it must never assert a push that never happened'); process.exit(1); }
const bad = parseIntegrateResult('handback=git-lock-push\nlanded=false\npush=FAILED\n');
if (bad.deferred !== true) { console.error('a FAILED push must stay retryable'); process.exit(1); }
if (bad.landedUnfinished === true) { console.error('a FAILED push must not be landedUnfinished'); process.exit(1); }
" || fail "(6) relay-loop.js parseIntegrateResult does not honour push=deferred / ratification=pending (see error above)"
pass "(6) relay-loop.js parses push=deferred + ratification=pending and never defaults a deferred tail to 'pushed'"

# =====================================================================================
# (7) SEAM 2 — LOCAL-AHEAD main ACROSS RUNS is not treated as a diverged base
#     After (1) the fixture's main is N commits ahead of an unmoved origin. A SECOND
#     integrate on that same repo must still merge — i.e. sync-origin must say `ok`,
#     not `diverged`, and classify-verdict must not rank it `blocked`.
# =====================================================================================
AHEAD="$(git -C "$M1" rev-list --count 'HEAD...@{upstream}' --right-only 2>/dev/null; git -C "$M1" rev-list --count '@{upstream}..HEAD')"
[[ "$(git -C "$M1" rev-list --count '@{upstream}..HEAD')" -gt 0 ]] \
  || fail "(7) fixture bug: main is not local-ahead after the deferred integrate"
SYNC_OUT="$("$INT_DIR/sync-origin.sh" "$M1" 2>/dev/null || true)"
[[ "$SYNC_OUT" == "ok" ]] \
  || fail "(7) SEAM 2: sync-origin.sh says '$SYNC_OUT' on a LOCAL-AHEAD main — a later run would hand back at step 3 forever"
# classify-verdict.sh's diverged guard must also not fire on ahead-only.
CV_OUT="$(printf '%s' '{"repo":"x","dirty":false,"has_upstream":true,"upstream_ahead_behind":"3\t0","actionable_routine_open":0,"open_hard":0}' \
          | "$INT_DIR/classify-verdict.sh" 2>/dev/null || true)"
grep -qi 'diverged' <<<"$CV_OUT" \
  && fail "(7) SEAM 2: classify-verdict.sh calls an AHEAD-ONLY repo diverged/blocked — the pool would stop dispatching it: $CV_OUT"
# a SECOND integrate on the same, still-local-ahead checkout must land.
W7="$(child "$M1" second)"
rc=0
out7="$(FABLES_CONFIG="$C1" INTEGRATE_GIT_LOCK_PUSH="$REAL_PUSH" \
  "$INT" --repo "$R1" --path "$M1" --worktree "$W7" --branch relay/second \
         --summary "second close on a local-ahead main" --run r2 --label "executor (claude-sonnet-4-5, relay-loop)" \
         --ids bbbb --verdict execute --substantive true 2>"$ERRLOG")" || rc=$?
[[ $rc -eq 0 ]] || fail "(7) SEAM 2: a SECOND integrate on a LOCAL-AHEAD main exited $rc — the deferral wedges the pool after one round"
[[ "$(origin_head "$O1")" == "$ORIGIN_BEFORE" ]] || fail "(7) the second integrate pushed"
[[ "$(grep -c . "$Q1")" -eq 2 ]] || fail "(7) the ratification queue must APPEND (want 2 entries, got $(grep -c . "$Q1"))"
pass "(7) seam 2: a LOCAL-AHEAD main is 'ok' to sync-origin, not diverged to classify-verdict, and a later run still integrates"

echo "ALL PASS: tests/$(basename "$0")"

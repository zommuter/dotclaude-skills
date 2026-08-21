#!/usr/bin/env bash
# id:f0ad — an UPSTREAM-LESS repo's integrate must not silently count unpublished work
# as a completion.
#
# NO `# roadmap:` header ON PURPOSE: this is a defect fix filed in TODO.md (id:f0ad), not a
# ROADMAP item, so its failures must ALWAYS count — the expected-red carve-out must never
# apply to it.
#
# THE DEFECT: integrate.sh's step-8 `no-upstream` branch set `landed=1` (correctly — the
# merge is committed and tagged) but step 8b's ratification enqueue was gated on
# `$defer_push`, which is EMPTY for a NON-substantive unit — and a non-substantive unit is
# the only kind that can reach that branch at all. So the unit exited 0 on the SUCCESS path
# with `ratification=none`, and relay-loop.js's surfacing condition
# (`result.ratification === 'pending' || result.pushStatus === 'deferred'`) matched NEITHER
# key. An unpublished merge was recorded as a plain completion with no durable record
# anywhere — the one outcome the id:4d44 design says it cannot have.
#
# fails-against: the pre-id:f0ad integrate.sh (step 8b gated on `$defer_push`). VERIFIED RED
#   there — run against a mirrored relay/scripts via $INT_OVERRIDE: stdout carries
#   `ratification=none`, no queue file is created, and the parsed result the supervisor sees
#   trips neither arm of the surfacing condition.
#
# What each section ASSERTS (behaviour against a real fixture repo, never a grep):
#   (1) an upstream-less repo's integrate still SUCCEEDS and reports push=no-upstream…
#   (2) …and is DURABLY QUEUED, with a remediation that matches its class (there is no
#       remote to push to, so "git push --follow-tags" would be a lie).
#   (3) the object relay-loop.js's parser builds from that stdout carries
#       ratification='pending', which is the key its surfacing condition reads.
set -uo pipefail

# Hermeticity: neutralise the developer's global core.hooksPath for every git invocation.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null

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

# A push helper that does nothing and exits 0. Honest here, not a liar stub: the fixture has
# NO remote at all, so "pushed nothing, exit 0" is exactly what a real run would produce.
NOOP_PUSH="$TMP/push-noop.sh"
cat > "$NOOP_PUSH" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$NOOP_PUSH"

# A repo with NO remote and NO upstream — the id:f0ad shape.
M="$TMP/m-noup"
git init -q -b main "$M"
git -C "$M" config user.email t@e.st
git -C "$M" config user.name t
echo base > "$M/f"
git -C "$M" add -A
git -C "$M" commit -qm base
[[ -z "$(git -C "$M" remote)" ]] || fail "fixture bug: the repo has a remote"

W="$TMP/wt-noup"
git -C "$M" worktree add -q -b relay/noup "$W" main
echo work > "$W/g"
git -C "$W" add -A
git -C "$W" commit -qm "child work"

R="$(basename "$M")"
C="$TMP/cfg-noup"
mkdir -p "$C"
printf '[repos.%s]\nstatus = "active"\n' "$R" > "$C/relay.toml"
Q="$C/ratification-queue.jsonl"

rc=0
out="$(FABLES_CONFIG="$C" INTEGRATE_GIT_LOCK_PUSH="$NOOP_PUSH" \
  "$INT" --repo "$R" --path "$M" --worktree "$W" --branch relay/noup \
         --summary "close in an upstream-less repo" --run r1 \
         --label "reviewer (claude-opus-5, relay-loop)" \
         --verdict review --substantive false --strong-model claude-opus-5 2>"$ERRLOG")" || rc=$?

# =====================================================================================
# (1) it still succeeds, and it says honestly that nothing was published
# =====================================================================================
[[ $rc -eq 0 ]] || fail "(1) integrate exited $rc in an upstream-less repo. stderr: $(cat "$ERRLOG")"
grep -q '^push=no-upstream$' <<<"$out" || fail "(1) expected push=no-upstream, got: $(grep '^push=' <<<"$out")"
MERGED="$(awk '/^merged=/{print substr($0, 8); exit}' <<<"$out")"
CKPT="$(awk -F'=' '/^ckpt=/{print substr($0, 6); exit}' <<<"$out")"
[[ -n "$MERGED" && -n "$CKPT" ]] || fail "(1) no merged=/ckpt= lines: $out"
git -C "$M" rev-parse -q --verify "refs/tags/$CKPT" >/dev/null || fail "(1) the ckpt tag is missing locally"
grep -q '^ratification=pending$' <<<"$out" \
  || fail "(1) id:f0ad REGRESSION: an UNPUBLISHED merge reported '$(grep '^ratification=' <<<"$out")' — relay-loop.js keys its surfacing on 'pending', so this work is counted as a completion and vanishes"
pass "(1) id:f0ad an upstream-less integrate succeeds, reports push=no-upstream AND ratification=pending"

# =====================================================================================
# (2) the durable queue entry exists and its remediation fits the class
# =====================================================================================
[[ -s "$Q" ]] \
  || fail "(2) id:f0ad REGRESSION: no durable ratification queue at $Q — the merge $MERGED sits unpushed with NO record of its existence"
python3 - "$Q" "$R" "$MERGED" "$CKPT" <<'PYEOF' || fail "(2) the queue entry is missing/incomplete (see message above)"
import json, sys
q, repo, merged, ckpt = sys.argv[1:5]
lines = [l for l in open(q).read().splitlines() if l.strip()]
assert len(lines) == 1, "expected exactly 1 queue line, got %d" % len(lines)
r = json.loads(lines[0])
for k, want in (("repo", repo), ("merged", merged), ("ckpt", ckpt),
                ("status", "pending"), ("push", "no-upstream")):
    assert r.get(k) == want, "queue field %r = %r, want %r" % (k, r.get(k), want)
assert r.get("path"), "queue entry has no repo path — the owner cannot act on it"
act = r.get("action") or ""
assert "upstream" in act, "the action must name the actual problem (no upstream), got %r" % (act,)
assert "push --follow-tags" not in act, \
    "the action hands the owner a push command that CANNOT work — there is no remote: %r" % (act,)
PYEOF
pass "(2) id:f0ad the unpublished unit is durably queued with a remediation that matches its class"

# =====================================================================================
# (3) what relay-loop.js's parser makes of that stdout is what its surfacing reads
# =====================================================================================
[[ -f "$LOOP" ]] || fail "(3) relay-loop.js not found at $LOOP"
printf '%s' "$out" > "$TMP/stdout.txt"
node --input-type=module -e "
const fs = await import('node:fs');
const src = fs.readFileSync('$LOOP', 'utf8');
const m = src.match(/function parseIntegrateResult\(raw\)\s*\{[\s\S]*?\n\}/);
if (!m) { console.error('parseIntegrateResult not found'); process.exit(1); }
const parseIntegrateResult = new Function('return ' + m[0])();
const r = parseIntegrateResult(fs.readFileSync('$TMP/stdout.txt', 'utf8'));
if (r.merged !== true) { console.error('the no-upstream success path was not parsed as merged'); process.exit(1); }
if (r.pushStatus !== 'no-upstream') { console.error('pushStatus=' + r.pushStatus); process.exit(1); }
// THE seam: this is the exact expression integrate() surfaces on.
if (!(r.ratification === 'pending' || r.pushStatus === 'deferred')) {
  console.error('SURFACING CONDITION DOES NOT FIRE for an unpublished merge (ratification=' + r.ratification + ', push=' + r.pushStatus + ')');
  process.exit(1);
}
" || fail "(3) relay-loop.js would NOT surface this unpublished merge (see error above)"
pass "(3) id:f0ad the parsed result trips relay-loop.js's ratification-pending surfacing condition"

echo "ALL PASS: tests/$(basename "$0")"

#!/usr/bin/env bash
# roadmap:5fe2 — a POST-PUSH integrate failure must NOT be misread as a retryable defer.
#
# integrate.sh's steps split into two classes, separated by the push at step 8:
#   PRE-push  (remote untouched, retry is CORRECT): isolation, sync, wiring, bump(30),
#             merge, tick(31), version(24), changelog(25), archive(32), ckpt(26)
#             — plus push(27) itself, where the push FAILED so the remote is untouched.
#   POST-push (merge committed, tagged AND pushed — retry is WRONG): retire(28),
#             state(29), strong(33).
# Before id:5fe2 the two were indistinguishable on the wire: `parseIntegrateResult`
# collapsed EVERY MECH-ERROR to `{merged:false}` and the caller kept the worktree for a
# retry that then fails forever at merge/isolation, leaving relay.toml last_ckpt stale.
#
# This test drives the REAL integrate.sh against REAL git fixtures to one PRE-push failure
# (changelog, code 25), one POST-push failure (worktree-retire, code 28) and the push(27)
# special case, then feeds each result — shaped exactly as mechanical-proxy.py shapes it —
# through relay-loop.js's real parseIntegrateResult and asserts the caller's resulting state
# DIFFERS correctly.
#
# id:2c2a UPDATED THE WIRE, NOT THE CLASSES. Those per-step numbers are no longer EXIT codes:
# a handback is a verdict REACHED and EXECUTED, so integrate.sh exits 0 and the step identity
# rides on stdout as handback=/handbackCode=/handbackReason=. The proxy shape therefore
# inverted — it returns STDOUT on a zero exit and discards stderr, where it used to return
# 'MECH-ERROR exit=<n>\n<stderr>' and discard stdout — so every assertion below reads STDOUT.
# The three CLASSES (pre-land defer / landed-but-unfinished / success) are unchanged, and the
# landed-but-unfinished one gained its own `partial=<step>` marker.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INT="$SRC_DIR/relay/scripts/integrate.sh"
JS="$SRC_DIR/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$INT" ]] || fail "integrate.sh not found/executable at $INT"
[[ -f "$JS"  ]] || fail "relay-loop.js not found at $JS"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── node harness: extract the REAL parseIntegrateResult from relay-loop.js (brace-matched,
#    never a reimplementation) and print the fields the caller branches on. ──
PARSE="$TMP/parse.js"
cat > "$PARSE" <<'NODEEOF'
const fs = require("fs");
const src = fs.readFileSync(process.argv[2], "utf8");
const start = src.indexOf("function parseIntegrateResult(raw) {");
if (start < 0) { console.error("parseIntegrateResult not found in relay-loop.js"); process.exit(1); }
let i = src.indexOf("{", start), depth = 0, end = -1;
for (let p = i; p < src.length; p++) {
  if (src[p] === "{") depth++;
  else if (src[p] === "}") { depth--; if (depth === 0) { end = p + 1; break } }
}
if (end < 0) { console.error("could not brace-match parseIntegrateResult"); process.exit(1); }
const fn = eval("(" + src.slice(start, end).replace(/^function parseIntegrateResult/, "function") + ")");
const raw = fs.readFileSync(process.argv[3], "utf8");
const r = fn(raw) || {};
console.log(JSON.stringify({
  merged: !!r.merged,
  landedUnfinished: !!r.landedUnfinished,
  deferred: !!r.deferred,
  handbackStep: r.handbackStep || "",
  handbackCode: r.handbackCode || "",
  partial: r.partial || "",
  mergedSha: r.mergedSha || "",
  remaining: r.remaining || "",
  ckptRecorded: r.ckptRecorded === undefined ? null : r.ckptRecorded,
  hasReason: !!r.reason,
}));
NODEEOF

# id:2c2a — the proxy shape CHANGED with the exit-code flattening. A handback now exits 0, so
# mechanical-proxy.py returns the child's STDOUT (and DISCARDS stderr) — the exact mirror of
# the old 'MECH-ERROR exit=<n>\n<stderr>'. This helper therefore feeds parseIntegrateResult
# the STDOUT file, which is where integrate.sh now writes the KEY=VALUE block.
parse_of() { # <stdout-file> → JSON of parseIntegrateResult on the proxy shape
  node "$PARSE" "$JS" "$1"
}

jget() { python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"; }

# ── hermetic fixture: bare origin + main checkout + a child worktree with one commit ──
build() { # <suffix> → prints the main checkout path; sets nothing global
  # NB: one `local` per line — bash expands ALL of a `local`'s args before assigning any,
  # so `local a="$1" b="$a"` reads an unbound $a under `set -u`.
  local sfx="$1"
  local origin="$TMP/origin-$sfx.git"
  local seed="$TMP/seed-$sfx"
  local main="$TMP/myrepo-$sfx"
  git init --bare -b main -q "$origin"
  git clone -q "$origin" "$seed" 2>/dev/null
  git -C "$seed" config user.email t@e.st; git -C "$seed" config user.name t
  echo base > "$seed/f"; git -C "$seed" add -A; git -C "$seed" commit -qm base
  git -C "$seed" push -q -u origin main
  git clone -q "$origin" "$main" 2>/dev/null
  git -C "$main" config user.email t@e.st; git -C "$main" config user.name t
  echo "$main"
}

OK_STUB="$TMP/ok.sh";   printf '#!/usr/bin/env bash\nexit 0\n' > "$OK_STUB";   chmod +x "$OK_STUB"
BAD_STUB="$TMP/bad.sh"; printf '#!/usr/bin/env bash\necho "injected failure" >&2\nexit 1\n' > "$BAD_STUB"; chmod +x "$BAD_STUB"

# id:4d44 — CASE_EXTRA lets one case pass extra integrate.sh flags. Only case (C) uses it, to
# ask for `--substantive false`: since the ratification gate landed, a SUBSTANTIVE unit does
# not push at all, so the push-failure class (C) can only be exercised on the pushing path.
CASE_EXTRA=()
run_case() { # <suffix> <env-assignments...> → sets RC, OUTF, ERRF, MAIN_PATH, CFG_TOML, REPO
  local sfx="$1"; shift
  MAIN_PATH="$(build "$sfx")"
  REPO="$(basename "$MAIN_PATH")"
  local wt="$TMP/wt-$sfx"
  git -C "$MAIN_PATH" worktree add -q -b "relay/$sfx" "$wt" main
  echo work > "$wt/g"; git -C "$wt" add -A; git -C "$wt" commit -qm "child work id:test"
  local cfg="$TMP/cfg-$sfx"; mkdir -p "$cfg"
  # id:c82a — declare `[publish]` explicitly, as the live relay.toml does. FLOORED, a local
  # bare `origin` that cannot be proven private is withheld from the publish set, and this
  # file's whole subject (a POST-push failure) becomes unreachable. See
  # tests/test_publish_floor_privacy_gate_c82a.sh for the floor's own spec.
  printf '[publish]\ndefault_remotes = ["origin"]\n\n[repos.%s]\nstatus = "active"\n' "$REPO" > "$cfg/relay.toml"
  CFG_TOML="$cfg/relay.toml"
  ERRF="$TMP/err-$sfx"
  OUTF="$TMP/out-$sfx"   # id:2c2a — stdout is now the parsed channel on a handback too
  RC=0
  env FABLES_CONFIG="$cfg" "$@" \
    "$INT" --repo "$REPO" --path "$MAIN_PATH" --worktree "$wt" --branch "relay/$sfx" \
           --summary "test close id:test" --run testrun \
           --label "reviewer (claude-opus-4-8, integrate)" --ids test --level patch \
           --verdict execute ${CASE_EXTRA[@]+"${CASE_EXTRA[@]}"} >"$TMP/out-$sfx" 2>"$ERRF" || RC=$?
}

# =====================================================================================
# (A) PRE-push failure — changelog-append (exit 25). Remote untouched; retry is CORRECT.
# =====================================================================================
run_case pre INTEGRATE_CHANGELOG_APPEND="$BAD_STUB" INTEGRATE_GIT_LOCK_PUSH="$OK_STUB"
# id:2c2a — a legitimate refusal EXITS 0 and carries its step on stdout instead.
[[ $RC -eq 0 ]] || fail "(A) id:2c2a: a PRE-push refusal must exit 0, got $RC: $(cat "$ERRF")"
grep -q 'HANDBACK\[changelog-append\]' "$ERRF" || fail "(A) no loud HANDBACK[changelog-append] line"
grep -qx 'handback=changelog-append' "$OUTF" || fail "(A) STDOUT lost the step identity (handback=changelog-append): $(cat "$OUTF")"
grep -qx 'handbackCode=25' "$OUTF" || fail "(A) STDOUT lost the numeric step identity the exit code used to carry (handbackCode=25): $(cat "$OUTF")"
grep -q '^handbackReason=.*injected failure' "$OUTF" || fail "(A) STDOUT lost the handback REASON — with exit 0 the proxy drops stderr, so the cause must ride on stdout: $(cat "$OUTF")"
# ACCEPTANCE 1 (negative half): a PRE-push handback must NOT advertise a landed merge.
grep -qE '^merged=' "$OUTF" && fail "(A) PRE-push handback emitted a merged= line — a deferred unit must never look landed"
grep -qE '^landed=true' "$OUTF" && fail "(A) PRE-push handback claimed landed=true"
grep -qE '^partial=' "$OUTF" && fail "(A) PRE-push handback emitted partial= — that marker is for the LANDED-BUT-UNFINISHED class only"
PRE_JSON="$(parse_of "$OUTF")"
[[ "$(jget merged <<<"$PRE_JSON")" == "False" ]] || fail "(A) parse says merged for a PRE-push failure"
[[ "$(jget deferred <<<"$PRE_JSON")" == "True" ]] || fail "(A) parse did not mark the PRE-push failure DEFERRED: $PRE_JSON"
[[ "$(jget landedUnfinished <<<"$PRE_JSON")" == "False" ]] || fail "(A) parse marked a PRE-push failure landed: $PRE_JSON"
pass "(A) PRE-push failure (changelog, code 25): exit 0, step+code+reason on STDOUT, no merged=/landed=/partial=, parsed as DEFERRED (retry is correct)"

# =====================================================================================
# (B) POST-LAND failure — worktree-retire (exit 28). Merge committed AND tagged.
#     id:4d44 note: this case passes no --substantive, so the push is now DEFERRED and the
#     land point is the CKPT TAG rather than the push. Every assertion below is unchanged and
#     still green — which is the point: the LANDED-BUT-UNFINISHED class survived the land
#     point moving, so a substantive unit's tail failure is still never re-merged.
# =====================================================================================
run_case post INTEGRATE_GIT_LOCK_PUSH="$OK_STUB" INTEGRATE_WORKTREE_RETIRE="$BAD_STUB"
# id:2c2a — THE LANDED-BUT-UNFINISHED CASE. Owner-ratified: it exits 0 (the merge was
# COMMITTED, TAGGED and PUSHED — it succeeded at everything that matters) and carries a
# DISTINCT `partial=` marker on stdout alongside merged=/handback=/landed=.
[[ $RC -eq 0 ]] || fail "(B) id:2c2a: landed-but-unfinished must exit 0, got $RC: $(cat "$ERRF")"
grep -q 'HANDBACK\[worktree-retire\]' "$ERRF" || fail "(B) no loud HANDBACK[worktree-retire] line"
grep -qx 'partial=worktree-retire' "$OUTF" \
  || fail "(B) id:2c2a: no partial=<step> marker on stdout — the landed-but-unfinished class is now indistinguishable from a plain success: $(cat "$OUTF")"
grep -qx 'handbackCode=28' "$OUTF" || fail "(B) STDOUT lost the numeric step identity (handbackCode=28): $(cat "$OUTF")"
# ACCEPTANCE 1: merged=<sha> alongside handback=<step> on a POST-push handback.
grep -qE '^handback=worktree-retire$' "$OUTF" || fail "(B) POST-push handback did not emit handback=worktree-retire: $(cat "$OUTF")"
grep -qE '^landed=true$' "$OUTF"               || fail "(B) POST-push handback did not emit landed=true"
grep -qE '^merged=[0-9a-f]{7,}$' "$OUTF"       || fail "(B) POST-push handback did not emit merged=<sha>"
grep -qE '^remaining=.*worktree-retire'  "$OUTF" || fail "(B) POST-push handback did not name the steps that did NOT run"
MERGED_SHA_WIRE="$(sed -n 's/^merged=//p' "$OUTF" | tail -n1)"
# merged= is the --no-ff MERGE commit (later scoped tick/changelog/archive commits sit on
# top of it), so pin it as a real ancestor of main HEAD carrying the merge subject.
git -C "$MAIN_PATH" merge-base --is-ancestor "$MERGED_SHA_WIRE" HEAD \
  || fail "(B) merged= on the wire ($MERGED_SHA_WIRE) is not an ancestor of main HEAD"
grep -q 'merge(relay): test close id:test' < <(git -C "$MAIN_PATH" log -1 --format=%s "$MERGED_SHA_WIRE") \
  || fail "(B) merged= on the wire is not the --no-ff merge commit"
# ACCEPTANCE 6: the recorded checkpoint must not silently disagree with the remote.
CKPT="$(git -C "$MAIN_PATH" tag -l 'relay-ckpt-*' | tail -n1)"
[[ -n "$CKPT" ]] || fail "(B) fixture produced no relay-ckpt-* tag — the POST-push state was never reached"
grep -qF "last_ckpt = \"$CKPT\"" "$CFG_TOML" \
  || fail "(B) relay.toml last_ckpt is STALE after a POST-push failure (acceptance 6): $(cat "$CFG_TOML")"
grep -qE '^ckptRecorded=true$' "$OUTF" || fail "(B) POST-push handback did not report ckptRecorded=true"
POST_JSON="$(parse_of "$OUTF")"
[[ "$(jget merged <<<"$POST_JSON")" == "False" ]] \
  || fail "(B) parse reported merged=true — the caller would take the SUCCESS path and double-count the unit"
[[ "$(jget landedUnfinished <<<"$POST_JSON")" == "True" ]] \
  || fail "(B) parse did not mark the POST-push failure LANDED-BUT-UNFINISHED: $POST_JSON"
[[ "$(jget deferred <<<"$POST_JSON")" == "False" ]] \
  || fail "(B) parse marked a POST-push (already-pushed) failure DEFERRED — it would be re-merged: $POST_JSON"
[[ "$(jget handbackStep <<<"$POST_JSON")" == "worktree-retire" ]] || fail "(B) parse lost the handback step: $POST_JSON"
[[ "$(jget mergedSha <<<"$POST_JSON")" == "$MERGED_SHA_WIRE" ]] || fail "(B) parse lost the merged sha: $POST_JSON"
[[ "$(jget partial <<<"$POST_JSON")" == "worktree-retire" ]] \
  || fail "(B/2c2a) parseIntegrateResult DROPPED partial= — a partial must never land silently: $POST_JSON"
[[ "$(jget handbackCode <<<"$POST_JSON")" == "28" ]] \
  || fail "(B/2c2a) parseIntegrateResult DROPPED handbackCode: $POST_JSON"
pass "(B) POST-push failure (retire, code 28): exit 0 with partial=<step>+merged=<sha>+handback=<step> on stdout, parsed as LANDED-BUT-UNFINISHED, last_ckpt reconciled"

# ── the two caller states genuinely DIFFER (the whole point of the item) ──
[[ "$(jget deferred <<<"$PRE_JSON")" != "$(jget deferred <<<"$POST_JSON")" ]] \
  || fail "PRE-push and POST-push failures produce the SAME caller state — indistinguishable, the id:5fe2 bug"
pass "(A/B) the caller's resulting state DIFFERS between the two classes"

# =====================================================================================
# (C) push(27) — SUPERSEDED BY id:a726(a). This case used to assert DEFERRED (acceptance 4:
#     "the push failed, so the remote is untouched, so a retry is correct"). That premise was
#     WRONG about the local side: step 7 writes the ckpt tag BEFORE step 8 pushes, so by the
#     time a push can fail the merge is on main AND tagged. A retry takes the zero-commit path
#     and is stopped by id:8739's isolation gate at exit 21, reported as a FALSE main-checkout
#     breach for a unit that is really "already merged and tagged, push failed".
#     The class is therefore LANDED-BUT-UNFINISHED — the same class as (B) — and id:5155 adds
#     the durable ratification-queue entry that makes it actionable.
# =====================================================================================
CASE_EXTRA=(--substantive false)   # id:4d44 — only a NON-substantive unit still pushes
run_case push INTEGRATE_GIT_LOCK_PUSH="$BAD_STUB"
CASE_EXTRA=()
[[ $RC -eq 0 ]] || fail "(C) id:2c2a: push(code 27) is a reached verdict and must exit 0, got $RC: $(cat "$ERRF")"
grep -qx 'handbackCode=27' "$OUTF" || fail "(C) STDOUT lost the numeric step identity (handbackCode=27): $(cat "$OUTF")"
grep -qE '^merged=' "$OUTF" \
  || fail "(C/a726a) push(27) hid the landed merge — the merge + ckpt tag ARE committed, so merged= must be on the wire: $(cat "$OUTF")"
grep -qx 'partial=git-lock-push' "$OUTF" \
  || fail "(C/2c2a) push(27) is LANDED-BUT-UNFINISHED but carried no partial= marker: $(cat "$OUTF")"
PUSH_JSON="$(parse_of "$OUTF")"
[[ "$(jget deferred <<<"$PUSH_JSON")" == "False" ]] \
  || fail "(C/a726a) push(27) parsed as DEFERRED — the caller would retry a merge that is already on main and already tagged: $PUSH_JSON"
[[ "$(jget landedUnfinished <<<"$PUSH_JSON")" == "True" ]] \
  || fail "(C/a726a) push(27) not parsed as LANDED-BUT-UNFINISHED: $PUSH_JSON"
[[ "$(jget handbackStep <<<"$PUSH_JSON")" == "git-lock-push" ]] || fail "(C) parse lost the handback step: $PUSH_JSON"
pass "(C/a726a) push(27) is LANDED-BUT-UNFINISHED, not a retryable defer (acceptance 4, superseded by id:a726(a))"

# =====================================================================================
# (D) HAPPY PATH UNCHANGED — a full success still parses as merged (no regression).
# =====================================================================================
MAIN_OK="$(build ok)"; REPO_OK="$(basename "$MAIN_OK")"
git -C "$MAIN_OK" worktree add -q -b relay/ok "$TMP/wt-ok" main
echo work > "$TMP/wt-ok/g"; git -C "$TMP/wt-ok" add -A; git -C "$TMP/wt-ok" commit -qm "child work id:test"
mkdir -p "$TMP/cfg-ok"
printf '[publish]\ndefault_remotes = ["origin"]\n\n[repos.%s]\nstatus = "active"\n' "$REPO_OK" > "$TMP/cfg-ok/relay.toml"   # id:c82a — see build() above
OKRC=0
FABLES_CONFIG="$TMP/cfg-ok" INTEGRATE_GIT_LOCK_PUSH="$OK_STUB" \
  "$INT" --repo "$REPO_OK" --path "$MAIN_OK" --worktree "$TMP/wt-ok" --branch relay/ok \
         --summary "test close id:test" --run testrun \
         --label "reviewer (claude-opus-4-8, integrate)" --ids test --level patch \
         --verdict execute >"$TMP/out-ok" 2>"$TMP/err-ok" || OKRC=$?
[[ $OKRC -eq 0 ]] || fail "(D) happy path exited $OKRC: $(cat "$TMP/err-ok")"
grep -qE '^handback=' "$TMP/out-ok" && fail "(D) a SUCCESSFUL integrate emitted a handback= line"
OK_JSON="$(node "$PARSE" "$JS" "$TMP/out-ok")"
[[ "$(jget merged <<<"$OK_JSON")" == "True" ]] || fail "(D) happy path no longer parses as merged: $OK_JSON"
[[ "$(jget landedUnfinished <<<"$OK_JSON")" == "False" ]] || fail "(D) happy path parsed as landed-but-unfinished: $OK_JSON"
[[ "$(jget deferred <<<"$OK_JSON")" == "False" ]] || fail "(D) happy path parsed as deferred: $OK_JSON"
pass "(D) happy path still parses as a plain merged success (no regression)"

# =====================================================================================
# (E) CALL SITE — the landed-but-unfinished result must have its OWN branch that never
#     takes the success path, and must be surfaced (never silently retried).
# =====================================================================================
grep -q 'result.landedUnfinished' "$JS" \
  || fail "(E) relay-loop.js's integrate call site never branches on result.landedUnfinished — a landed unit is still treated as a plain defer"
pass "(E) the integrate call site has a distinct landed-but-unfinished branch"

echo "ALL PASS: id:5fe2 post-push integrate failures are distinguishable from retryable defers"

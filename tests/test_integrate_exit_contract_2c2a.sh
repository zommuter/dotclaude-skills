#!/usr/bin/env bash
# id:2c2a — integrate.sh's exit code must stop conflating "I did my job and refused" with
# "I could not reach a verdict".
#
# NO `# roadmap:XXXX` HEADER ON PURPOSE: id:2c2a is a TODO.md item and has no ROADMAP.md
# twin, so there is no checkbox for the harness's EXPECTED-RED rule to key on. Per
# tests/run-tests.sh's convention a test without the header always counts — which is what a
# contract change with real regression risk should do.
#
# OWNER-RATIFIED CONTRACT (2026-08-26):
#   • exit 0 whenever integrate.sh REACHED a verdict and executed it — merged, OR legitimately
#     refused. A handback IS the mechanism working (the relay's own `agent-failures=0`, id:06a1,
#     already excludes handbacks by definition).
#   • non-zero reserved for genuinely UNDETERMINABLE outcomes — it never reached a verdict.
#   • the landed-but-unfinished case (merge COMMITTED+TAGGED+PUSHED, only a post-land tail step
#     failed) is exit 0 carrying a distinct `partial=` marker in stdout.
#
# THE REGRESSION THIS FILE GUARDS: the step identity used to ride on the exit code (16 distinct
# EX_* codes). Flattening them to 0 destroys that identity unless it moves WHOLLY into the
# parsed stdout contract first. So every case below is checked PER PATH — not once — for
# `handback=<step>` + `handbackCode=<N>` + `handbackReason=` on STDOUT, which is the only
# channel mechanical-proxy.py returns on a zero exit.
# fails-against: rev 5979484a40b3 -- the tree as it stood immediately before the commit that
#   added this test, i.e. the pre-fix relay/scripts/integrate.sh, relay/scripts/relay-loop.js. Derived + verified by tests/verify-negative-cases.py.
# fails-against-rev: 5979484a40b3 -- relay/scripts/integrate.sh relay/scripts/relay-loop.js
# fails-against-assertion: — id:2c2a reserves non-zero for UNDETERMINABLE outcomes. stderr:

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

OK_STUB="$TMP/ok.sh";   printf '#!/usr/bin/env bash\nexit 0\n' > "$OK_STUB";   chmod +x "$OK_STUB"
BAD_STUB="$TMP/bad.sh"; printf '#!/usr/bin/env bash\necho "injected failure" >&2\nexit 1\n' > "$BAD_STUB"; chmod +x "$BAD_STUB"
DIV_STUB="$TMP/div.sh"; printf '#!/usr/bin/env bash\necho "diverged 1 1"\nexit 3\n' > "$DIV_STUB"; chmod +x "$DIV_STUB"

# ── hermetic fixture: a LOCAL bare "remote" + main checkout + a child worktree. Every remote
#    here is a path inside $TMP, so nothing can reach the network (the id:99b7 lesson: a
#    fixture holding a real remote URL WILL act on it). ──
build() { # <suffix> → prints the main checkout path
  local sfx="$1"
  local origin="$TMP/o-$sfx.git" seed="$TMP/s-$sfx" main="$TMP/m-$sfx"
  git init --bare -b main -q "$origin"
  git clone -q "$origin" "$seed" 2>/dev/null
  git -C "$seed" config user.email t@e.st; git -C "$seed" config user.name t
  echo base > "$seed/f"
  printf '# Roadmap\n\n- [ ] [ROUTINE] the worked item <!-- id:aaaa -->\n' > "$seed/ROADMAP.md"
  printf '[project]\nname = "x"\nversion = "0.4.0"\n' > "$seed/pyproject.toml"
  git -C "$seed" add -A; git -C "$seed" commit -qm base; git -C "$seed" push -q -u origin main
  git clone -q "$origin" "$main" 2>/dev/null
  git -C "$main" config user.email t@e.st; git -C "$main" config user.name t
  printf '%s' "$main"
}

# run_path <suffix> <extra-toml-line|-> <case-extra-args-csv|-> <env-assignments...>
#   → sets RC / OUTF / ERRF / MAIN_PATH
run_path() {
  local sfx="$1" tomlx="$2" extra="$3"; shift 3
  MAIN_PATH="$(build "$sfx")"
  local repo; repo="$(basename "$MAIN_PATH")"
  local wt="$TMP/wt-$sfx"
  git -C "$MAIN_PATH" worktree add -q -b "relay/$sfx" "$wt" main
  echo work > "$wt/g"; git -C "$wt" add -A; git -C "$wt" commit -qm "child work id:aaaa"
  local cfg="$TMP/cfg-$sfx"; mkdir -p "$cfg"
  # id:c82a — `[publish]` is declared EXPLICITLY, exactly as the live relay.toml does. Left
  # FLOORED, a local bare `origin` that cannot be PROVEN private is withheld from the publish
  # set, so the push/post-push step codes below would never be reached. The floor's own
  # behaviour is specified in tests/test_publish_floor_privacy_gate_c82a.sh.
  { printf '[publish]\ndefault_remotes = ["origin"]\n\n[repos.%s]\nstatus = "active"\n' "$repo"
    [[ "$tomlx" != "-" ]] && printf '%s\n' "$tomlx"; } > "$cfg/relay.toml"
  OUTF="$TMP/out-$sfx"; ERRF="$TMP/err-$sfx"
  local -a xargs=()
  [[ "$extra" != "-" ]] && IFS=' ' read -r -a xargs <<<"$extra"
  RC=0
  env FABLES_CONFIG="$cfg" "$@" \
    "$INT" --repo "$repo" --path "$MAIN_PATH" --worktree "$wt" --branch "relay/$sfx" \
           --summary "close id:aaaa" --run testrun --ids aaaa ${LEVEL_ARG:+--level $LEVEL_ARG} \
           --label "executor (claude-sonnet-4-5, relay-loop)" --verdict execute \
           ${xargs[@]+"${xargs[@]}"} >"$OUTF" 2>"$ERRF" || RC=$?
}
# An explicit `--level` RESOLVES the bump trigger, so the bump(30) case must omit it.
LEVEL_ARG=patch

# assert_path <label> <step> <code> — the PER-PATH attribution check.
assert_path() {
  local label="$1" step="$2" code="$3"
  [[ $RC -eq 0 ]] \
    || fail "($label) a REACHED-AND-EXECUTED refusal exited $RC — id:2c2a reserves non-zero for UNDETERMINABLE outcomes. stderr: $(tr '\n' ' ' <"$ERRF" | cut -c1-400)"
  grep -qx "handback=$step" "$OUTF" \
    || fail "($label) STDOUT carries no handback=$step — the step identity the exit code used to carry was LOST: $(cat "$OUTF")"
  grep -qx "handbackCode=$code" "$OUTF" \
    || fail "($label) STDOUT carries no handbackCode=$code — attribution regressed to a bare 'it refused': $(cat "$OUTF")"
  grep -q '^handbackReason=..*' "$OUTF" \
    || fail "($label) STDOUT carries no non-empty handbackReason= — with exit 0 the proxy DROPS stderr, so the cause would never reach the operator: $(cat "$OUTF")"
  grep -q "HANDBACK\[$step\]" "$ERRF" \
    || fail "($label) the loud human HANDBACK[$step] line vanished from stderr"
  SEEN_CODES+=("$code")
}

SEEN_CODES=()

# =====================================================================================
# (1) EVERY injectable handback path, one at a time. This is the "per-path, not once"
#     assertion the item's trap warns about.
# =====================================================================================
run_path cleantree - - INTEGRATE_CLEAN_TREE_GATE="$BAD_STUB"
assert_path 1/clean-tree clean-tree 20

run_path iso - - INTEGRATE_CLEAN_TREE_GATE="$OK_STUB" INTEGRATE_VERIFY_ISOLATION="$BAD_STUB"
assert_path 1/verify-isolation verify-isolation 21

run_path sync - - INTEGRATE_CLEAN_TREE_GATE="$OK_STUB" INTEGRATE_VERIFY_ISOLATION="$OK_STUB" \
                  INTEGRATE_SYNC_ORIGIN="$DIV_STUB"
assert_path 1/sync-origin sync-origin 22

# merge(23): a conflicting commit on main so the child branch cannot merge cleanly.
run_path merge - - INTEGRATE_CLEAN_TREE_GATE="$OK_STUB" INTEGRATE_VERIFY_ISOLATION="$OK_STUB" \
                   INTEGRATE_SYNC_ORIGIN="$OK_STUB"
# (the fixture above already merged; rebuild one that conflicts)
MC="$(build mergeconf)"; RCP="$(basename "$MC")"
git -C "$MC" worktree add -q -b relay/mergeconf "$TMP/wt-mergeconf" main
echo childside > "$TMP/wt-mergeconf/f"
git -C "$TMP/wt-mergeconf" add -A; git -C "$TMP/wt-mergeconf" commit -qm "child work id:aaaa"
echo mainside > "$MC/f"; git -C "$MC" add -A; git -C "$MC" commit -qm "conflict seed"
mkdir -p "$TMP/cfg-mergeconf"
printf '[repos.%s]\nstatus = "active"\n' "$RCP" > "$TMP/cfg-mergeconf/relay.toml"
OUTF="$TMP/out-mergeconf"; ERRF="$TMP/err-mergeconf"; RC=0
env FABLES_CONFIG="$TMP/cfg-mergeconf" INTEGRATE_CLEAN_TREE_GATE="$OK_STUB" \
    INTEGRATE_VERIFY_ISOLATION="$OK_STUB" INTEGRATE_SYNC_ORIGIN="$OK_STUB" \
  "$INT" --repo "$RCP" --path "$MC" --worktree "$TMP/wt-mergeconf" --branch relay/mergeconf \
         --summary "close id:aaaa" --run testrun --ids aaaa --level patch \
         --label "executor (claude-sonnet-4-5, relay-loop)" --verdict execute \
         >"$OUTF" 2>"$ERRF" || RC=$?
assert_path 1/merge merge 23

run_path vbump - - INTEGRATE_VERSION_BUMP="$BAD_STUB" INTEGRATE_GIT_LOCK_PUSH="$OK_STUB"
assert_path 1/version-bump version-bump 24

run_path clog - - INTEGRATE_CHANGELOG_APPEND="$BAD_STUB" INTEGRATE_GIT_LOCK_PUSH="$OK_STUB"
assert_path 1/changelog-append changelog-append 25

run_path ckpt - - INTEGRATE_CKPT_TAG="$BAD_STUB" INTEGRATE_GIT_LOCK_PUSH="$OK_STUB"
assert_path 1/ckpt-tag ckpt-tag 26

# push(27): only a NON-substantive unit still pushes (id:4d44), so ask for that explicitly.
run_path push - "--substantive false" INTEGRATE_GIT_LOCK_PUSH="$BAD_STUB"
assert_path 1/git-lock-push git-lock-push 27

run_path retire - - INTEGRATE_GIT_LOCK_PUSH="$OK_STUB" INTEGRATE_WORKTREE_RETIRE="$BAD_STUB"
assert_path 1/worktree-retire worktree-retire 28

# ratify-enqueue(35): the durable queue append rides on relay-state-write's event-append, so a
# wholly-failing state writer stops there — which is exactly the path this reaches.
run_path ratify - - INTEGRATE_STATE_WRITE="$BAD_STUB" INTEGRATE_GIT_LOCK_PUSH="$OK_STUB"
assert_path 1/ratify-enqueue ratify-enqueue 35

# state-write(29): a SELECTIVE writer — real for everything except `toml-set <repo> status`,
# so the enqueue and the last_ckpt write succeed and the failure lands on step 10 itself.
SEL_STATE="$TMP/state-sel.sh"
cat > "$SEL_STATE" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "toml-set" ] && [ "\$3" = "status" ]; then echo "injected failure" >&2; exit 1; fi
exec "$SRC_DIR/relay/scripts/relay-state-write.sh" "\$@"
EOF
chmod +x "$SEL_STATE"
run_path statew - - INTEGRATE_STATE_WRITE="$SEL_STATE" INTEGRATE_GIT_LOCK_PUSH="$OK_STUB"
assert_path 1/state-write state-write 29

run_path tick - - INTEGRATE_ROADMAP_TICK="$BAD_STUB" INTEGRATE_GIT_LOCK_PUSH="$OK_STUB"
assert_path 1/roadmap-tick roadmap-tick 31

run_path arch - - INTEGRATE_ROADMAP_ARCHIVE="$BAD_STUB" INTEGRATE_GIT_LOCK_PUSH="$OK_STUB"
assert_path 1/roadmap-archive roadmap-archive 32

# bump(30): a PRESENT-BUT-UNPARSED near-miss policy key leaves the trigger UNDETERMINABLE
# for the BUMP decision — but integrate.sh still reaches the verdict "refuse", so exit 0.
LEVEL_ARG=""
run_path bumpbad 'bumppolicy = "never"' - INTEGRATE_GIT_LOCK_PUSH="$OK_STUB"
LEVEL_ARG=patch
assert_path 1/bump bump 30

# wiring(34): a required helper missing entirely.
run_path wiring - - INTEGRATE_STRANDED_SCAN="$TMP/does-not-exist.sh" INTEGRATE_GIT_LOCK_PUSH="$OK_STUB"
assert_path 1/wiring sibling-scan 34

# Every code observed must be DISTINCT — the whole point is that flattening the EXIT status
# did not flatten the ATTRIBUTION.
UNIQ="$(printf '%s\n' "${SEEN_CODES[@]}" | sort -u | wc -l)"
[[ "$UNIQ" -eq "${#SEEN_CODES[@]}" ]] \
  || fail "(1) the ${#SEEN_CODES[@]} exercised paths produced only $UNIQ distinct handbackCodes — attribution collapsed: ${SEEN_CODES[*]}"
pass "(1) ${#SEEN_CODES[@]} distinct handback paths each exit 0 and each carry their OWN handback=/handbackCode=/handbackReason= on stdout"

# =====================================================================================
# (2) STRUCTURAL: the ONLY non-zero exits left in integrate.sh are the UNDETERMINABLE class.
#     15 of the 16 step codes are exercised live above; strong-state (33) is the one with no
#     cheap injection seam, and it funnels through the same single `handback()` — which is
#     what this block proves, together with "no non-zero exit survives outside EX_USAGE".
# =====================================================================================
# Code lines only (comments stripped), and only a REAL `exit <nonzero>` / `exit "$EX_*"`.
BAD_EXITS="$(awk '!/^[[:space:]]*#/ && /(^|[;&|[:space:]])exit ([1-9][0-9]*|"\$EX_[A-Z_]+")/ {print NR": "$0}' "$INT" \
             | grep -v 'EX_USAGE' || true)"
[[ -z "$BAD_EXITS" ]] \
  || fail "(2) integrate.sh still has a non-zero exit outside the UNDETERMINABLE class (only EX_USAGE may remain): $BAD_EXITS"
grep -q 'exit "\$code"' "$INT" \
  && fail "(2) handback() still exits with the step's code — the flattening was reverted"
grep -qE '^\s*exit 0\s*$' <<<"$(sed -n '/^handback() {/,/^}/p' "$INT")" \
  || fail "(2) handback() does not end in 'exit 0' — the flattening is not actually in place"
for code in 33 35; do
  grep -q "EX_[A-Z]*=$code" "$INT" || fail "(2) step-identity code $code disappeared from integrate.sh"
done
grep -q 'handback strong-state "\$EX_STRONG"' "$INT" \
  || fail "(2) the strong-state path no longer routes through handback() — its identity would be lost"
grep -q 'handback ratify-enqueue "\$EX_RATIFY"' "$INT" \
  || fail "(2) the ratify-enqueue path no longer routes through handback() — its identity would be lost"
pass "(2) EX_USAGE is the only surviving non-zero exit; every step code still routes through the single handback()"

# =====================================================================================
# (3) UNDETERMINABLE stays NON-ZERO — the other half of the contract. A mis-invocation
#     never reaches a verdict at all, so it must NOT be flattened to 0.
# =====================================================================================
rc=0; out="$("$INT" --repo x --path "$TMP/not-a-repo" --worktree /tmp --branch b \
                    --summary s --run r --label l 2>&1)" || rc=$?
[[ $rc -ne 0 ]] || fail "(3) a mis-invocation (no verdict was ever reached) exited 0: $out"
grep -q 'handback=' <<<"$out" && fail "(3) a mis-invocation emitted a handback= line — it is not a verdict"
rc=0; out="$("$INT" --repo x --nonsense 2>&1)" || rc=$?
[[ $rc -eq 2 ]] || fail "(3) an unknown argument must exit EX_USAGE=2, got $rc: $out"
pass "(3) genuinely UNDETERMINABLE outcomes (mis-invocation) still exit non-zero, with no handback= line"

# =====================================================================================
# (4) partial= — the landed-but-unfinished marker, produced by the REAL script and consumed
#     by the REAL parseIntegrateResult, then surfaced by the REAL call site.
# =====================================================================================
run_path partial - - INTEGRATE_GIT_LOCK_PUSH="$OK_STUB" INTEGRATE_WORKTREE_RETIRE="$BAD_STUB"
[[ $RC -eq 0 ]] || fail "(4) landed-but-unfinished exited $RC — the merge was COMMITTED and TAGGED; it succeeded at everything that matters"
grep -qx 'partial=worktree-retire' "$OUTF" \
  || fail "(4) no partial=<step> marker on stdout: $(cat "$OUTF")"
grep -qx 'landed=true' "$OUTF" || fail "(4) partial= was emitted without landed=true"
grep -qE '^merged=[0-9a-f]{7,}$' "$OUTF" || fail "(4) partial= was emitted without the merged sha"

PARSE="$TMP/parse.js"
cat > "$PARSE" <<'NODEEOF'
const fs = require("fs");
const src = fs.readFileSync(process.argv[2], "utf8");
const start = src.indexOf("function parseIntegrateResult(raw) {");
if (start < 0) { console.error("parseIntegrateResult not found"); process.exit(1); }
let depth = 0, end = -1;
for (let p = src.indexOf("{", start); p < src.length; p++) {
  if (src[p] === "{") depth++;
  else if (src[p] === "}") { depth--; if (depth === 0) { end = p + 1; break } }
}
const fn = eval("(" + src.slice(start, end).replace(/^function parseIntegrateResult/, "function") + ")");
const r = fn(fs.readFileSync(process.argv[3], "utf8")) || {};
console.log(JSON.stringify({
  merged: !!r.merged, landedUnfinished: !!r.landedUnfinished, deferred: !!r.deferred,
  partial: r.partial || "", handbackCode: r.handbackCode || "",
  handbackReason: r.handbackReason || "", handbackStep: r.handbackStep || "",
}));
NODEEOF
J="$(node "$PARSE" "$JS" "$OUTF")"
jget() { python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"; }
[[ "$(jget partial <<<"$J")" == "worktree-retire" ]] \
  || fail "(4) parseIntegrateResult DROPPED partial= — a partial must never land silently: $J"
[[ "$(jget handbackCode <<<"$J")" == "28" ]] || fail "(4) parseIntegrateResult dropped handbackCode: $J"
[[ -n "$(jget handbackReason <<<"$J")" ]] || fail "(4) parseIntegrateResult dropped handbackReason: $J"
[[ "$(jget landedUnfinished <<<"$J")" == "True" ]] || fail "(4) a partial did not classify as LANDED-BUT-UNFINISHED: $J"
[[ "$(jget merged <<<"$J")" == "False" ]] || fail "(4) a partial was parsed as a plain success: $J"

# A PRE-LAND handback must carry NO partial= — the marker is for case (ii) only.
run_path nopartial - - INTEGRATE_CHANGELOG_APPEND="$BAD_STUB" INTEGRATE_GIT_LOCK_PUSH="$OK_STUB"
grep -qE '^partial=' "$OUTF" && fail "(4) a PRE-LAND handback emitted partial= — the marker would stop discriminating case (ii)"
JP="$(node "$PARSE" "$JS" "$OUTF")"
[[ -z "$(jget partial <<<"$JP")" ]] || fail "(4) parse invented a partial for a pre-land handback: $JP"
pass "(4) partial=<step> is emitted on exactly the landed-but-unfinished case and survives the real parser"

# =====================================================================================
# (5) partial= REACHES THE OPERATOR — it must not land silently in relay-loop.js.
# =====================================================================================
grep -q 'id:2c2a PARTIAL integrate for' "$JS" \
  || fail "(5) relay-loop.js has no unconditional log for a parsed partial= — it would land silently"
grep -q 'id:2c2a CONTRACT INVARIANT' "$JS" \
  || fail "(5) relay-loop.js does not shout when partial= arrives without the landedUnfinished class"
grep -q "k === 'partial'" "$JS" || fail "(5) parseIntegrateResult does not parse the partial= key at all"
# and the surfaced handback reason names it, so it reaches RELAY_STATUS/the handback surface.
grep -q 'id:2c2a partial=' "$JS" \
  || fail "(5) the LANDED-BUT-UNFINISHED handback reason does not name partial= — the operator surface lost it"
pass "(5) a parsed partial= is logged unconditionally AND named in the operator-facing handback reason"

echo "ALL PASS: id:2c2a integrate.sh exit contract — refusals exit 0 with per-path attribution on stdout, undeterminable stays non-zero, partial= surfaced"

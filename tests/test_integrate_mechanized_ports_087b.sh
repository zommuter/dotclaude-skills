#!/usr/bin/env bash
# roadmap:087b — BEHAVIOURAL proof that the five LLM-only integrator behaviours really run
# inside relay/scripts/integrate.sh, and that the one residual (the semver bump trigger) fails
# LOUD instead of guessing. Structural greps live in the tests those behaviours came from
# (test_relay_driver_ticks, test_roadmap_archive_wired_f54d, test_fable_recheck_write_side,
# test_discover_pushseed, test_version_bump); this file EXERCISES them against real fixture
# repos, because a grep cannot tell a wired step from a step that runs and does nothing.
#
# Covered, one section each:
#   (1) ROADMAP tick (id:5b12)    — fires for execute/hard, scoped-commits, and is NOT applied
#                                   to a review unit (those self-tick in their own worktree).
#   (2) archive-done (id:f54d)    — a prior-commit [x] item moves to ROADMAP.archive.md.
#   (3) Fable-recheck keys (e030) — a STRONG unit writes all three; an EXECUTE unit writes NONE
#                                   (the masking bug), and both --fable-recheck branches differ.
#   (4) L2 push-seed (id:c855)    — postSig/openRoutine/openHard are emitted, counted from the
#                                   POST-integrate ROADMAP (i.e. after the tick + archive).
#   (5) sibling surfacing (dd7d)  — a sibling branch is surfaced VERBATIM, the unit's own branch
#                                   is NOT, and the merge lands either way (surface, never block).
#   (6) bump trigger (id:e647)    — version-less repo: no bump, no handback. Manifest repo with
#                                   a substantive close and no recorded policy: the id:65ad
#                                   FLEET DEFAULT minor. An UNRECOGNISED bump_policy value is
#                                   still HANDBACK[bump] with its own exit code and NOTHING
#                                   mutated (main unmoved). --no-bump and --level remain the
#                                   two explicit caller resolutions.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# $INT_OVERRIDE points this suite at a MIRRORED relay/scripts tree — the seam used to run a
# negative control (mutate one line in the mirror, confirm the matching assertion goes red).
# It must be a full mirror, not a lone copied file: integrate.sh resolves its helpers from
# its own $SCRIPT_DIR, so a copy elsewhere fails for the wrong reason and proves nothing.
INT="${INT_OVERRIDE:-$SRC_DIR/relay/scripts/integrate.sh}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Sections that PARSE integrate.sh's stdout must keep stderr out of the capture, but a
# swallowed stderr turns any future failure into an undiagnosable red — so it goes to a file
# and every failure message replays its tail. (This file flaked once, unreproduced, in a
# full-suite parallel run on 2026-08-20; without this the next occurrence would be just as
# opaque as that one was.)
ERRLOG="$TMP/integrate.stderr"
: >"$ERRLOG"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; [[ -s "$ERRLOG" ]] && { echo "       last integrate.sh stderr:"; tail -n 20 "$ERRLOG" | sed 's/^/       | /'; }; exit 1; }

[[ -x "$INT" ]] || fail "integrate.sh not found/executable at $INT"

# id:f5d9(a) — this stub must REALLY push (into the fixture's local bare origin), not just
# exit 0. integrate.sh now VERIFIES the push against the remote ref instead of trusting the
# helper's exit code, so the old `exit 0` stub is now correctly reported as push=FAILED —
# it was modelling the id:dc4f defect, not a working push. Still hermetic: `origin` is a bare
# repo under $TMP and no network is touched.
PUSH_STUB="$TMP/push-stub.sh"
cat > "$PUSH_STUB" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
p=""
for a in "$@"; do case "$a" in --ff-only|-b|-m|-f) ;; *) p="$a" ;; esac; done
git -C "$p" push --follow-tags origin HEAD >/dev/null 2>&1
EOF
chmod +x "$PUSH_STUB"

# ── hermetic origin + main checkout, optionally seeded with a ROADMAP.md ──
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

# A child worktree with one commit, on branch relay/<name>.
child() { # <main> <name> → prints the worktree path
  # NOTE: `local a=$1 b=$TMP/$a` does NOT work — bash expands every word before running
  # `local`, so `$a` is still unbound. Assign on separate lines.
  local main="$1" name="$2"
  local wt="$TMP/wt-$name"
  git -C "$main" worktree add -q -b "relay/$name" "$wt" main
  echo "work-$name" > "$wt/g-$name"
  git -C "$wt" add -A
  git -C "$wt" commit -qm "child work $name"
  printf '%s' "$wt"
}

cfg() { # <suffix> <repo-name> → prints the config dir, with a [repos.<name>] block
  local d="$TMP/cfg-$1"
  mkdir -p "$d"
  printf '[repos.%s]\nstatus = "active"\n' "$2" > "$d/relay.toml"
  printf '%s' "$d"
}

# =====================================================================================
# (1) ROADMAP tick (id:5b12) — execute ticks; review does NOT get driver-ticked
# =====================================================================================
cat > "$TMP/rm-tick.md" <<'EOF'
# Roadmap

- [ ] [ROUTINE] the worked item <!-- id:aaaa -->
- [ ] [ROUTINE] an untouched item <!-- id:bbbb -->
- [ ] [HARD] a hard item <!-- id:cccc -->
EOF

MT="$(build tick "$TMP/rm-tick.md")"; RT="$(basename "$MT")"
WTT="$(child "$MT" tick)"
CT="$(cfg tick "$RT")"
rc=0
out="$(FABLES_CONFIG="$CT" INTEGRATE_GIT_LOCK_PUSH="$PUSH_STUB" \
  "$INT" --repo "$RT" --path "$MT" --worktree "$WTT" --branch relay/tick \
         --summary "close aaaa" --run r1 --label "executor (sonnet, relay-loop)" \
         --ids aaaa --verdict execute --substantive true 2>&1)" || rc=$?
[[ $rc -eq 0 ]] || fail "(1) execute integrate exited $rc: $out"
grep -q '^- \[x\].*id:aaaa' "$MT/ROADMAP.md" || fail "(1) worked id aaaa was NOT ticked in the canonical checkout"
grep -q '^- \[ \].*id:bbbb' "$MT/ROADMAP.md" || fail "(1) an unworked item was ticked — the tick is not id-scoped"
# the tick was COMMITTED (a dirty ROADMAP would have tripped worktree-retire)
[[ -z "$(git -C "$MT" status --porcelain)" ]] || fail "(1) tree left dirty after integrate — the tick was not committed"
grep -q 'tick worked items' < <(git -C "$MT" log --oneline -- ROADMAP.md) \
  || fail "(1) no scoped 'tick worked items' commit"
pass "(1) id:5b12 driver-side tick fires for an execute unit, id-scoped, and is committed"

# review: the child self-ticks in its own worktree, so the driver must NOT tick here
MR="$(build tickrev "$TMP/rm-tick.md")"; RR="$(basename "$MR")"
WTR="$(child "$MR" tickrev)"
CR="$(cfg tickrev "$RR")"
rc=0
out="$(FABLES_CONFIG="$CR" INTEGRATE_GIT_LOCK_PUSH="$PUSH_STUB" \
  "$INT" --repo "$RR" --path "$MR" --worktree "$WTR" --branch relay/tickrev \
         --summary "review pass" --run r1 --label "reviewer (claude-opus-5, relay-loop)" \
         --ids aaaa --verdict review --substantive true --strong-model claude-opus-5 2>&1)" || rc=$?
[[ $rc -eq 0 ]] || fail "(1b) review integrate exited $rc: $out"
grep -q '^- \[ \].*id:aaaa' "$MR/ROADMAP.md" \
  || fail "(1b) a REVIEW unit was driver-ticked — review/handoff children tick in their own worktree"
pass "(1b) id:5b12 driver-side tick is correctly SKIPPED for a review unit"

# =====================================================================================
# (2) archive-done (id:f54d) — a [x] item present in HEAD moves to ROADMAP.archive.md
# =====================================================================================
cat > "$TMP/rm-arch.md" <<'EOF'
# Roadmap

- [x] [ROUTINE] a long-finished item <!-- id:dddd -->
- [ ] [ROUTINE] still open <!-- id:eeee -->
EOF
MA="$(build arch "$TMP/rm-arch.md")"; RA="$(basename "$MA")"
WTA="$(child "$MA" arch)"
CA="$(cfg arch "$RA")"
rc=0
out="$(FABLES_CONFIG="$CA" INTEGRATE_GIT_LOCK_PUSH="$PUSH_STUB" \
  "$INT" --repo "$RA" --path "$MA" --worktree "$WTA" --branch relay/arch \
         --summary "some close" --run r1 --label "executor (sonnet, relay-loop)" \
         --verdict execute --substantive true 2>&1)" || rc=$?
[[ $rc -eq 0 ]] || fail "(2) integrate exited $rc: $out"
[[ -f "$MA/ROADMAP.archive.md" ]] || fail "(2) ROADMAP.archive.md was not created — the archiver did not run"
grep -q 'id:dddd' "$MA/ROADMAP.archive.md" || fail "(2) the done item was not moved into the archive"
grep -q '^- \[ \].*id:eeee' "$MA/ROADMAP.md" || fail "(2) the archiver touched an OPEN item"
[[ -z "$(git -C "$MA" status --porcelain)" ]] || fail "(2) tree left dirty — the archive was not committed"
pass "(2) id:f54d archive-done runs at integrate, moves only done items, and is committed"

# =====================================================================================
# (3) durable Fable-recheck keys (id:e030) — STRONG writes three; EXECUTE writes none
# =====================================================================================
ME="$(build e030x)"; RE_="$(basename "$ME")"
WTE="$(child "$ME" e030x)"
CE="$(cfg e030x "$RE_")"
# pre-seed a PENDING recheck, exactly as a prior strong checkpoint would have left it
printf 'last_strong_ckpt = "relay-ckpt-PRIOR"\nstrong_model = "claude-opus-5"\nfable_rechecked = false\n' >> "$CE/relay.toml"
rc=0
out="$(FABLES_CONFIG="$CE" INTEGRATE_GIT_LOCK_PUSH="$PUSH_STUB" \
  "$INT" --repo "$RE_" --path "$ME" --worktree "$WTE" --branch relay/e030x \
         --summary "executor close" --run r1 --label "executor (sonnet, relay-loop)" \
         --verdict execute --substantive true 2>&1)" || rc=$?
[[ $rc -eq 0 ]] || fail "(3) execute integrate exited $rc: $out"
grep -q 'last_strong_ckpt = "relay-ckpt-PRIOR"' "$CE/relay.toml" \
  || fail "(3) THE id:e030 MASKING BUG: an EXECUTE checkpoint overwrote last_strong_ckpt"
grep -q 'fable_rechecked = false' "$CE/relay.toml" \
  || fail "(3) an EXECUTE checkpoint cleared the pending Fable recheck (id:e030)"
grep -q 'last_ckpt = ' "$CE/relay.toml" || fail "(3) the execute checkpoint did not write last_ckpt at all"
pass "(3) id:e030: an EXECUTE checkpoint updates last_ckpt and leaves the three strong keys untouched"

# STRONG, standin (no --fable-recheck) → fable_rechecked = bare false, keys refreshed
MS="$(build e030s)"; RS="$(basename "$MS")"
WTS="$(child "$MS" e030s)"
CS="$(cfg e030s "$RS")"
rc=0
out="$(FABLES_CONFIG="$CS" INTEGRATE_GIT_LOCK_PUSH="$PUSH_STUB" \
  "$INT" --repo "$RS" --path "$MS" --worktree "$WTS" --branch relay/e030s \
         --summary "strong close" --run r1 --label "reviewer (claude-opus-5, relay-loop)" \
         --verdict review --substantive true --strong-model claude-opus-5 2>&1)" || rc=$?
[[ $rc -eq 0 ]] || fail "(3b) strong integrate exited $rc: $out"
grep -qE 'last_strong_ckpt = "relay-ckpt-' "$CS/relay.toml" || fail "(3b) strong checkpoint did not write last_strong_ckpt"
grep -q 'strong_model = "claude-opus-5"' "$CS/relay.toml" || fail "(3b) strong checkpoint did not record strong_model"
grep -q 'fable_rechecked = false' "$CS/relay.toml" \
  || fail "(3b) an Opus-standin strong checkpoint must queue fable_rechecked = false (bare)"
pass "(3b) id:e030: a STRONG standin checkpoint writes all three keys with fable_rechecked = false"

# STRONG, real Fable (--fable-recheck) → fable_rechecked = today's ISO date, NOT false
MF="$(build e030f)"; RF="$(basename "$MF")"
WTF="$(child "$MF" e030f)"
CF="$(cfg e030f "$RF")"
rc=0
out="$(FABLES_CONFIG="$CF" INTEGRATE_GIT_LOCK_PUSH="$PUSH_STUB" \
  "$INT" --repo "$RF" --path "$MF" --worktree "$WTF" --branch relay/e030f \
         --summary "fable close" --run r1 --label "reviewer (claude-fable-5, relay-loop)" \
         --verdict handoff --substantive true --strong-model claude-fable-5 --fable-recheck 2>&1)" || rc=$?
[[ $rc -eq 0 ]] || fail "(3c) fable integrate exited $rc: $out"
grep -qE 'fable_rechecked = "[0-9]{4}-[0-9]{2}-[0-9]{2}"' "$CF/relay.toml" \
  || fail "(3c) id:6856: a REAL-Fable strong checkpoint must mark fable_rechecked with today's date, not false"
grep -q 'fable_rechecked = false' "$CF/relay.toml" \
  && fail "(3c) id:6856: the Fable branch recorded false — it queues a bogus Fable-rechecks-Fable review"
pass "(3c) id:e030/6856: a REAL-Fable strong checkpoint dates fable_rechecked (any strong verdict, incl. handoff)"

# =====================================================================================
# (4) L2 push-seed inputs (id:c855) — emitted, and counted from POST-integrate state
# =====================================================================================
# rm-tick.md has 2 open [ROUTINE] + 1 open [HARD]; run (1) ticked aaaa, so the settled
# post-integrate counts must be 1 routine and 1 hard — NOT the pre-integrate 2 and 1.
MP="$(build seed "$TMP/rm-tick.md")"; RP="$(basename "$MP")"
WTP="$(child "$MP" seed)"
CP="$(cfg seed "$RP")"
rc=0
sout="$(FABLES_CONFIG="$CP" INTEGRATE_GIT_LOCK_PUSH="$PUSH_STUB" \
  "$INT" --repo "$RP" --path "$MP" --worktree "$WTP" --branch relay/seed \
         --summary "close aaaa" --run r1 --label "executor (sonnet, relay-loop)" \
         --ids aaaa --verdict execute --substantive true 2>"$ERRLOG")" || rc=$?
[[ $rc -eq 0 ]] || fail "(4) integrate exited $rc"
grep -q '^postSig=' <<<"$sout" || fail "(4) no postSig= line — the push-seed input is missing"
grep -q '^openRoutine=1$' <<<"$sout" \
  || fail "(4) openRoutine is not counted from the POST-integrate ROADMAP (want 1 after the tick): $(grep '^openRoutine=' <<<"$sout")"
grep -q '^openHard=1$' <<<"$sout" \
  || fail "(4) openHard wrong (want 1): $(grep '^openHard=' <<<"$sout")"
grep -q '^ts=' <<<"$sout" || fail "(4) no ts= line (the fs-less Workflow sandbox cannot make one itself)"
# id:4d44 — this unit is `--substantive true`, so the push is now DEFERRED for owner
# ratification and the line reads `push=deferred`. `push=pushed` here would mean the
# ratification gate had stopped firing. The pushing half is asserted in
# tests/test_integrate_ratification_gate_4d44.sh, which owns that contract.
grep -q '^push=deferred$' <<<"$sout" || fail "(4) no push=deferred line for a substantive unit (id:4d44): $(grep '^push=' <<<"$sout")"
pass "(4) id:c855 push-seed inputs are emitted and reflect settled post-integrate state"

# a DRAINED repo (no ROADMAP.md at all) must report 0/0 rather than erroring
MD="$(build seeddry)"; RD="$(basename "$MD")"
WTD="$(child "$MD" seeddry)"
CD="$(cfg seeddry "$RD")"
rc=0
dout="$(FABLES_CONFIG="$CD" INTEGRATE_GIT_LOCK_PUSH="$PUSH_STUB" \
  "$INT" --repo "$RD" --path "$MD" --worktree "$WTD" --branch relay/seeddry \
         --summary "drained" --run r1 --label "executor (sonnet, relay-loop)" \
         --verdict execute --substantive true 2>"$ERRLOG")" || rc=$?
[[ $rc -eq 0 ]] || fail "(4b) integrate on a ROADMAP-less repo exited $rc"
grep -q '^openRoutine=0$' <<<"$dout" || fail "(4b) a repo with no ROADMAP.md must report openRoutine=0"
grep -q '^openHard=0$' <<<"$dout" || fail "(4b) a repo with no ROADMAP.md must report openHard=0"
pass "(4b) id:c855 counts are 0/0 (not an error) on a repo with no ROADMAP.md"

# =====================================================================================
# (5) sibling-branch surfacing (id:dd7d) — surface the sibling, never the own branch,
#     and NEVER block the merge
# =====================================================================================
MB="$(build sib)"; RB="$(basename "$MB")"
# This unit's own branch, named exactly as the pool names it: <run>-<verdict>-<item>-<attempt>
WTB="$TMP/wt-sib"
git -C "$MB" worktree add -q -b "relay/r9-execute-ffff-0" "$WTB" main
echo mine > "$WTB/mine"; git -C "$WTB" add -A; git -C "$WTB" commit -qm "own work"
OWN_SHA="$(git -C "$WTB" rev-parse HEAD)"
# a SIBLING branch for the SAME item from a prior attempt, carrying different commits
WTB2="$TMP/wt-sib2"
git -C "$MB" worktree add -q -b "relay/r8-execute-ffff-0" "$WTB2" main
echo theirs > "$WTB2/theirs"; git -C "$WTB2" add -A; git -C "$WTB2" commit -qm "prior attempt"
CB="$(cfg sib "$RB")"
rc=0
bout="$(FABLES_CONFIG="$CB" INTEGRATE_GIT_LOCK_PUSH="$PUSH_STUB" \
  "$INT" --repo "$RB" --path "$MB" --worktree "$WTB" --branch "relay/r9-execute-ffff-0" \
         --summary "close ffff" --run r9 --label "executor (sonnet, relay-loop)" \
         --ids ffff --verdict execute --substantive true 2>"$ERRLOG")" || rc=$?
[[ $rc -eq 0 ]] || fail "(5) a surfaced sibling BLOCKED the integrate (exit $rc) — this gate must never block"
git -C "$MB" merge-base --is-ancestor "$OWN_SHA" HEAD \
  || fail "(5) the unit's own branch did not merge — the sibling gate blocked it"
grep -q '^sibling=relay/r8-execute-ffff-0' <<<"$bout" \
  || fail "(5) the sibling branch was NOT surfaced: $(grep '^sibling=' <<<"$bout" || echo '<none>')"
grep -q '^sibling=relay/r9-execute-ffff-0' <<<"$bout" \
  && fail "(5) the unit's OWN branch was surfaced as a sibling — it is about to be merged, not a rival"
pass "(5) id:dd7d surfaces a real sibling verbatim, drops the own branch, and never blocks the merge"

# =====================================================================================
# (6) the ONE residual: the semver bump trigger (id:e647)
# =====================================================================================
# (6a) version-less repo (no manifest): no bump, NO handback — determinable by construction.
MV="$(build vless)"; RV="$(basename "$MV")"
WTV="$(child "$MV" vless)"
CV="$(cfg vless "$RV")"
rc=0
vout="$(FABLES_CONFIG="$CV" INTEGRATE_GIT_LOCK_PUSH="$PUSH_STUB" \
  "$INT" --repo "$RV" --path "$MV" --worktree "$WTV" --branch relay/vless \
         --summary "a user-observable close" --run r1 --label "executor (sonnet, relay-loop)" \
         --verdict execute --substantive true 2>"$ERRLOG")" || rc=$?
[[ $rc -eq 0 ]] || fail "(6a) a version-less repo must integrate without a bump handback (exit $rc)"
grep -q '^bump=$' <<<"$vout" || fail "(6a) a version-less repo reported a bump: $(grep '^bump=' <<<"$vout")"
pass "(6a) id:e647: a version-less repo never bumps and never hands back (dotclaude-skills' own case)"

# ── manifest-repo fixture builder (the case where a bump is actually possible) ──
build_manifest() { # <suffix> → prints the main checkout path
  local sfx="$1"
  local origin seed main
  origin="$TMP/o-$sfx.git"; seed="$TMP/s-$sfx"; main="$TMP/m-$sfx"
  git init --bare -b main -q "$origin"
  git clone -q "$origin" "$seed" 2>/dev/null
  git -C "$seed" config user.email t@e.st
  git -C "$seed" config user.name t
  echo base > "$seed/f"
  printf '[project]\nname = "x"\nversion = "0.4.0"\n' > "$seed/pyproject.toml"
  git -C "$seed" add -A
  git -C "$seed" commit -qm base
  git -C "$seed" push -q -u origin main
  git clone -q "$origin" "$main" 2>/dev/null
  git -C "$main" config user.email t@e.st
  git -C "$main" config user.name t
  printf '%s' "$main"
}

# (6b) AMENDED by id:65ad (owner-ratified 2026-08-22). The ABSENT-policy case is no longer
#      undeterminable — it takes the FLEET DEFAULT `minor`. The loud-handback assertions
#      below are NOT dropped: they are RETARGETED onto the case that is still genuinely
#      undeterminable, an explicit but UNRECOGNISED bump_policy value (a typo), which must
#      never be silently defaulted. Full precedence coverage: test_bump_policy_fleet_default_65ad.sh.
MM="$(build_manifest bumpask)"; RM_="$(basename "$MM")"
WTM="$(child "$MM" bumpask)"
CM="$(cfg bumpask "$RM_")"
rc=0
mout="$(FABLES_CONFIG="$CM" INTEGRATE_GIT_LOCK_PUSH="$PUSH_STUB" \
  "$INT" --repo "$RM_" --path "$MM" --worktree "$WTM" --branch relay/bumpask \
         --summary "close" --run r1 --label "executor (sonnet, relay-loop)" \
         --verdict execute --substantive true 2>"$ERRLOG")" || rc=$?
[[ $rc -eq 0 ]] || fail "(6b) an absent bump_policy did not take the id:65ad fleet default (exit $rc)"
grep -q '^bump=v0.5.0$' <<<"$mout" || fail "(6b) the fleet default did not mint a MINOR bump: $(grep '^bump=' <<<"$mout")"
pass "(6b) id:65ad: an absent bump_policy takes the fleet default MINOR bump (amends id:e647's handback)"

# (6b2) a TYPO'D bump_policy is still undeterminable → LOUD HANDBACK[bump], distinct exit,
#       and NOTHING mutated: main unmoved, worktree still on disk.
MZ="$(build_manifest bumpbad)"; RZ="$(basename "$MZ")"
WTZ="$(child "$MZ" bumpbad)"
CZ="$(cfg bumpbad "$RZ")"
printf 'bump_policy = "mnior"\n' >> "$CZ/relay.toml"
HEAD_BEFORE="$(git -C "$MZ" rev-parse HEAD)"
rc=0
zout="$(FABLES_CONFIG="$CZ" INTEGRATE_GIT_LOCK_PUSH="$PUSH_STUB" \
  "$INT" --repo "$RZ" --path "$MZ" --worktree "$WTZ" --branch relay/bumpbad \
         --summary "close" --run r1 --label "executor (sonnet, relay-loop)" \
         --verdict execute --substantive true 2>&1)" || rc=$?
[[ $rc -ne 0 ]] || fail "(6b2) an undeterminable bump trigger SILENTLY proceeded — it must hand back"
[[ $rc -eq 30 ]] || fail "(6b2) expected the distinct bump exit code 30, got $rc"
grep -q 'HANDBACK\[bump\]' <<<"$zout" || fail "(6b2) no loud HANDBACK[bump] line: $zout"
[[ "$(git -C "$MZ" rev-parse HEAD)" == "$HEAD_BEFORE" ]] \
  || fail "(6b2) main MOVED before the bump handback — the trigger must resolve BEFORE any mutation"
[[ -d "$WTZ" ]] || fail "(6b2) the worktree was retired despite the handback"
pass "(6b2) id:e647: an undeterminable bump trigger hands back loudly (exit 30) with main unmoved"

# (6c) the same close with --no-bump (reviewer judged it refactor-only) integrates cleanly.
MN="$(build_manifest bumpno)"; RN="$(basename "$MN")"
WTN="$(child "$MN" bumpno)"
CN="$(cfg bumpno "$RN")"
rc=0
nout="$(FABLES_CONFIG="$CN" INTEGRATE_GIT_LOCK_PUSH="$PUSH_STUB" \
  "$INT" --repo "$RN" --path "$MN" --worktree "$WTN" --branch relay/bumpno \
         --summary "refactor only" --run r1 --label "executor (sonnet, relay-loop)" \
         --verdict execute --substantive true --no-bump 2>"$ERRLOG")" || rc=$?
[[ $rc -eq 0 ]] || fail "(6c) --no-bump did not resolve the trigger (exit $rc)"
grep -q '^bump=$' <<<"$nout" || fail "(6c) --no-bump still produced a bump"
grep -q '0.4.0' "$MN/pyproject.toml" || fail "(6c) --no-bump changed the manifest version"
pass "(6c) id:e647: --no-bump is an explicit refactor-only resolution — integrates, no bump"

# (6d) a NON-substantive close on a manifest repo resolves without asking (it cannot be a
#      user-observable close), and a durable relay.toml bump_policy also resolves it.
MQ="$(build_manifest bumpsub)"; RQ="$(basename "$MQ")"
WTQ="$(child "$MQ" bumpsub)"
CQ="$(cfg bumpsub "$RQ")"
rc=0
qout="$(FABLES_CONFIG="$CQ" INTEGRATE_GIT_LOCK_PUSH="$PUSH_STUB" \
  "$INT" --repo "$RQ" --path "$MQ" --worktree "$WTQ" --branch relay/bumpsub \
         --summary "no-op review" --run r1 --label "reviewer (claude-opus-5, relay-loop)" \
         --verdict review --substantive false --strong-model claude-opus-5 2>"$ERRLOG")" || rc=$?
[[ $rc -eq 0 ]] || fail "(6d) a non-substantive close must resolve the trigger without asking (exit $rc)"
grep -q '^bump=$' <<<"$qout" || fail "(6d) a non-substantive close produced a bump"
pass "(6d) id:e647: --substantive false resolves the trigger to NO bump, no handback"

MY="$(build_manifest bumppol)"; RY="$(basename "$MY")"
WTY="$(child "$MY" bumppol)"
CY="$(cfg bumppol "$RY")"
printf 'bump_policy = "never"\n' >> "$CY/relay.toml"
rc=0
yout="$(FABLES_CONFIG="$CY" INTEGRATE_GIT_LOCK_PUSH="$PUSH_STUB" \
  "$INT" --repo "$RY" --path "$MY" --worktree "$WTY" --branch relay/bumppol \
         --summary "close" --run r1 --label "executor (sonnet, relay-loop)" \
         --verdict execute --substantive true 2>"$ERRLOG")" || rc=$?
[[ $rc -eq 0 ]] || fail "(6e) a durable bump_policy did not resolve the trigger (exit $rc)"
grep -q '^bump=$' <<<"$yout" || fail "(6e) bump_policy = never still produced a bump"
pass "(6e) id:e647: a durable relay.toml bump_policy resolves the trigger without a handback"

# =====================================================================================
# (7) TILDE EXPANSION — a child reports its worktree as `~/.cache/relay/worktrees/...`.
#     The old LLM integrator got that expanded for free (the prompt spliced it UNQUOTED);
#     the mechanical caller must single-quote every argument, and `'~/x'` does NOT expand.
#     integrate.sh therefore expands a leading `~/` itself. Without this the very first
#     real integration would fail on "not a git checkout" / a missing worktree.
# =====================================================================================
MTI="$(build tilde)"; RTI="$(basename "$MTI")"
WTI="$(child "$MTI" tilde)"
CTI="$(cfg tilde "$RTI")"
FAKE_HOME="$TMP/fakehome"
mkdir -p "$FAKE_HOME"
ln -s "$WTI" "$FAKE_HOME/wt-link"
rc=0
tout="$(HOME="$FAKE_HOME" FABLES_CONFIG="$CTI" INTEGRATE_GIT_LOCK_PUSH="$PUSH_STUB" \
  "$INT" --repo "$RTI" --path "$MTI" --worktree '~/wt-link' --branch relay/tilde \
         --summary "tilde close" --run r1 --label "executor (sonnet, relay-loop)" \
         --verdict execute --substantive true 2>"$ERRLOG")" || rc=$?
[[ $rc -eq 0 ]] || fail "(7) a '~/'-prefixed --worktree was not expanded (exit $rc)"
grep -q '^merged=' <<<"$tout" || fail "(7) no merged= line for the tilde-path worktree"
pass "(7) id:087b: a leading '~/' in --worktree is expanded by integrate.sh, not by the caller's quoting"

echo "ALL PASS: roadmap:087b — the five ported behaviours run mechanically and the bump trigger fails LOUD"

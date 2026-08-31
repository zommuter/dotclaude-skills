#!/usr/bin/env bash
# id:4b64 — ONE fixture per lane spelling, on BOTH sides of the dual-vocab window
# (routed:6629 + routed:5ccd + routed:8858 — three repos, one root cause). No `# roadmap:`
# header: this pins three OBSERVED defects, so its failures always count.
#
# READ side (relay/scripts/unpromoted-scan.sh):
#   [ROUTINE] / [HARD] / [HARD — pool]                       → promote  (executor + pool lanes;
#                                                              bare [HARD] is the recorded 1:1
#                                                              successor of [HARD — pool])
#   [HARD — meeting|hands|decision gate]                     → laned    (old human lanes)
#   [INPUT — meeting|decision|access|author] / [MECHANICAL]  → laned    (new human/compute lanes)
#   untagged                                                  → surface
# `laned` is verdict-NEUTRAL (classify-repo.sh folds only {promote, surface}); that is CORRECT
# for a human lane — re-triaging an already-laned line is the answer-then-re-ask loop — and
# FATAL for the pool lane, which is why bare [HARD] must land in `promote`. Observed live in
# lodelore: id:e545 ([INPUT — author] → surface, inflating the `human` verdict) and
# id:b0c4/id:193f (bare [HARD] → laned → verdict:idle with apex work pending).
#
# EMIT side (relay/scripts/handback-followup.py, the id:3801 auto-gate):
#   every tag it writes must be a CANONICAL capability-keyed tag AND must survive relay's own
#   hooks/pre-commit-lane-vocab.sh ratchet. It used to emit `[HARD — decision gate]`, which the
#   ratchet BLOCKS: the gate commit failed, ROADMAP.md was left STAGED-but-uncommitted, and the
#   dirty residue made every later pool run DEFER the repo while the run reported success
#   (lodelore run relay-20260810-214130-15097).
#
# RESIDUE: a relay writer that stages a ledger edit must COMMIT it or ROLL IT BACK. With a
# pre-commit hook that rejects everything, the follow-up must exit non-zero AND leave
# `git status --porcelain` empty.
#
# CROSS-CHECK (the anti-recurrence mechanism): every lane marker defined in
# relay/references/hard-lanes.md must appear in unpromoted-scan.sh's recognized-tag list, so
# the NEXT vocabulary move fails loudly here instead of silently mis-bucketing a whole lane.
#
# Hermetic: mktemp fixtures, no network, never touches ~/.claude.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN="$ROOT/relay/scripts/unpromoted-scan.sh"
FOLLOWUP="$ROOT/relay/scripts/handback-followup.py"
HOOK="$ROOT/hooks/pre-commit-lane-vocab.sh"
LANES="$ROOT/relay/references/hard-lanes.md"

fail=0
ok()  { echo "  ok  $1"; }
bad() { echo "  FAIL $1"; fail=1; }

for f in "$SCAN" "$FOLLOWUP" "$HOOK" "$LANES"; do
  [[ -e "$f" ]] || { echo "FAIL: missing $f"; exit 1; }
done

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ─────────────────────────────────────────────────────────────────────────────────────────
echo "== READ side: one fixture item per lane spelling → its disposition =="
# ─────────────────────────────────────────────────────────────────────────────────────────
R="$TMP/read"; mkdir -p "$R"
git -C "$R" init -q
git -C "$R" config user.email t@e.st; git -C "$R" config user.name t
printf '# Roadmap\n\n## Items\n' > "$R/ROADMAP.md"   # nothing twinned → every item is un-promoted
cat > "$R/TODO.md" <<'EOF'
# TODO

## Current
- [ ] [ROUTINE] **Executor lane** — plainly promotable <!-- id:1001 -->
- [ ] [HARD] **Pool lane, new spelling** — apex-tier work <!-- id:1002 -->
- [ ] [HARD — pool] **Pool lane, old spelling** — apex-tier work <!-- id:1003 -->
- [ ] [HARD — meeting] **Old meeting lane** — needs a design session <!-- id:1004 -->
- [ ] [HARD — hands] **Old hands lane** — needs a person at a keyboard <!-- id:1005 -->
- [ ] [HARD — decision gate] **Old decision-gate lane** — a human call <!-- id:1006 -->
- [ ] [INPUT — meeting] **New meeting lane** — needs a design session <!-- id:1007 -->
- [ ] [INPUT — decision] **New decision lane** — a human call, no session <!-- id:1008 -->
- [ ] [INPUT — access] **New access lane** — needs a credential <!-- id:1009 -->
- [ ] [INPUT — author] **New author lane** — a human expert authors the prose <!-- id:100a -->
- [ ] [MECHANICAL] **Compute lane** — a daemon runs it <!-- id:100b -->
- [ ] **No lane tag at all** — the genuine triage case <!-- id:100c -->
EOF
git -C "$R" add -A; git -C "$R" commit -qm init

read_out="$("$SCAN" "$R" 2>/dev/null)"; rc=$?
[[ "$rc" -eq 0 ]] || bad "unpromoted-scan exited $rc (report-only must exit 0 with findings)"

expect_disp() { # <id> <disposition> <lane spelling>
  if grep -qP "\t$1\t$2\t" <<<"$read_out"; then
    ok "$3 → $2"
  else
    bad "$3 (id:$1) is not '$2' — got: $(grep -P "\t$1\t" <<<"$read_out" | cut -f3 | tr '\n' ' ')"
  fi
}
expect_disp 1001 promote '[ROUTINE]'
expect_disp 1002 promote '[HARD] (bare, new pool spelling)'
expect_disp 1003 promote '[HARD — pool] (old pool spelling)'
expect_disp 1004 laned   '[HARD — meeting]'
expect_disp 1005 laned   '[HARD — hands]'
expect_disp 1006 laned   '[HARD — decision gate]'
expect_disp 1007 laned   '[INPUT — meeting]'
expect_disp 1008 laned   '[INPUT — decision]'
expect_disp 1009 laned   '[INPUT — access]'
expect_disp 100a laned   '[INPUT — author]'
expect_disp 100b laned   '[MECHANICAL]'
expect_disp 100c surface 'untagged item'

# The two pool spellings must agree with each other — the whole point of the 1:1 rename.
new_d="$(grep -P '\t1002\t' <<<"$read_out" | cut -f3)"
old_d="$(grep -P '\t1003\t' <<<"$read_out" | cut -f3)"
[[ "$new_d" == "$old_d" ]] \
  && ok "the two pool spellings bucket identically ($new_d)" \
  || bad "pool-lane spellings DISAGREE: [HARD]=$new_d vs [HARD — pool]=$old_d (id:4b64)"

# ─────────────────────────────────────────────────────────────────────────────────────────
echo "== CROSS-CHECK: every marker in hard-lanes.md is recognized by the read side =="
# ─────────────────────────────────────────────────────────────────────────────────────────
# The next vocabulary move must fail HERE, loudly, instead of silently mis-bucketing a lane.
# Both the SSOT scrape and the read-side check are delimiter-AGNOSTIC (id:71d6).
# Before this they were pinned to the em dash, so flipping the SSOT to hyphens
# narrowed this cross-check from 11 markers to 3 while it kept reporting PASS: the
# 8 lane-qualified markers -- the entire point of the check -- went unverified. The
# read side is checked in EITHER spelling because its consumers migrate on their own
# seams (unpromoted-scan.sh is S4), so a spelling mismatch here is not yet a defect.
markers_checked=0
while IFS= read -r marker; do
  [[ -n "$marker" ]] || continue
  case "$marker" in
    HARD:*|INPUT:*)
      kind="${marker%%:*}"; lane="${marker#*:}"
      if grep -qE "\"\[${kind}[[:space:]]*[—-][[:space:]]*${lane}\]\"" "$SCAN"; then
        ok "unpromoted-scan recognizes [$kind - $lane] (either delimiter)"
      else
        bad "hard-lanes.md defines [$kind - $lane] but unpromoted-scan.sh's primary_lane() tag list omits it in BOTH delimiter spellings -- items in that lane silently fall through to 'surface' (id:4b64, routed:6629)"
      fi ;;
    *)
      if grep -qF -- "\"$marker\"" "$SCAN"; then
        ok "unpromoted-scan recognizes $marker"
      else
        bad "hard-lanes.md defines $marker but unpromoted-scan.sh's primary_lane() tag list omits it -- items in that lane silently fall through to 'surface' (id:4b64, routed:6629)"
      fi ;;
  esac
  markers_checked=$((markers_checked + 1))
done < <(
  {
    grep -oE '\[(ROUTINE|MECHANICAL|HARD)\]' "$LANES"
    grep -oE '\[HARD[[:space:]]*[—-][[:space:]]*[a-z][a-z ]*[a-z]\]' "$LANES" \
      | sed -E 's/\[HARD[[:space:]]*[—-][[:space:]]*/HARD:/; s/\]$//'
    grep -oE '\[INPUT[[:space:]]*[—-][[:space:]]*[a-z]+\]' "$LANES" \
      | sed -E 's/\[INPUT[[:space:]]*[—-][[:space:]]*/INPUT:/; s/\]$//'
  } | sort -u
)

# FLOOR (id:71d6). The cross-check must actually ITERATE. A delimiter or vocabulary
# change that shrinks the scrape must fail HERE, loudly, rather than pass while
# verifying almost nothing. This file's own comment promised "the next vocabulary
# move must fail HERE, loudly" -- it did not, because nothing asserted the loop ran.
MARKER_FLOOR=11
if [[ "$markers_checked" -ge "$MARKER_FLOOR" ]]; then
  ok "cross-check iterated $markers_checked markers (floor $MARKER_FLOOR)"
else
  bad "cross-check iterated only $markers_checked markers, below the floor of $MARKER_FLOOR -- the hard-lanes.md scrape has SILENTLY NARROWED (delimiter or vocabulary drift), so this check was passing while verifying almost nothing (id:71d6)"
fi

# ─────────────────────────────────────────────────────────────────────────────────────────
echo "== EMIT side: the auto-gate's tags are canonical AND pass the pre-commit ratchet =="
# ─────────────────────────────────────────────────────────────────────────────────────────
E="$TMP/emit"; mkdir -p "$E"
git -C "$E" init -q
git -C "$E" config user.email t@e.st; git -C "$E" config user.name t
cat > "$E/ROADMAP.md" <<'EOF'
# Roadmap

## Items
- [ ] [HARD] a bounded item a strong child sized out <!-- id:aaaa -->
- [ ] [ROUTINE] a second item, decomposed into seams <!-- id:bbbb -->
EOF
git -C "$E" add -A; git -C "$E" commit -qm init

SPLIT='[{"id":"cc01","title":"Seam one","tier":"HARD","acceptance":"a is true","done_check":"tests/run-tests.sh tests/test_a.sh","file":"src/a.py:fn()"},{"id":"cc02","title":"Seam two","tier":"ROUTINE","acceptance":"b is true","done_check":"tests/run-tests.sh tests/test_b.sh","file":"src/b.py:fn()"}]'

HANDBACK_NO_COMMIT=1 python3 "$FOLLOWUP" "$E" --parent-id aaaa --route decision-gate \
  --gate-reason "needs a human call" >/dev/null 2>&1
HANDBACK_NO_COMMIT=1 python3 "$FOLLOWUP" "$E" --parent-id bbbb --route hard-split \
  --gate-reason "too large" --split-json "$SPLIT" >/dev/null 2>&1

emitted="$(cat "$E/ROADMAP.md")"
grep -qF '[INPUT - decision]' <<<"$emitted" \
  && ok "gate emitted as the canonical [INPUT - decision]" \
  || bad "gate did not emit [INPUT - decision] (emit-side vocab, id:4b64):
$emitted"
grep -qF '[HARD — decision gate]' <<<"$emitted" \
  && bad "gate emitted the OLD-vocab [HARD — decision gate] — the pre-commit ratchet blocks it (routed:8858)" \
  || ok "no old-vocab gate tag emitted"
grep -qF '[HARD — strong model]' <<<"$emitted" \
  && bad "a seam emitted the legacy [HARD — strong model] tag, which is in NO lane vocabulary (id:4b64)" \
  || ok "no legacy [HARD — strong model] seam tag emitted"
grep -qF '**[HARD]**' <<<"$emitted" \
  && ok "HARD seam emitted as the canonical bare [HARD]" \
  || bad "HARD seam not emitted as **[HARD]**:
$emitted"

# The emitted ROADMAP must pass relay's OWN pre-commit lane-vocab ratchet.
git -C "$E" add -A
hook_out="$(cd "$E" && LANE_VOCAB_ALL_REPOS=1 bash "$HOOK" 2>&1)"; hook_rc=$?
if [[ "$hook_rc" -eq 0 ]]; then
  ok "hooks/pre-commit-lane-vocab.sh accepts every tag the auto-gate emitted"
else
  bad "the auto-gate's own output is BLOCKED by relay's pre-commit ratchet (routed:8858) — rc=$hook_rc:
$hook_out"
fi

# And the READ side must agree on what the emitted tags mean.
git -C "$E" commit -qm 'emitted gate + seams' >/dev/null 2>&1
cp "$E/ROADMAP.md" "$E/TODO.md"
printf '# Roadmap\n\n## Items\n' > "$E/ROADMAP.md"
git -C "$E" add -A; git -C "$E" commit -qm 'read-back fixture' >/dev/null 2>&1
emit_read="$("$SCAN" "$E" 2>/dev/null)"
grep -qP '\taaaa\tlaned\t' <<<"$emit_read" \
  && ok "the emitted gate reads back as 'laned' (verdict-neutral human lane)" \
  || bad "the emitted gate does not read back as laned: $(grep -P '\taaaa\t' <<<"$emit_read" | cut -f3)"
grep -qP '\tcc01\tpromote\t' <<<"$emit_read" \
  && ok "the emitted [HARD] seam reads back as 'promote' (pickable pool work)" \
  || bad "the emitted [HARD] seam does not read back as promote: $(grep -P '\tcc01\t' <<<"$emit_read" | cut -f3)"
grep -qP '\tcc02\tpromote\t' <<<"$emit_read" \
  && ok "the emitted [ROUTINE] seam reads back as 'promote'" \
  || bad "the emitted [ROUTINE] seam does not read back as promote: $(grep -P '\tcc02\t' <<<"$emit_read" | cut -f3)"

# ...and the DISPATCH-relevant reader agrees: gather-repo-state.sh must count the emitted
# [HARD] seam as an open POOL item (open_hard_pool), or relay-loop's demote-guard (id:9973)
# would surface the repo instead of dispatching the seam the auto-split just created.
GATHER="$ROOT/relay/scripts/gather-repo-state.sh"
P="$TMP/pool"; mkdir -p "$P"
git -C "$P" init -q
git -C "$P" config user.email t@e.st; git -C "$P" config user.name t
cp "$E/TODO.md" "$P/ROADMAP.md"     # the emitted gate + seams, as a ROADMAP
git -C "$P" add -A; git -C "$P" commit -qm init
ohp="$("$GATHER" --repo pool --path "$P" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["open_hard_pool"])' 2>/dev/null)"
[[ "$ohp" == "1" ]] \
  && ok "gather-repo-state counts the emitted [HARD] seam as open pool work (open_hard_pool=1)" \
  || bad "the emitted [HARD] seam is invisible to the pool-dispatch guard: open_hard_pool='$ohp' (want 1)"

# ─────────────────────────────────────────────────────────────────────────────────────────
echo "== RESIDUE: a ledger write that cannot commit is rolled back, never left staged =="
# ─────────────────────────────────────────────────────────────────────────────────────────
D="$TMP/residue"; DHOOKS="$TMP/residue-hooks"; mkdir -p "$D" "$DHOOKS"
git -C "$D" init -q
git -C "$D" config user.email t@e.st; git -C "$D" config user.name t
cat > "$D/ROADMAP.md" <<'EOF'
# Roadmap

## Items
- [ ] [HARD] a bounded item a strong child sized out <!-- id:aaaa -->
EOF
git -C "$D" add -A; git -C "$D" commit -qm init
before_head="$(git -C "$D" rev-parse HEAD)"
before_body="$(cat "$D/ROADMAP.md")"

# A pre-commit hook that rejects EVERYTHING — the general shape of the observed failure
# (relay's own lane-vocab ratchet rejecting the emitted tag), independent of that one hook.
cat > "$DHOOKS/pre-commit" <<'HOOKEOF'
#!/usr/bin/env bash
echo "simulated pre-commit rejection (id:4b64 test)" >&2
exit 1
HOOKEOF
chmod +x "$DHOOKS/pre-commit"
git -C "$D" config core.hooksPath "$DHOOKS"
# tests/run-tests.sh neutralizes core.hooksPath for the whole run via the
# GIT_CONFIG_COUNT/KEY_0/VALUE_0 env override (hermeticity: the developer's own global
# hooks must never fire in a fixture). That override BEATS the repo-local config above, so
# this one case — which needs a hook to fire — re-points the same override at its own
# throwaway hooks dir, for this invocation only.
hooks_env=(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$DHOOKS")

# Stub the push step so nothing leaves the fixture.
STUB="$TMP/push-stub.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB"; chmod +x "$STUB"

env "${hooks_env[@]}" HANDBACK_GIT_LOCK_PUSH="$STUB" python3 "$FOLLOWUP" "$D" --parent-id aaaa \
  --route decision-gate --gate-reason "needs a human call" >"$TMP/residue.out" 2>&1
resid_rc=$?

[[ "$resid_rc" -ne 0 ]] \
  && ok "the follow-up exits non-zero when its ledger write cannot commit (LOUD, not a silent success)" \
  || bad "the follow-up exited 0 although the commit was rejected — the caller sees success and the round reports 'drained' (routed:8858)"

porcelain="$(git -C "$D" status --porcelain)"
[[ -z "$porcelain" ]] \
  && ok "no residue: the working tree AND the index are clean after the rejected commit" \
  || bad "STAGED/dirty residue left behind after a rejected commit — every later pool run defers this repo (id:aa93/id:2147):
$porcelain"

staged="$(git -C "$D" diff --cached --name-only)"
[[ -z "$staged" ]] \
  && ok "nothing is left STAGED (a staged-and-abandoned write is worse than no write)" \
  || bad "ROADMAP.md is still staged: $staged"

[[ "$(cat "$D/ROADMAP.md")" == "$before_body" ]] \
  && ok "the working-tree ledger is back to its pre-write content" \
  || bad "the ledger content was neither committed nor rolled back:
$(diff <(printf '%s\n' "$before_body") "$D/ROADMAP.md")"

[[ "$(git -C "$D" rev-parse HEAD)" == "$before_head" ]] \
  && ok "no commit was created (the rejection stands)" \
  || bad "a commit landed despite the pre-commit rejection"

grep -qiE 'FAILED|refus' "$TMP/residue.out" \
  && ok "the failure is reported in the script's own output" \
  || bad "the failure was not reported loudly; output was:
$(cat "$TMP/residue.out")"

echo
[ "$fail" -eq 0 ] && echo "test_lane_vocab_both_sides_4b64: PASS" || echo "test_lane_vocab_both_sides_4b64: FAIL"
exit "$fail"

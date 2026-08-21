#!/usr/bin/env bash
# roadmap:ecce
# RED SPEC for id:ecce — an INTEGRATE checkpoint must NOT advance the strong-audit
# watermark, because an integrate performs no audit.
#
# THE MECHANISM, verified in-code 2026-08-01:
#   relay/SKILL.md:398        integrate step prescribes  -l "reviewer (<full claude-* id>)"
#   relay/scripts/ckpt-tag.sh the role-prefix carve-out at ~:135 exempts only `executor*`
#                             and `reconcile*`; every other label carrying a claude-* id
#                             syncs last_strong_ckpt + strong_model
#   gather-repo-state.sh ~:296-302  newest_strong matches tag labels `reviewer*|strong-execute*`
# So an INTEGRATE — which verifies contract_met and merges, but performs NO test-integrity
# audit, NO spec-drift check, NO roadmap re-derivation — advances the strong-audit watermark
# exactly as a genuine review would.
#
# OBSERVED CONSEQUENCE (2026-07-31): three integrate checkpoints (relay-ckpt-20260731-1403 /
# -1519 / -1613) were written while integrating five executor units; last_strong_ckpt..HEAD
# was then 0 commits, so a /relay review spawned right after would have audited an EMPTY
# window and reported clean. The true unreviewed window was 42 substantive commits back to
# relay-ckpt-20260730-2018.
#
# WHY IT IS THE ANTI-GAMING HOLE, not a cosmetic label bug: review exists to catch an
# executor that gamed a test, and the integrator is frequently the same session that
# dispatched those executors. Self-integration marking work audited removes the only
# independent check. Note relay-ckpt-20260730-2018 was hand-labelled
# `reviewer (claude-opus-5, manual-integrate)` — someone already disambiguated informally.
#
# Cases 1-5 are FULLY BEHAVIOURAL (real `git init` fixture + scratch FABLES_CONFIG/RELAY_TOML,
# never touching ~/.config/relay, never pushing). Case 6 is a DOC-CONTRACT assertion over
# relay/SKILL.md — labelled as such, not dressed up as behaviour.
#
# TRIANGULATION (id:108e): the integrate case is paired at every step with the DISCRIMINATING
# reviewer case over the same code path, plus the two existing non-strong roles as regression
# controls, plus the second consumer (gather-repo-state's tag scan). A fix that stops syncing
# for everything, or that special-cases one literal string in one consumer, fails here.
#
# RED until ckpt-tag.sh + gather-repo-state.sh + SKILL.md know the integrate role.
# roadmap:ecce unticked => EXPECTED-RED.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CKPT="$ROOT/relay/scripts/ckpt-tag.sh"
GATHER="$ROOT/relay/scripts/gather-repo-state.sh"
SKILLMD="$ROOT/relay/SKILL.md"
for f in "$CKPT" "$GATHER"; do
  [[ -x "$f" ]] || { echo "FAIL: missing/not executable: $f"; exit 1; }
done
[[ -f "$SKILLMD" ]] || { echo "FAIL: relay/SKILL.md not found at $SKILLMD"; exit 1; }

pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/fixturerepo"
CFG="$TMP/cfg"
mkdir -p "$REPO" "$CFG"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@example.invalid
git -C "$REPO" config user.name  Test
printf 'x\n' > "$REPO/f.txt"
git -C "$REPO" add f.txt
git -C "$REPO" -c commit.gpgsign=false commit -qm init
printf '[repos.fixturerepo]\nlast_ckpt = ""\nlast_strong_ckpt = ""\nstrong_model = ""\n' > "$CFG/relay.toml"

toml_of() { head -1 < <(grep -E "^$1" "$CFG/relay.toml") | sed 's/.*= *//; s/"//g' ; }

run_ckpt() { # $1 = label, $2 = summary -> OUT / ERR / RC
  OUT="$(FABLES_CONFIG="$CFG" bash "$CKPT" "$REPO" -m "$2" -l "$1" 2>"$TMP/err")"
  RC=$?
  ERR="$(cat "$TMP/err")"
}

# ── Case 1: an INTEGRATE label must NOT advance the strong watermark ─────────────
before_s="$(toml_of last_strong_ckpt)"; before_m="$(toml_of strong_model)"
run_ckpt "integrate (claude-opus-5)" "case 1: integrate checkpoint"
(( RC == 0 )) || bad "(1) ckpt-tag.sh exited $RC on an integrate label — it must still succeed"
[[ -n "$OUT" ]] || bad "(1) ckpt-tag.sh printed no tag name — an integrate checkpoint is still a real tag"
after_s="$(toml_of last_strong_ckpt)"; after_m="$(toml_of strong_model)"
if [[ "$after_s" == "$before_s" && "$after_m" == "$before_m" ]]; then
  ok "(1) 'integrate (claude-opus-5)' leaves last_strong_ckpt + strong_model UNCHANGED"
else
  bad "(1) 'integrate (claude-opus-5)' ADVANCED the strong watermark (last_strong_ckpt '$before_s'->'$after_s', strong_model '$before_m'->'$after_m') — an integrate performs no audit and must never mark work AUDITED (id:ecce)"
fi

# ── Case 2: it must still sync last_ckpt (it IS a checkpoint, just not a strong one) ──
[[ "$(toml_of last_ckpt)" == "$OUT" ]] \
  && ok "(2) the integrate checkpoint still syncs last_ckpt to its own tag" \
  || bad "(2) last_ckpt was not synced for the integrate checkpoint (got '$(toml_of last_ckpt)', tag '$OUT') — only the STRONG watermark is withheld"

# ── Case 3: it must announce itself as an expected non-strong role, not warn ─────
# `executor*`/`reconcile*` get a `note:`; a genuinely defective label gets `WARNING:`.
# An integrate is expected-and-correct, so it belongs with the notes — otherwise the
# single most common path in the fleet warns every time and real warnings get ignored.
if grep -q 'note:' <<<"$ERR" && grep -qF 'integrate (claude-opus-5)' <<<"$ERR" && ! grep -q 'WARNING:' <<<"$ERR"; then
  ok "(3) the skip is announced as a 'note:' quoting the label, not a WARNING"
else
  bad "(3) an integrate label must emit a 'note:' naming the role/label and NOT a 'WARNING:' (the executor/reconcile precedent). stderr was: $ERR"
fi

# ── Case 4 (DISCRIMINATING): a real REVIEW label must still sync both keys ───────
# Without this, "stop syncing entirely" would pass cases 1-3.
run_ckpt "reviewer (claude-opus-5)" "case 4: genuine review checkpoint"
(( RC == 0 )) || bad "(4) ckpt-tag.sh exited $RC on a reviewer label"
if [[ "$(toml_of last_strong_ckpt)" == "$OUT" && "$(toml_of strong_model)" == "claude-opus-5" ]]; then
  ok "(4) 'reviewer (claude-opus-5)' still syncs last_strong_ckpt + strong_model (unchanged behaviour)"
else
  bad "(4) a genuine reviewer label must STILL sync the watermark; got last_strong_ckpt='$(toml_of last_strong_ckpt)' strong_model='$(toml_of strong_model)' tag='$OUT'"
fi

# ── Case 5 (REGRESSION CONTROLS): the two existing non-strong roles are untouched ──
prev_s="$(toml_of last_strong_ckpt)"
run_ckpt "executor (sonnet, relay-loop)" "case 5a: executor checkpoint"
[[ "$(toml_of last_strong_ckpt)" == "$prev_s" ]] \
  && ok "(5a) control: 'executor (sonnet, relay-loop)' still does not advance the watermark" \
  || bad "(5a) control broken: the executor role advanced last_strong_ckpt"
run_ckpt "reconcile (auto/human)" "case 5b: reconcile checkpoint"
[[ "$(toml_of last_strong_ckpt)" == "$prev_s" ]] \
  && ok "(5b) control: 'reconcile (auto/human)' still does not advance the watermark" \
  || bad "(5b) control broken: the reconcile role advanced last_strong_ckpt"

# ── Case 6: the SECOND consumer — gather-repo-state.sh's newest_strong tag scan ──
# ckpt-tag.sh alone is not enough: gather-repo-state.sh re-derives the anchor from TAG
# LABELS (`reviewer*|strong-execute*`) whenever a tag sorts newer than the toml watermark.
# An integrate tag must not satisfy that scan either, or the stale-watermark guard
# re-introduces the same false "audited" through the back door.
if grep -qE 'reviewer\*\|strong-execute\*' "$GATHER"; then
  bad "(6) gather-repo-state.sh's newest_strong case is still 'reviewer*|strong-execute*' with no integrate carve-out — verify the new role prefix cannot match it, and say so in the source (id:ecce part 2)"
else
  ok "(6) gather-repo-state.sh's newest_strong scan was revisited for the integrate role"
fi
grep -q 'integrate' "$GATHER" \
  && ok "(6b) gather-repo-state.sh names the integrate role explicitly" \
  || bad "(6b) gather-repo-state.sh never mentions the integrate role — the tag-label anchor and ckpt-tag.sh must agree on which prefixes are strong (id:ecce part 2)"

# ── Case 7 (DOC CONTRACT, not behaviour): SKILL.md must stop prescribing 'reviewer (' ──
if grep -nE '^\s*"<summary>" -l "reviewer \(' "$SKILLMD" >/dev/null; then
  bad "(7) relay/SKILL.md still prescribes -l \"reviewer (...)\" at the INTEGRATE step — that is the instruction that creates the hole (id:ecce part 3). Leave 'reviewer (' to a real review pass."
else
  ok "(7) relay/SKILL.md no longer prescribes a reviewer label at the integrate step"
fi
grep -qF 'integrate (' "$SKILLMD" \
  && ok "(7b) relay/SKILL.md names the distinct integrate label" \
  || bad "(7b) relay/SKILL.md does not name a distinct integrate label anywhere (id:ecce part 3)"

echo
echo "  ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]

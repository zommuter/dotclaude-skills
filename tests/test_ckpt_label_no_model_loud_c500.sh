#!/usr/bin/env bash
# roadmap:c500
# RED SPEC for id:c500 — a checkpoint label with no `claude-*` substring must FAIL LOUDLY,
# and relay-reconcile.sh must stop baking such a label in.
#
# The defect, verified in-code 2026-07-31:
#   relay/scripts/relay-reconcile.sh:278  -l "reconcile (auto/human)"   <- fixed literal,
#                                          contains no claude-* string
#   relay/scripts/ckpt-tag.sh:104         model="$(grep -oE 'claude-[a-z0-9.-]+' <<<"$label" …)"
#   relay/scripts/ckpt-tag.sh:105-109     the last_strong_ckpt / strong_model sync is gated on
#                                          a non-empty $model, so on no match it never runs —
#                                          and it never runs SILENTLY: the only WARNING lines
#                                          in that block (:107, :109) fire when a toml-set
#                                          FAILS, never when the sync is never ATTEMPTED.
# So every reconcile-integrate looks completely successful while the watermark it should have
# advanced stays put. Confirmed live: tag relay-ckpt-20260731-1147 on this repo is labelled
# "reconcile (auto/human)" and is already pushed, so it cannot be rewritten.
#
# This is the banked [[ckpt-tag-label-needs-full-model-id]] hazard with the difference that
# makes it worse: there, a HUMAN types the wrong bare form and care can avoid it; here the bad
# label is baked into the script and recurs for everyone.
#
# FULLY BEHAVIOURAL and hermetic: real `git init` fixture + a scratch FABLES_CONFIG. Never
# touches ~/.config/relay, never pushes, never reads the developer's real relay.toml.
#
# TRIANGULATION (id:108e): four cases over the same code path with DIFFERENT labels —
# no-model (must warn), strong model (must sync, must not warn), sonnet (must skip, decision
# stated), plus the reconcile call site — so special-casing one string cannot satisfy it.
#
# RED until ckpt-tag.sh gets its loud path. roadmap:c500 unticked => EXPECTED-RED.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CKPT="$ROOT/relay/scripts/ckpt-tag.sh"
RECON="$ROOT/relay/scripts/relay-reconcile.sh"
[[ -x "$CKPT" ]] || { echo "FAIL: ckpt-tag.sh not found/executable at $CKPT"; exit 1; }

fail() { echo "FAIL: $*"; exit 1; }
pass() { echo "PASS: $*"; }

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

strong_of() { grep -E '^last_strong_ckpt' "$CFG/relay.toml" | head -1 | sed 's/.*= *//; s/"//g'; }

run_ckpt() { # $1 = label, $2 = summary  -> stdout in $OUT, stderr in $ERR, rc in $RC
  set +e
  OUT="$(FABLES_CONFIG="$CFG" bash "$CKPT" "$REPO" -m "$2" -l "$1" 2>"$TMP/err")"
  RC=$?
  set -e
  ERR="$(cat "$TMP/err")"
}

# ── Case 1: a label with NO claude-* substring — the reconcile-integrate case ──────────────
before="$(strong_of)"
run_ckpt "reconcile (auto/human)" "case 1: model-less label"
(( RC == 0 )) || fail "(1) ckpt-tag.sh exited $RC on a model-less label — this must be a WARNING, not a failure (id:c500)"
[[ -n "$OUT" ]] || fail "(1) ckpt-tag.sh printed no tag name on stdout for a model-less label — the tag must still be created (id:c500)"
after="$(strong_of)"

if [[ "$before" == "$after" ]] && ! grep -qiE 'strong|watermark|claude-' <<<"$ERR"; then
  fail "(1) a model-less label 'reconcile (auto/human)' left last_strong_ckpt unchanged ('$before') with NO stderr line naming the label or the skipped strong-watermark sync — this is the SILENT skip id:c500 exists to kill ([[no-swallow-stderr]]). stderr was:
$ERR"
fi
grep -qF 'reconcile (auto/human)' <<<"$ERR" \
  || fail "(1) the stderr warning does not QUOTE the offending label — the operator must be told which label was rejected, not merely that something was skipped (id:c500). stderr was:
$ERR"
pass "(1) a model-less label warns loudly and quotes the label"

# ── Case 2: a genuine strong label still syncs, and does NOT gain new noise ────────────────
run_ckpt "reviewer (claude-opus-5, manual-integrate)" "case 2: strong label"
(( RC == 0 )) || fail "(2) ckpt-tag.sh exited $RC on a strong label"
after2="$(strong_of)"
[[ -n "$after2" && "$after2" == "$OUT" ]] \
  || fail "(2) a strong 'claude-opus-5' label did not advance last_strong_ckpt (got '$after2', tag was '$OUT') — the existing behaviour must be preserved (id:c500)"
if grep -qiE 'no claude-|skipp?ed the strong|watermark sync skipped' <<<"$ERR"; then
  fail "(2) a VALID strong label produced a no-model warning — the loud path must fire only when the label really lacks a claude-* id (id:c500). stderr was:
$ERR"
fi
pass "(2) a strong label still syncs the watermark, with no spurious warning"

# ── Case 3: a sonnet label — the existing :105 exclusion must be preserved ─────────────────
prev="$(strong_of)"
run_ckpt "executor (claude-sonnet-4-5)" "case 3: weak model label"
(( RC == 0 )) || fail "(3) ckpt-tag.sh exited $RC on a sonnet label"
[[ "$(strong_of)" == "$prev" ]] \
  || fail "(3) a sonnet label advanced last_strong_ckpt — the ckpt-tag.sh:105 weak-model exclusion must not be broken by the c500 fix (id:c500)"
pass "(3) the sonnet exclusion is preserved"

# ── Case 4: the reconcile call site no longer bakes in a model-less literal ────────────────
if [[ -f "$RECON" ]]; then
  bad="$(grep -n -- '-l "reconcile (auto/human)"' "$RECON" || true)"
  if [[ -n "$bad" ]]; then
    fail "(4) relay-reconcile.sh still hardcodes the model-less label: $bad — it must record the integrating session's actual model, or explicitly declare itself non-strong in the label text plus an in-source comment (id:c500 part 1). If you cannot settle which, HAND BACK route:decision-gate; do not pick one silently."
  fi
  grep -Eqi 'claude-|non-strong|not a strong checkpoint' "$RECON" \
    || fail "(4) relay-reconcile.sh's checkpoint label carries neither a claude-* model id nor an explicit non-strong declaration — one of the two is required (id:c500 part 1)"
  pass "(4) the reconcile call site no longer bakes in a model-less literal"
else
  fail "(4) relay-reconcile.sh not found at $RECON — cannot verify the call site"
fi

echo "PASS test_ckpt_label_no_model_loud_c500"

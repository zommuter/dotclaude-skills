#!/usr/bin/env bash
# Defect-fix test — NO `# roadmap:` header on purpose: this fixes a same-day regression,
# not an open roadmap item, so its failures ALWAYS count (CLAUDE.md §Testing).
#
# Regression it pins: id:1a34 (2026-07-31) made ckpt-tag.sh loud when a label carries no
# full `claude-*` model id. Correct for a mislabelled strong review — but the POOL's own
# execute-unit label is `executor (sonnet, relay-loop)` (relay-loop.js:2241), a bare tier
# name BY DESIGN, and `reconcile (auto/human)` is deliberately non-strong (id:c500 part 1,
# owner-ratified). Both landed in the WARNING branch, so a scary "a DEFECT if this was a
# strong review" line would have fired on EVERY pool execute integrate — the most common
# path in the fleet. Noise on the happy path is how real warnings get ignored.
#
# Contract: role prefix decides. executor/reconcile -> quiet `note:`; anything else with a
# missing model id -> loud WARNING. Neither ever advances last_strong_ckpt.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CKPT="$ROOT/relay/scripts/ckpt-tag.sh"
fails=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; fails=$((fails + 1)); }

[[ -x "$CKPT" ]] || { echo "FAIL: ckpt-tag.sh not executable at $CKPT"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- hermetic fixture: a throwaway repo + its own relay.toml -------------------
REPO="$TMP/fixt"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@example.invalid
git -C "$REPO" config user.name t
echo seed > "$REPO/seed.txt"
git -C "$REPO" add seed.txt
git -C "$REPO" commit -qm seed

export FABLES_CONFIG="$TMP/cfg"
mkdir -p "$FABLES_CONFIG"
name="$(basename "$REPO")"
printf '[repos.%s]\nlast_ckpt = ""\nlast_strong_ckpt = ""\nstrong_model = ""\n' "$name" \
  > "$FABLES_CONFIG/relay.toml"

# run ckpt-tag with a label, capture stderr, echo it
run_label() {
  "$CKPT" "$REPO" -m "fixture $2" -l "$1" 2>"$TMP/err.$2" >/dev/null
  cat "$TMP/err.$2"
}

watermark() { head -1 < <(grep -oP 'last_strong_ckpt = "\K[^"]*' "$FABLES_CONFIG/relay.toml") ; }

# --- (1) the pool's real execute label must be QUIET ---------------------------
err="$(run_label 'executor (sonnet, relay-loop)' a)"
if grep -q 'WARNING' <<<"$err"; then
  fail "(1) the pool's own label 'executor (sonnet, relay-loop)' still emits a WARNING — this fires on every pool execute integrate: $err"
elif grep -q 'note:' <<<"$err"; then
  pass "(1) 'executor (sonnet, relay-loop)' is a quiet note:, not a WARNING"
else
  fail "(1) expected a note: for the executor label, got: '$err'"
fi

# --- (2) reconcile is deliberately non-strong (id:c500 part 1) -----------------
err="$(run_label 'reconcile (auto/human)' b)"
if grep -q 'WARNING' <<<"$err"; then
  fail "(2) 'reconcile (auto/human)' still WARNs, but c500 part 1 ratified it as deliberately non-strong: $err"
else
  pass "(2) 'reconcile (auto/human)' does not WARN"
fi

# --- (3) a mislabelled STRONG review must STILL be loud (id:1a34 preserved) ----
err="$(run_label 'reviewer (opus)' c)"
if grep -q 'WARNING' <<<"$err"; then
  pass "(3) a bare-tier 'reviewer (opus)' still WARNs loudly — id:1a34's fix is intact"
else
  fail "(3) id:1a34 REGRESSED: 'reviewer (opus)' no longer warns: '$err'"
fi

# --- (4) none of the model-less labels advanced the watermark -----------------
if [[ -z "$(watermark)" ]]; then
  pass "(4) no model-less label advanced last_strong_ckpt"
else
  fail "(4) a model-less label advanced last_strong_ckpt to '$(watermark)'"
fi

# --- (5) a real strong label still syncs --------------------------------------
run_label 'reviewer (claude-opus-5)' d >/dev/null
if [[ -n "$(watermark)" ]]; then
  pass "(5) a full claude-* label still advances last_strong_ckpt"
else
  fail "(5) a full claude-* label failed to advance last_strong_ckpt"
fi

if (( fails )); then
  echo "ckpt-tag role-prefix quieting: $fails failure(s)"
  exit 1
fi
echo "ckpt-tag role-prefix quieting: all checks passed"

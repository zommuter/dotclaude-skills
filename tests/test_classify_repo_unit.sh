#!/usr/bin/env bash
# roadmap:3d61
# Spec for the FULL-UNIT ASSEMBLER (id:3d61) — the a0b6 flip step (b) sub-component that
# lets the mechanical runner emit a complete DISCOVER_SCHEMA `unit` without the LLM shard.
#
# `classify-repo.sh` today emits ONLY classify-verdict's {verdict,reason,evidence,ambiguous}.
# But relay-loop.js's merge/backstop code consumes a FULL unit: path, repo, verdict, reason,
# lastCkpt, income, hasRoutine, openHard, standin, is_finished, top_intensive,
# substantive_unaudited, work_sig, open_hard_pool, strongRecheckPending, intensive
# (DISCOVER_SCHEMA.properties.units, relay-loop.js:351-435). The LLM shard assembled those
# from the gather JSON + relay.toml; the mechanical runner needs a DETERMINISTIC assembler.
#
# Contract under test (authored by /relay handoff 2026-07-01):
#   `classify-repo.sh --emit unit --repo <name> --path <abs>` emits ONE JSON object that is a
#   full DISCOVER_SCHEMA unit. WITHOUT --emit unit the output is UNCHANGED (regression guard —
#   test_classify_repo.sh's {verdict,reason,evidence,ambiguous} contract must still hold).
#   Deterministic derivations (from the old shard prose, relay-loop.js:876-887):
#     - repo,path         : verbatim from args
#     - verdict,reason,intensive : from classify-verdict
#     - lastCkpt          : gather latest_ckpt (tag name, "" if none)
#     - income            : true iff the repo's relay.toml block has `income = true`
#     - standin           : true iff gather latest_ckpt_msg contains the literal "fable-standin"
#     - strongRecheckPending : true iff toml block has non-empty last_strong_ckpt AND
#                              fable_rechecked is false/absent
#     - hasRoutine        : any open [ROUTINE] in ROADMAP (already derived by classify-repo)
#     - openHard,open_hard_pool,is_finished,top_intensive,substantive_unaudited,work_sig :
#                              verbatim from gather (open_hard_pool drives both HARD fields)
#   SIDE-EFFECT-FREE: mutates nothing.
#
# RED until classify-repo.sh grows the --emit unit mode. roadmap:3d61 box unticked ⇒
# EXPECTED-RED (does not fail the suite); ticking it makes any failure real.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CR="$ROOT/relay/scripts/classify-repo.sh"
[[ -x "$CR" ]] || { echo "classify-repo.sh not found (RED): $CR"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export RELAY_WORKTREE_BASE="$tmp/wt"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

field() { python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get(sys.argv[1], "<<MISSING>>"))' "$1"; }
has_key() { python3 -c 'import sys,json; sys.exit(0 if sys.argv[1] in json.load(sys.stdin) else 1)' "$1"; }

# --- fixture: an execute repo with income + a fable-standin strong checkpoint --------------
R="$tmp/repo_a"; mkdir -p "$R"
git -C "$R" init -q; git -C "$R" config user.email t@e; git -C "$R" config user.name t
cat > "$R/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] do the thing <!-- id:1111 -->
EOF
printf '# TODO\n## Current\n' > "$R/TODO.md"
git -C "$R" add -A; git -C "$R" commit -qm init
# a strong checkpoint tag whose message carries fable-standin
git -C "$R" tag -a "relay-ckpt-20260101-0000" -m "review: work (fable-standin)"

# relay.toml with income + a pending strong recheck for this repo
export RELAY_TOML="$tmp/relay.toml"
cat > "$RELAY_TOML" <<EOF
[repos.repo_a]
classification = "own"
income = true
last_strong_ckpt = "relay-ckpt-20260101-0000"
fable_rechecked = false
EOF

# === (1) default mode UNCHANGED — regression guard =========================================
def_out="$("$CR" --repo repo_a --path "$R")"
printf '%s' "$def_out" | has_key evidence  || fail "(1) default mode lost the 'evidence' field (regression vs test_classify_repo.sh)"
printf '%s' "$def_out" | has_key ambiguous || fail "(1) default mode lost the 'ambiguous' field"
printf '%s' "$def_out" | has_key verdict   || fail "(1) default mode lost 'verdict'"
pass "(1) default classify-repo.sh output is unchanged (evidence+ambiguous+verdict present)"

# === (2) --emit unit emits a FULL DISCOVER_SCHEMA unit =====================================
unit="$("$CR" --emit unit --repo repo_a --path "$R")"
for k in repo path verdict reason lastCkpt income hasRoutine openHard standin \
         is_finished top_intensive substantive_unaudited work_sig open_hard_pool \
         strongRecheckPending intensive; do
  printf '%s' "$unit" | has_key "$k" || fail "(2) --emit unit missing required field: $k (unit=$unit)"
done
pass "(2) --emit unit emits every DISCOVER_SCHEMA unit field"

# === (3) field derivations ================================================================
[[ "$(printf '%s' "$unit" | field repo)"    == "repo_a" ]] || fail "(3) repo != repo_a"
[[ "$(printf '%s' "$unit" | field path)"    == "$R" ]]     || fail "(3) path not verbatim"
[[ "$(printf '%s' "$unit" | field verdict)" == "execute" ]] || fail "(3) verdict != execute (open [ROUTINE])"
[[ "$(printf '%s' "$unit" | field lastCkpt)" == "relay-ckpt-20260101-0000" ]] || fail "(3) lastCkpt not the latest tag"
[[ "$(printf '%s' "$unit" | field income)" == "True" ]]    || fail "(3) income not derived true from relay.toml"
[[ "$(printf '%s' "$unit" | field standin)" == "True" ]]   || fail "(3) standin not derived from fable-standin ckpt msg"
[[ "$(printf '%s' "$unit" | field hasRoutine)" == "True" ]] || fail "(3) hasRoutine not true (open [ROUTINE] present)"
[[ "$(printf '%s' "$unit" | field strongRecheckPending)" == "True" ]] || fail "(3) strongRecheckPending not derived (last_strong_ckpt set, fable_rechecked=false)"
# verdict parity with the default classify-verdict output
[[ "$(printf '%s' "$unit" | field verdict)" == "$(printf '%s' "$def_out" | field verdict)" ]] || fail "(3) --emit unit verdict disagrees with default classify-verdict verdict"
pass "(3) unit field derivations correct (income/standin/lastCkpt/strongRecheckPending/hasRoutine + verdict parity)"

# === (4) income defaults false when the toml block lacks it ===============================
R2="$tmp/repo_b"; mkdir -p "$R2"
git -C "$R2" init -q; git -C "$R2" config user.email t@e; git -C "$R2" config user.name t
cat > "$R2/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] thing <!-- id:2222 -->
EOF
printf '# TODO\n## Current\n' > "$R2/TODO.md"
git -C "$R2" add -A; git -C "$R2" commit -qm init
cat >> "$RELAY_TOML" <<EOF

[repos.repo_b]
classification = "own"
EOF
unit_b="$("$CR" --emit unit --repo repo_b --path "$R2")"
[[ "$(printf '%s' "$unit_b" | field income)" == "False" ]]  || fail "(4) income must default false with no income= line"
[[ "$(printf '%s' "$unit_b" | field standin)" == "False" ]] || fail "(4) standin must be false with no fable-standin ckpt"
[[ "$(printf '%s' "$unit_b" | field strongRecheckPending)" == "False" ]] || fail "(4) strongRecheckPending must be false with no last_strong_ckpt"
pass "(4) income/standin/strongRecheckPending default false when their signals are absent"

# === (5) side-effect-free ==================================================================
for r in "$R" "$R2"; do
  [[ -z "$(git -C "$r" status --porcelain)" ]] || fail "(5) --emit unit dirtied $r (must be side-effect-free)"
done
pass "(5) --emit unit is side-effect-free"

echo "ALL PASS: classify-repo.sh --emit unit full-unit assembler (id:3d61)"

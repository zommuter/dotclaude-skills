#!/usr/bin/env bash
# roadmap:32d6 — tools/ctx-budget.sh: advisory token-budget audit of SKILL.md
# files. TSV output <relpath> <est_tokens> <gate> <OK|WARN>, est = bytes/4,
# default gate 2000 tokens, CTX_BUDGET_GATE override, --summary mode,
# always exit 0 (advisory logger).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/tools/ctx-budget.sh"

[[ -x "$SCRIPT" ]] || { echo "tools/ctx-budget.sh missing or not executable"; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bigskill" "$tmp/smallskill"
python3 -c "print('x' * 11999)" > "$tmp/bigskill/SKILL.md"    # 12000 bytes ≈ 3000 tokens
printf 'tiny\n' > "$tmp/smallskill/SKILL.md"                   # 5 bytes ≈ 1 token

out="$("$SCRIPT" "$tmp")" || { echo "ctx-budget.sh exited non-zero (must be advisory)"; exit 1; }

big_line="$(grep -P '^bigskill/SKILL\.md\t' <<<"$out" || true)"
[[ -n "$big_line" ]] || { echo "no TSV line for bigskill/SKILL.md in: $out"; exit 1; }
awk -F'\t' '{exit !($2 == 3000 && $3 == 2000 && $4 == "WARN")}' <<<"$big_line" \
  || { echo "bigskill line wrong (want est=3000 gate=2000 WARN): $big_line"; exit 1; }

small_line="$(grep -P '^smallskill/SKILL\.md\t' <<<"$out" || true)"
[[ -n "$small_line" ]] || { echo "no TSV line for smallskill/SKILL.md"; exit 1; }
awk -F'\t' '{exit !($4 == "OK")}' <<<"$small_line" \
  || { echo "smallskill must be OK: $small_line"; exit 1; }

# Gate override via env
out2="$(CTX_BUDGET_GATE=100000 "$SCRIPT" "$tmp")"
if grep -q 'WARN' <<<"$out2"; then echo "CTX_BUDGET_GATE override ignored"; exit 1; fi

# --summary: only WARN lines plus a total line
out3="$("$SCRIPT" --summary "$tmp")"
grep -q '^bigskill/SKILL\.md' <<<"$out3" || { echo "--summary must keep WARN lines"; exit 1; }
if grep -q '^smallskill/SKILL\.md' <<<"$out3"; then echo "--summary must drop OK lines"; exit 1; fi
grep -qE 'total: [0-9]+ files, [0-9]+ over gate' <<<"$out3" \
  || { echo "--summary must end with 'total: N files, M over gate'"; exit 1; }

# Run against the real repo: must list the meeting skill and stay advisory (exit 0)
out4="$("$SCRIPT" "$ROOT")" || { echo "ctx-budget.sh failed on the real repo"; exit 1; }
grep -q 'meeting/SKILL.md' <<<"$out4" || { echo "real-repo scan must include meeting/SKILL.md"; exit 1; }

echo ok

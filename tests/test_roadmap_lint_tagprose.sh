#!/usr/bin/env bash
# roadmap:297b
# Spec for the case (c)/(d) lint checks (id:297b; meeting 2026-06-30-1523 DP2/DP3).
#
# roadmap-lint.sh must LOUDLY ERROR (nonzero exit + a stderr message) on:
#   (c) id:244b — a tag/prose lane DISAGREEMENT: the item's lane bracket says one thing
#       while its own prose claims another lane ("re-laned to pool, runs under --intensive").
#       The TAG is authority; a tag/prose disagreement must fail loud (never be read as a
#       silent "gated" no-op that an empty run then misreads as "done").
#   (d) c5e9/fd30 — a FREE-TYPED [INTENSIVE — <resource>] on a non-derivable item (a disk
#       `rm`, a /meeting decision item). INTENSIVE must be DERIVABLE, not free-typed.
#
# These are LOUD-FAIL cases, NOT verdicts: assert exit-code + stderr severity, never a
# verdict label (mixing assert-verdict with assert-loud-fail is itself a swallowed-warning
# regression — DP3). Verdict-layer cases (a/b/h) live in tests/test_classify_verdict.sh
# (# roadmap:85df). RED until roadmap-lint.sh grows the case-c and case-d checks.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINT="$ROOT/relay/scripts/roadmap-lint.sh"
[[ -x "$LINT" ]] || { echo "roadmap-lint.sh not found/executable (RED): $LINT"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# --- Case (c) tag/prose disagreement → loud ERROR -----------------------------------------
cat > "$tmp/roadmap_c.md" <<'EOF'
# Roadmap
## Items
- [ ] [HARD — decision gate] benchmark thing — actually re-laned to `[HARD — pool]`, runs under --intensive now <!-- id:1111 -->
EOF
if "$LINT" "$tmp/roadmap_c.md" 2>"$tmp/err_c"; then
  echo "case c: tag/prose lane disagreement must ERROR (nonzero exit)"; exit 1
fi
grep -qiE 'tag.*prose|prose.*lane|disagree|contradic|conflict' "$tmp/err_c" \
  || { echo "case c: stderr must name the tag/prose disagreement (got: $(cat "$tmp/err_c"))"; exit 1; }

# --- Case (d) free-typed INTENSIVE → loud ERROR -------------------------------------------
cat > "$tmp/roadmap_d.md" <<'EOF'
# Roadmap
## Items
- [ ] [HARD — meeting] [INTENSIVE — local-llm] decide whether to rm the stale GGUF cache <!-- id:2222 -->
EOF
if "$LINT" "$tmp/roadmap_d.md" 2>"$tmp/err_d"; then
  echo "case d: free-typed [INTENSIVE] on a non-derivable item must ERROR (nonzero exit)"; exit 1
fi
grep -qiE 'intensive' "$tmp/err_d" \
  || { echo "case d: stderr must name the INTENSIVE violation (got: $(cat "$tmp/err_d"))"; exit 1; }

# --- No false positives: a clean ROADMAP still lints OK -----------------------------------
cat > "$tmp/roadmap_ok.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] a normal executor item <!-- id:3333 -->
- [ ] [HARD — pool] a normal pool item <!-- id:4444 -->
EOF
"$LINT" "$tmp/roadmap_ok.md" 2>"$tmp/err_ok" \
  || { echo "clean roadmap must pass lint (got: $(cat "$tmp/err_ok"))"; exit 1; }

echo "PASS test_roadmap_lint_tagprose"

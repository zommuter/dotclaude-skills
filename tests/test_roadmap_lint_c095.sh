#!/usr/bin/env bash
# roadmap:dfe4
# Spec for the c095 heading-as-item REFINEMENT (id:dfe4; REVIEW_ME decision,
# human 2026-07-11; audit Run 70 finding, filed 5dc3).
#
# WHY: roadmap-lint.sh's c095 "heading-as-item" detector treats ANY `## …[LANE]…`
# heading as a work-item heading that must carry its own `<!-- id:XXXX -->`. That
# false-positives on descriptive relay-handoff SECTION headers whose SOLE child is
# an already-`- [x]` item carrying its OWN `[LANE]` tag + id (e.g. ROADMAP's
# `## [MECHANICAL] lane-anchor hotfix …` / `## [MECHANICAL] recipe
# explicit-success-marker …` / `## [ROUTINE] case-c bare-only lane count …`
# headers, children 0d58/fd37/9078). Demanding an id on such a heading would
# DUPLICATE the child's own id and break single-id-two-views.
#
# THE FIX: a `## …[LANE]…` heading is a heading-*item* (required to carry its own
# id) ONLY when its children (up to the next `## ` heading or EOF) are ALL bare
# status markers (no own class tag + id). If ANY child carries its OWN class tag +
# id, the heading is a descriptive SECTION title, not a work-item, and must NOT be
# flagged for a missing id — the existing genuine c095 shape (heading owns lane+id
# over bare-marker children) is UNCHANGED.
#
# Hermetic: temp ROADMAP fixtures; no network, no ~/.claude.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINT="$ROOT/relay/scripts/roadmap-lint.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$LINT" ]] || fail "roadmap-lint.sh not found/executable at $LINT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- (a) heading whose SOLE child carries its OWN class tag + id -------------
# MUST NOT be flagged for a missing id — the heading is a descriptive SECTION
# title, not a heading-item; the child already satisfies the grammar on its own.
section_title="$tmp/section_title.md"
cat > "$section_title" <<'EOF'
# Roadmap

## Items

## [MECHANICAL] a descriptive section header with a tagged+ided child
- [x] [ROUTINE] the actual work item, already done <!-- id:0d58 -->
EOF
set +e
out_a="$("$LINT" "$section_title" 2>&1)"
rc_a=$?
set -e
[[ "$rc_a" -eq 0 ]] || fail "(a) a '## [LANE]' section header over a tagged+ided child must NOT be flagged as heading-as-item (got nonzero, output: $out_a)"
! grep -qi 'heading-as-item MISSING its id' <<<"$out_a" || fail "(a) section header wrongly reported as heading-as-item MISSING its id:
$out_a"
pass "(a) a '## [LANE]' section header whose sole child owns its own tag+id is NOT flagged"

# --- (b) heading owning lane+id over BARE-marker children --------------------
# Genuine c095 shape is UNCHANGED: still flagged MISSING-id when it has none.
bare_children="$tmp/bare_children.md"
cat > "$bare_children" <<'EOF'
# Roadmap

## Items

## [ROUTINE] A heading-item with NO id token, bare status children
- [ ] Open
- [x] earlier status
EOF
set +e
out_b="$("$LINT" "$bare_children" 2>&1)"
rc_b=$?
set -e
[[ "$rc_b" -ne 0 ]] || fail "(b) a heading owning lane+id over bare-marker children missing its own id must still be flagged"
grep -qi 'heading-as-item MISSING its id' <<<"$out_b" || fail "(b) bare-marker heading-item not reported with the right reason:
$out_b"
pass "(b) a heading owning lane+id over BARE-marker children is still flagged MISSING-id"

# --- (b2) same shape, but the heading DOES carry its own id — clean ----------
bare_ok="$tmp/bare_ok.md"
cat > "$bare_ok" <<'EOF'
# Roadmap

## Items

## [ROUTINE] A heading-item WITH its own id <!-- id:abcd -->
- [ ] Open
- [x] earlier status
EOF
set +e
"$LINT" "$bare_ok" >/dev/null 2>&1
rc_b2=$?
set -e
[[ "$rc_b2" -eq 0 ]] || fail "(b2) a heading-item with bare status children AND its own id must be clean"
pass "(b2) a heading-item with bare status children and its own id is clean"

echo "ALL PASS: c095 heading-as-item refinement (roadmap:dfe4)"

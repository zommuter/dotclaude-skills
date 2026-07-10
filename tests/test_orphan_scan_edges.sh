#!/usr/bin/env bash
# (NO `# roadmap:` header on purpose — this test specs the typed-ledger-edges feature
#  tracked in TODO.md id:46f6, not in ROADMAP.md, so it is not an executor-owned red
#  spec. Its failures therefore ALWAYS count; there is no expected-red exemption.)
#
# orphan-scan.sh --shipped typed-edge closure (meeting note
# docs/meeting-notes/2026-07-10-1430-typed-ledger-edges-umbrella-closure.md, id:46f6):
# an item carrying a `<!-- children:… -->` and/or `<!-- gated-on:… -->` sibling marker
# (form C, before the terminal `<!-- id:XXXX -->`) is decided by the typed predicate and
# bypasses the wait_re gate-word heuristic entirely. Unmarked items keep their exact
# prior behaviour. One fixture ledger per class, plus a regression + a no-regression case.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORPHAN="$ROOT/meeting/orphan-scan.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Canonical own-repo set via a fixture relay.toml (NOT a ~/src glob — the correction
# that zkm-ner lives at ~/src/zkm/plugins/zkm-ner but is a confirmed own repo). Names
# only; paths are irrelevant to name-in-prose matching.
cat > "$tmp/relay.toml" <<'EOF'
[repos.meeting-rpg]
classification = "own"
path = "/nonexistent/meeting-rpg"

[repos.puzzle-pwa]
classification = "own"
path = "/nonexistent/puzzle-pwa"

[repos.zkm-ner]
classification = "own"
path = "/nonexistent/zkm/plugins/zkm-ner"
EOF

# run_shipped <repo-dir> -> sets OUT (stdout) and RC (exit code); never aborts the test.
OUT=""; RC=0
run_shipped() {
  set +e
  OUT="$(HOME="$tmp" RELAY_TOML="$tmp/relay.toml" SRC_DIR="$tmp/src" \
        ORPHAN_SCAN_LIMIT=0 "$ORPHAN" --shipped "$1" 2>&1)"
  RC=$?
  set -e
}

# mk_repo <name>: create a fixture repo dir with an (empty) archive; echoes its path.
mk_repo() {
  local d="$tmp/$1"
  mkdir -p "$d/docs/meeting-notes" "$d/tests"
  : > "$d/TODO.archive.md"
  echo "$d"
}

fail() { echo "FAIL: $1"; echo "--- exit=$RC out ---"; echo "$OUT"; exit 1; }

# --- UMBRELLA-READY: all children resolve and all [x] --------------------------------
d="$(mk_repo umbrella_ready)"
cat > "$d/TODO.md" <<'EOF'
# TODO
- [ ] Ship the umbrella <!-- children:aaaa,bbbb --> <!-- id:cccc -->
- [x] child one <!-- id:aaaa -->
- [x] child two <!-- id:bbbb -->
EOF
run_shipped "$d"
(( RC == 0 )) || fail "UMBRELLA-READY must exit 0"
grep -q 'id:cccc — UMBRELLA-READY' <<<"$OUT" || fail "expected UMBRELLA-READY for cccc"

# --- UMBRELLA-OPEN: all children resolve, >=1 still [ ] -> silent --------------------
d="$(mk_repo umbrella_open)"
cat > "$d/TODO.md" <<'EOF'
# TODO
- [ ] Ship the umbrella <!-- children:aaaa,bbbb --> <!-- id:cccc -->
- [x] child one <!-- id:aaaa -->
- [ ] child two <!-- id:bbbb -->
EOF
run_shipped "$d"
(( RC == 0 )) || fail "UMBRELLA-OPEN must exit 0"
grep -q 'id:cccc' <<<"$OUT" && fail "UMBRELLA-OPEN must be SILENT for cccc" || true

# --- UMBRELLA-OPEN via archived-but-OPEN child (membership != closed) ----------------
# A child in TODO.archive.md that is still `- [ ]` resolves but is NOT closed — must be
# UMBRELLA-OPEN (silent), never UMBRELLA-READY. Guards the correction re TODO.archive:311.
d="$(mk_repo umbrella_archived_open)"
cat > "$d/TODO.md" <<'EOF'
# TODO
- [ ] Ship the umbrella <!-- children:3ef7 --> <!-- id:cccc -->
EOF
cat > "$d/TODO.archive.md" <<'EOF'
# Archive
- [ ] archived parent had an open sub-item <!-- id:3ef7 -->
EOF
run_shipped "$d"
(( RC == 0 )) || fail "archived-open-child umbrella must exit 0"
grep -q 'UMBRELLA-READY' <<<"$OUT" && fail "archived-but-OPEN child must NOT be READY" || true
grep -q 'id:cccc' <<<"$OUT" && fail "archived-open-child umbrella must be SILENT (OPEN)" || true

# --- UMBRELLA-CROSS-REPO: unresolved child, prose names a confirmed own repo ---------
d="$(mk_repo umbrella_cross)"
cat > "$d/TODO.md" <<'EOF'
# TODO
- [ ] Needs meeting-rpg + zkm-ner children <!-- children:5d27,6bef --> <!-- id:fc04 -->
EOF
run_shipped "$d"
(( RC == 0 )) || fail "UMBRELLA-CROSS-REPO must exit 0 (child in another repo is not a defect)"
grep -q 'id:fc04 — UMBRELLA-CROSS-REPO' <<<"$OUT" || fail "expected UMBRELLA-CROSS-REPO for fc04"

# --- UMBRELLA-CROSS-REPO reports EVIDENCE, not an attribution -------------------------
# A line naming TWO different own repos must list BOTH as evidence and must NOT single
# one out as "the" home repo (correction 2026-07-10: nothing on the line maps a child
# token to a repo name, so naming one fabricates a mapping — worse than naming none).
d="$(mk_repo umbrella_cross_multi)"
cat > "$d/TODO.md" <<'EOF'
# TODO
- [ ] The zkm-ner half and the puzzle-pwa half both pending <!-- children:5d27 --> <!-- id:fc04 -->
EOF
run_shipped "$d"
(( RC == 0 )) || fail "multi-repo CROSS-REPO must exit 0"
grep -q 'id:fc04 — UMBRELLA-CROSS-REPO' <<<"$OUT" || fail "multi-repo line must be UMBRELLA-CROSS-REPO"
# Both own-repo names appear in the output...
grep -q 'zkm-ner' <<<"$OUT"   || fail "must list own-repo name 'zkm-ner' as evidence"
grep -q 'puzzle-pwa' <<<"$OUT" || fail "must list own-repo name 'puzzle-pwa' as evidence"
# ...and neither is singled out as "the" home repo. The regression we guard against is
# the old "names own repo 'X'" singular attribution and any "home repo 'X'" phrasing —
# a generic "tracked in another repo" (naming no specific repo) is fine.
cross_line="$(grep 'id:fc04 — UMBRELLA-CROSS-REPO' <<<"$OUT")"
grep -qiE "own repo '|home repo '" <<<"$cross_line" \
  && fail "CROSS-REPO must not attribute the child to a single named repo: $cross_line" || true
grep -q 'evidence' <<<"$cross_line" || fail "CROSS-REPO must label the repo names as evidence"

# --- UMBRELLA-UNRESOLVED: unresolved child, no own-repo evidence -> LOUD, non-zero ---
# Same code path as the id:46f6 self-documentation hazard: a literal marker with
# unresolvable tokens in prose would land here. DO NOT put a real `<!-- children:… -->`
# literal into TODO prose — the detector would flag itself and exit non-zero.
d="$(mk_repo umbrella_unresolved)"
cat > "$d/TODO.md" <<'EOF'
# TODO
- [ ] Umbrella with a dead child token <!-- children:dead --> <!-- id:beef -->
EOF
run_shipped "$d"
(( RC != 0 )) || fail "UMBRELLA-UNRESOLVED must exit NON-ZERO"
grep -q 'id:beef — UMBRELLA-UNRESOLVED' <<<"$OUT" || fail "expected UMBRELLA-UNRESOLVED for beef"
grep -q 'dead' <<<"$OUT" || fail "UMBRELLA-UNRESOLVED must name the dangling token"

# --- GATE-READY: all gated-on tokens resolve and all [x] -> advisory -----------------
d="$(mk_repo gate_ready)"
cat > "$d/TODO.md" <<'EOF'
# TODO
- [ ] Was blocked, now free <!-- gated-on:aaaa,bbbb --> <!-- id:cccc -->
- [x] gate one <!-- id:aaaa -->
- [x] gate two <!-- id:bbbb -->
EOF
run_shipped "$d"
(( RC == 0 )) || fail "GATE-READY must exit 0"
grep -q 'id:cccc — GATE-READY' <<<"$OUT" || fail "expected GATE-READY for cccc"

# --- GATE-BLOCKED: >=1 gate token open -> silent ------------------------------------
d="$(mk_repo gate_blocked)"
cat > "$d/TODO.md" <<'EOF'
# TODO
- [ ] Still blocked <!-- gated-on:aaaa,bbbb --> <!-- id:cccc -->
- [x] gate one <!-- id:aaaa -->
- [ ] gate two <!-- id:bbbb -->
EOF
run_shipped "$d"
(( RC == 0 )) || fail "GATE-BLOCKED must exit 0"
grep -q 'id:cccc' <<<"$OUT" && fail "GATE-BLOCKED must be SILENT for cccc" || true

# --- UNMARKED-GATE: gate vocabulary, no gated-on: marker -> advisory backstop --------
d="$(mk_repo unmarked_gate)"
cat > "$d/TODO.md" <<'EOF'
# TODO
- [ ] Feature X, blocked until the audit lands <!-- id:cccc -->
EOF
run_shipped "$d"
(( RC == 0 )) || fail "UNMARKED-GATE must exit 0"
grep -q 'id:cccc — UNMARKED-GATE' <<<"$OUT" || fail "expected UNMARKED-GATE for cccc"

# --- REGRESSION: gate word lives ONLY inside a quoted child clause, item is marked ---
# Must classify UMBRELLA-READY (children all [x]) and must NOT be suppressed by the
# wait_re heuristic, and must NOT emit UNMARKED-GATE (marked items bypass it entirely).
d="$(mk_repo regression_child_clause)"
cat > "$d/TODO.md" <<'EOF'
# TODO
- [ ] Umbrella; a child was once "gated on foo" <!-- children:aaaa,bbbb --> <!-- id:cccc -->
- [x] child one <!-- id:aaaa -->
- [x] child two <!-- id:bbbb -->
EOF
run_shipped "$d"
(( RC == 0 )) || fail "regression umbrella must exit 0"
grep -q 'id:cccc — UMBRELLA-READY' <<<"$OUT" \
  || fail "child-clause gate word must NOT suppress a marked umbrella (expected UMBRELLA-READY)"
grep -q 'UNMARKED-GATE' <<<"$OUT" && fail "marked umbrella must NOT emit UNMARKED-GATE" || true

# --- NO-REGRESSION: an UNMARKED item with a wait_re gate word stays suppressed -------
# Uses bare "gated"/"awaiting" (wait_re vocabulary), which is NOT UNMARKED-GATE phrase
# vocabulary, so behaviour is byte-for-byte as before: suppressed, no output.
d="$(mk_repo no_regression)"
cat > "$d/TODO.md" <<'EOF'
# TODO
- [ ] Legacy item, gated, awaiting external review <!-- id:cccc -->
EOF
run_shipped "$d"
(( RC == 0 )) || fail "no-regression item must exit 0"
grep -q 'id:cccc' <<<"$OUT" && fail "unmarked wait_re item must stay SILENT (no behaviour change)" || true

echo ok

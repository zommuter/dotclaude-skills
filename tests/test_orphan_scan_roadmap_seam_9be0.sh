#!/usr/bin/env bash
# roadmap:9be0
#
# RED SPEC — authored 2026-07-29 (handoff C3, run relay-20260729-133054-23284), NOT
# implemented. EXPECTED-RED while ROADMAP id:9be0 is unticked. This file is the executable
# specification; do not weaken it to make it pass.
#
# WHY (INBOUND routed:4f48 from loderite) — a dependency on a relay SEAM is untypeable.
# orphan-scan.sh builds its typed-edge resolution map from TODO.md ∪ TODO.archive.md only
# (`meeting/orphan-scan.sh:217`, with `:214` stating the exclusion deliberately). But in a
# relay-managed repo the seams live in ROADMAP.md — so a `gated-on:`/`children:` marker
# naming a seam id reports it DANGLING, and an umbrella over seams exits NON-ZERO. loderite
# hit this on id:3d11 (gate on ca44) and id:5d00 (14 seams, all ROADMAP-only). The item can
# then only be marked gate-prose-only, which throws the typed edge away.
#
# THE FIX SHAPE this spec pins: resolve against TODO.md ∪ TODO.archive.md ∪ ROADMAP.md,
# first-wins in that order. Resolution asks "does this token EXIST?"; --cross-ledger asks
# "do the two views AGREE?" — adding ROADMAP to the former does not weaken the latter, and
# first-wins keeps the TODO (design ledger) view authoritative for closure.
#
# TRIANGULATION (why a hard-coded pass cannot satisfy this file): section (a) needs a
# ROADMAP-only gate to RESOLVE; (b) needs ROADMAP-only children to close an umbrella; (c)
# needs a genuinely absent token to STILL dangle and STILL exit non-zero; (d) needs the
# TODO view to win over a disagreeing ROADMAP twin. "Everything resolves" fails (c);
# "nothing resolves" fails (a)/(b); "ROADMAP wins" fails (d).
#
# Hermetic: mktemp -d fixture repos + a fixture relay.toml. HOME/RELAY_TOML/SRC_DIR are
# redirected; the real registry and the real ~/.claude are never read or written.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORPHAN="$ROOT/meeting/orphan-scan.sh"

fail=0
note() { echo "FAIL: $*" >&2; echo "--- exit=$RC out ---" >&2; echo "$OUT" >&2; fail=1; }
[[ -x "$ORPHAN" ]] || { echo "FAIL: orphan-scan.sh missing at $ORPHAN" >&2; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# Fixture own-repo registry (names only — never a ~/src glob, per the id:4347 correction).
cat > "$tmp/relay.toml" <<'EOF'
[repos.fixture-a]
classification = "own"
path = "/nonexistent/fixture-a"
EOF

OUT=""; RC=0
run_shipped() {
  set +e
  OUT="$(HOME="$tmp" RELAY_TOML="$tmp/relay.toml" SRC_DIR="$tmp/src" \
        ORPHAN_SCAN_LIMIT=0 "$ORPHAN" --shipped "$1" 2>&1)"
  RC=$?
  set -e
}

# mk_repo <name> — fixture repo with an empty archive and an empty ROADMAP; echoes its path.
mk_repo() {
  local d="$tmp/$1"
  mkdir -p "$d/docs/meeting-notes" "$d/tests"
  : > "$d/TODO.archive.md"
  printf '# Roadmap\n' > "$d/ROADMAP.md"
  echo "$d"
}

# ── (a) a gated-on: token living ONLY in ROADMAP.md must RESOLVE ──────────────────────
# Both gates are closed roadmap seams, so the item is unblocked ⇒ GATE-READY.
d="$(mk_repo gate_roadmap_seam)"
cat > "$d/TODO.md" <<'EOF'
# TODO
- [ ] Depends on two relay seams <!-- gated-on:a1a1,b2b2 --> <!-- id:c3c3 -->
EOF
cat > "$d/ROADMAP.md" <<'EOF'
# Roadmap
- [x] [ROUTINE] seam one <!-- id:a1a1 -->
- [x] [ROUTINE] seam two <!-- id:b2b2 -->
EOF
run_shipped "$d"
(( RC == 0 )) || note "(a) a gate on CLOSED ROADMAP-only seams must exit 0 (the seams exist; nothing is dangling)"
grep -q 'id:c3c3 — GATE-READY' <<<"$OUT" \
  || note "(a) a gated-on: token that exists ONLY in ROADMAP.md must RESOLVE and report GATE-READY once closed — today the seam is invisible to the resolver, so a real relay dependency cannot be typed at all (loderite id:3d11)"

# ── (b) a children: umbrella whose seams live ONLY in ROADMAP.md must close ───────────
d="$(mk_repo umbrella_roadmap_seams)"
cat > "$d/TODO.md" <<'EOF'
# TODO
- [ ] Hard-split umbrella over relay seams <!-- children:d4d4,e5e5 --> <!-- id:f6f6 -->
EOF
cat > "$d/ROADMAP.md" <<'EOF'
# Roadmap
- [x] [ROUTINE] seam alpha <!-- id:d4d4 -->
- [x] [ROUTINE] seam beta <!-- id:e5e5 -->
EOF
run_shipped "$d"
(( RC == 0 )) || note "(b) an umbrella over CLOSED ROADMAP-only seams must exit 0 — today every seam reports dangling and the scan exits non-zero (loderite id:5d00, 14 seams)"
grep -q 'id:f6f6 — UMBRELLA-READY' <<<"$OUT" \
  || note "(b) children: tokens resolving only in ROADMAP.md must count for umbrella closure (expected UMBRELLA-READY for f6f6)"
grep -q 'UMBRELLA-UNRESOLVED' <<<"$OUT" \
  && note "(b) ROADMAP-only seams must NOT be reported UMBRELLA-UNRESOLVED — that is the defect"

# ── (b2) a ROADMAP-only child still OPEN keeps the umbrella OPEN (silent), not READY ──
# Membership != closure: the widened map must not turn "resolves" into "done".
d="$(mk_repo umbrella_roadmap_open)"
cat > "$d/TODO.md" <<'EOF'
# TODO
- [ ] Umbrella with one seam still open <!-- children:d4d4,e5e5 --> <!-- id:f6f6 -->
EOF
cat > "$d/ROADMAP.md" <<'EOF'
# Roadmap
- [x] [ROUTINE] seam alpha <!-- id:d4d4 -->
- [ ] [ROUTINE] seam beta <!-- id:e5e5 -->
EOF
run_shipped "$d"
(( RC == 0 )) || note "(b2) an umbrella with an OPEN resolved seam must exit 0"
grep -q 'UMBRELLA-READY' <<<"$OUT" \
  && note "(b2) a resolved-but-OPEN ROADMAP seam must NOT make the umbrella READY — resolution is membership, not closure"

# ── (c) a genuinely absent token STILL dangles, loudly ────────────────────────────────
# The guard must be widened, not dissolved. No own-repo name appears in the prose, so this
# is UMBRELLA-UNRESOLVED (non-zero), exactly as today.
d="$(mk_repo umbrella_truly_dangling)"
cat > "$d/TODO.md" <<'EOF'
# TODO
- [ ] Umbrella with a dead child token <!-- children:9999 --> <!-- id:8888 -->
EOF
run_shipped "$d"
(( RC != 0 )) || note "(c) a token absent from ALL THREE ledgers must still exit NON-ZERO — widening the map must not dissolve the dangling-token guard into 'everything resolves'"
grep -q 'id:8888 — UMBRELLA-UNRESOLVED' <<<"$OUT" \
  || note "(c) a genuinely absent child token must still report UMBRELLA-UNRESOLVED and name the token"

# ── (d) first-wins: the TODO view beats a disagreeing ROADMAP twin ────────────────────
# Same id [ ] in TODO.md and [x] in ROADMAP.md. Closure must follow TODO (the design
# ledger, the conservative reading) ⇒ the umbrella stays OPEN (silent), never READY.
d="$(mk_repo first_wins)"
cat > "$d/TODO.md" <<'EOF'
# TODO
- [ ] Umbrella over a contested child <!-- children:7777 --> <!-- id:6666 -->
- [ ] contested child, still open in the design ledger <!-- id:7777 -->
EOF
cat > "$d/ROADMAP.md" <<'EOF'
# Roadmap
- [x] [ROUTINE] contested child, ticked in the execution queue <!-- id:7777 -->
EOF
run_shipped "$d"
(( RC == 0 )) || note "(d) a contested child resolves in both ledgers, so the scan must exit 0"
grep -q 'id:6666 — UMBRELLA-READY' <<<"$OUT" \
  && note "(d) first-wins is violated: a child OPEN in TODO.md but [x] in ROADMAP.md must NOT close the umbrella — TODO is the design ledger and the conservative view; the disagreement itself is --cross-ledger's job to report"

# ── (e) --cross-ledger must be UNCHANGED by the widening ──────────────────────────────
# The (d) fixture is exactly a cross-ledger disagreement; it must still be reported there.
set +e
OUT="$(HOME="$tmp" RELAY_TOML="$tmp/relay.toml" SRC_DIR="$tmp/src" \
      "$ORPHAN" --cross-ledger "$tmp/first_wins" 2>&1)"
RC=$?
set -e
grep -q 'id:7777' <<<"$OUT" \
  || note "(e) --cross-ledger no longer reports the TODO/ROADMAP checkbox disagreement on id:7777 — the resolution widening must not swallow the drift detector it was carved out of"

[[ $fail -eq 0 ]] || { echo "EXPECTED-RED: id:9be0 not built yet" >&2; exit 1; }
echo "ALL PASS: typed-edge tokens resolve against ROADMAP seams too (id:9be0)"

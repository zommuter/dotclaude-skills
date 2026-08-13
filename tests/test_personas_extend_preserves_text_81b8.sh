#!/usr/bin/env bash
# DEFECT-FIX test for routed:81b8 — deliberately NO `# roadmap:XXXX` header.
# This specs a confirmed data-loss defect, not an open roadmap item, so it must NEVER be
# reported EXPECTED-RED: its failures always count (CLAUDE.md §Testing).
#
# DEFECT (observed live 2026-08-12): meeting/append.sh's id:069b personas-extend branch
# announces "extending instead of appending a duplicate" but its awk is a whole-line
# REPLACE:
#     index($0, needle) > 0 && !done { print newline; done=1; next }
# It prints the caller's line and `next`s past the old one, DISCARDING all prior lens text
# unless the caller happened to retype it — silently, exit 0. Confirmed loss: extending
# Gil/Dex/Hank/Tilda dropped Gil's RELEASE-TAG-PUSH-SEMANTICS, Hank's PROMPT-PROSE-AS-CACHE
# and Dex's KIND-vs-ARITY text (repaired by hand in 624a7f8). meeting/personas.md is
# `merge=union`, so a lost fragment is NOT recoverable by a later merge.
#
# CONTRACT asserted here: an extend is LOSSLESS. The surviving entry carries the union of
# the old and new text; the "don't create a duplicate entry" behaviour (id:069b) is kept.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPEND="$ROOT/meeting/append.sh"
[[ -x "$APPEND" ]] || { echo "FAIL: meeting/append.sh not found/executable at $APPEND"; exit 1; }

fail() { echo "FAIL: $*"; exit 1; }
pass() { echo "PASS: $*"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"   # hermetic: never touch the real ~/.claude
mkdir -p "$HOME" "$TMP/meeting"
cp "$APPEND" "$TMP/meeting/append.sh"

mk_fixture() {
  cat > "$TMP/meeting/personas.md" <<'FIXTURE'
# Ad-hoc persona registry

- 🚚 **Gil** — release engineering. RELEASE-TAG-PUSH-SEMANTICS. Introduced 2026-06-02 (zkm/tags).
- 🧠 **Hank** — caching lens. PROMPT-PROSE-AS-CACHE. Introduced 2026-06-09 (relay/prompt-cache).
FIXTURE
}
FIX="$TMP/meeting/personas.md"

# ── 1. The regression itself: extending must not discard the ORIGINAL lens text ───────────
mk_fixture
set +e
err1="$(bash "$TMP/meeting/append.sh" -t personas \
  -e "- 🚚 **Gil** — release engineering; now also covers changelog derivation. Extended 2026-08-12 (dotclaude-skills/changelog)." 2>&1 >/dev/null)"
rc1=$?
set -e
(( rc1 == 0 )) || fail "(1) append.sh exited $rc1 extending **Gil** — an extension is a normal write (id:069b). stderr: $err1"
grep -qF -- 'RELEASE-TAG-PUSH-SEMANTICS' "$FIX" \
  || fail "(1) SILENT DATA LOSS: extending **Gil** DISCARDED its original lens text (RELEASE-TAG-PUSH-SEMANTICS). The id:069b branch whole-line-REPLACEs the matched entry instead of merging; personas.md is merge=union so the fragment is unrecoverable (routed:81b8). File now:
$(cat "$FIX")"
pass "(1) the original lens text survives an extend"

# 2. …and the NEW text landed too (a fix that simply ignores the extension is not a fix).
grep -qF -- 'changelog derivation' "$FIX" \
  || fail "(2) the extension text never landed — a lossless extend must ADD the new material, not drop it (routed:81b8)"
pass "(2) the new text is present after an extend"

# 3. Still ONE entry — the id:069b behaviour that motivated this branch must be preserved.
n_gil="$(grep -c -- '\*\*Gil\*\*' "$FIX" || true)"
(( n_gil == 1 )) \
  || fail "(3) extending **Gil** produced $n_gil entries — the merge must keep exactly one line per persona name (id:069b)"
pass "(3) exactly one entry per persona name after an extend"

# 4. An UNRELATED persona is untouched — the merge must be line-scoped.
grep -qF -- 'PROMPT-PROSE-AS-CACHE' "$FIX" \
  || fail "(4) extending **Gil** damaged the unrelated **Hank** entry — the merge must be line-scoped (routed:81b8)"
pass "(4) unrelated entries are untouched"

# 5. Superset case (the one that accidentally survived, commit e601f79): when the caller
#    RETYPES the prior text, nothing is lost AND nothing is duplicated inside the line.
mk_fixture
bash "$TMP/meeting/append.sh" -t personas \
  -e "- 🚚 **Gil** — release engineering. RELEASE-TAG-PUSH-SEMANTICS. Introduced 2026-06-02 (zkm/tags). Also changelog derivation. Extended 2026-08-12 (dotclaude-skills/changelog)." >/dev/null 2>&1
gil_line="$(grep -m1 -- '\*\*Gil\*\*' "$FIX")"
n_rep="$(grep -oF -- 'RELEASE-TAG-PUSH-SEMANTICS' <<<"$gil_line" | wc -l)"
(( n_rep == 1 )) \
  || fail "(5) the retyped-superset extend repeated 'RELEASE-TAG-PUSH-SEMANTICS' $n_rep times in one line — when the new entry already CONTAINS the old text the merge must not concatenate it again (routed:81b8). Line: $gil_line"
grep -qF -- 'changelog derivation' <<<"$gil_line" \
  || fail "(5) the retyped-superset extend lost the new material (routed:81b8). Line: $gil_line"
pass "(5) a retyped superset extends without duplicating the retyped text"

# 6. A genuinely NEW name still appends normally (guard against over-correcting).
mk_fixture
bash "$TMP/meeting/append.sh" -t personas \
  -e "- 🦉 **Nyx** — a genuinely new lens. Introduced 2026-08-12 (dotclaude-skills/newlens)." >/dev/null 2>&1
grep -q -- '\*\*Nyx\*\*' "$FIX" \
  || fail "(6) a genuinely new persona **Nyx** was not appended (id:069b)"
grep -qF -- 'RELEASE-TAG-PUSH-SEMANTICS' "$FIX" \
  || fail "(6) appending a NEW persona damaged an existing entry (routed:81b8)"
pass "(6) a genuinely new name still appends, harming nothing"

echo "PASS test_personas_extend_preserves_text_81b8"

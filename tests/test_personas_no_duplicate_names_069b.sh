#!/usr/bin/env bash
# roadmap:069b
# RED SPEC for id:069b — meeting/personas.md must carry no duplicate persona names, and
# append.sh must EXTEND an existing name instead of appending a second entry.
#
# Root cause is STRUCTURAL, not sloppiness: .gitattributes:1 sets
#   meeting/personas.md merge=union
# so when two sessions append the same persona — or one re-registers an existing one with
# enriched wording — union merge keeps BOTH sides forever. Reconciliation has to happen in
# the WRITER, because the merge driver by construction cannot do it.
#
# Verified at authoring (2026-07-31), reproducible commands:
#   grep -oE '\*\*[A-Za-z]+\*\*' meeting/personas.md | wc -l          -> 81
#   ... | sort -u | wc -l                                             -> 54   (27 redundant)
#   ... | sort | uniq -d | wc -l                                      -> 18   duplicated names
#   Sage and Otto appear 3x each; Cal is an exact byte-duplicate;
#   Quinn is at meeting/personas.md:32 and :74.
#   meeting/append.sh:327 routes -t personas to $SKILL_DIR/personas.md and :28 documents that
#   path as "free prose, no validation, no echo" — the sole sanctioned writer validates nothing.
#
# The reassuring half, verified before filing: NO name means two different things. Every
# duplicate is a same-lens re-registration with richer wording. The hazard is LENGTH, and it
# has already bitten — the 2026-07-31 session introduced a "new" persona named Quinn (already
# registered 2026-05-21) after reading only the head of the file, and had to rename to Wren.
#
# Assertions 1-2 run against the REAL registry (the contract's own acceptance command).
# Assertions 3-6 are hermetic: a mktemp copy of meeting/, never the real registry.
#
# TRIANGULATION (id:108e): six assertions over four concerns (no duplicates, provenance
# PRESERVED through dedup, writer extends-not-duplicates, writer still appends genuinely-new
# names) — assertion 2 in particular makes "delete every duplicate line" insufficient, and
# assertion 5 makes "reject every re-registration" insufficient.
#
# RED until the dedup + writer path land. roadmap:069b unticked => EXPECTED-RED.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REG="$ROOT/meeting/personas.md"
APPEND="$ROOT/meeting/append.sh"
CONF="$ROOT/meeting/personas-conformance.sh"
[[ -f "$REG"    ]] || { echo "FAIL: meeting/personas.md not found at $REG"; exit 1; }
[[ -x "$APPEND" ]] || { echo "FAIL: meeting/append.sh not found/executable at $APPEND"; exit 1; }

fail() { echo "FAIL: $*"; exit 1; }
pass() { echo "PASS: $*"; }

names_of() { grep -oE '\*\*[A-Za-z]+\*\*' "$1" | tr -d '*'; }

# 1. The item's own acceptance command: no name appears twice in the real registry.
dups="$(names_of "$REG" | sort | uniq -d | tr '\n' ' ')"
[[ -z "${dups// /}" ]] \
  || fail "(1) meeting/personas.md still has duplicate persona names: $dups — merge=union cannot reconcile a re-registration, so the dedup pass has not run (id:069b)"
pass "(1) no duplicate persona names in the real registry"

# 2. Provenance PRESERVED, not dropped. The dedup must keep the RICHEST entry per name and
#    MERGE the "Introduced/extended <date> (<project>/<slug>)" tails — the enrichment history
#    is the useful part, and losing it is silent data loss disguised as cleanup. This is what
#    makes "just delete the duplicate lines" insufficient.
#
#    Target sets below are the distinct dates PRESENT IN THE FILE TODAY, enumerated by
#    `grep -- '\*\*<name>\*\*' meeting/personas.md | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort -u`.
#    Note Sage has THREE entries but only TWO distinct dates (two share 2026-06-11) — this
#    asserts DATES, not entry counts, because the entry count is what the dedup removes.
check_dates() {
  local who="$1"; shift
  local line d
  line="$(grep -m1 -- "\*\*$who\*\*" "$REG" || true)"
  [[ -n "$line" ]] || fail "(2) persona '$who' vanished from the registry entirely — the dedup must KEEP one entry per name, not drop the name (id:069b)"
  for d in "$@"; do
    grep -qF -- "$d" <<<"$line" \
      || fail "(2) '$who' lost the provenance date $d — its variants' 'Introduced/extended <date> (<project>/<slug>)' tails must be MERGED onto the surviving line, not dropped (id:069b)"
  done
  pass "(2/$who) all $# provenance dates survive the dedup"
}
check_dates Sage  2026-05-08 2026-06-11
check_dates Otto  2026-06-03 2026-06-17 2026-07-30
check_dates Quinn 2026-05-21 2026-06-16
# Cal's :138 entry is a strict SUPERSET of its :76 entry (same text + an extended tail), NOT
# an exact byte-duplicate as TODO.md:184 states — so keep-first would discard the RICHER one.
check_dates Cal   2026-06-17 2026-07-16

# ── Hermetic writer tests: a throwaway copy of meeting/, never the real registry ───────────
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/meeting"
cp "$APPEND" "$TMP/meeting/append.sh"
[[ -f "$CONF" ]] && cp "$CONF" "$TMP/meeting/"
cat > "$TMP/meeting/personas.md" <<'FIXTURE'
# Ad-hoc persona registry

- 🔧 **Quinn** — inference-server internals. Introduced 2026-05-21 (zkm/embed-rebuild-500).
- 🧭 **Wren** — scheduler/queueing lens. Introduced 2026-07-31 (dotclaude-skills/cadence).
FIXTURE
FIX="$TMP/meeting/personas.md"

# 3. Re-registering an EXISTING name EXTENDS the entry — the file must not grow a second Quinn.
set +e
err3="$(bash "$TMP/meeting/append.sh" -t personas \
  -e "- 🔧 **Quinn** — inference-server internals lens; KV-cache, cold-start decomposition. Introduced 2026-06-16 (zelegator/fievel-cold-start)." 2>&1 >/dev/null)"
rc3=$?
set -e
(( rc3 == 0 )) || fail "(3) append.sh exited $rc3 re-registering an existing name — an extension is a normal write, not an error (id:069b). stderr: $err3"
n_quinn="$(grep -c -- '\*\*Quinn\*\*' "$FIX" || true)"
(( n_quinn == 1 )) \
  || fail "(3) re-registering **Quinn** produced $n_quinn entries — append.sh must EXTEND the existing line, not append a duplicate; merge=union can never reconcile the second copy (id:069b)"
pass "(3) re-registering an existing name extends rather than duplicates"

# 4. And it SAYS SO — a silent extension is as bad as a silent duplicate.
grep -qiE 'already registered|extend' <<<"$err3" \
  || fail "(4) append.sh extended **Quinn** silently — it must report 'name already registered, extending instead' on stderr ([[no-swallow-stderr]], id:069b). stderr was: '$err3'"
pass "(4) the extension is announced on stderr"

# 5. A genuinely NEW name still appends normally — the writer must not reject everything.
set +e
bash "$TMP/meeting/append.sh" -t personas \
  -e "- 🦉 **Nyx** — a genuinely new lens. Introduced 2026-08-01 (dotclaude-skills/newlens)." >/dev/null 2>&1
rc5=$?
set -e
(( rc5 == 0 )) || fail "(5) append.sh exited $rc5 on a genuinely NEW persona name — the guard must not reject new registrations (id:069b)"
grep -q -- '\*\*Nyx\*\*' "$FIX" \
  || fail "(5) a genuinely new persona **Nyx** was not appended — the extends-existing path must not swallow new names (id:069b)"
pass "(5) a genuinely new name still appends"

# 6. The conformance check exists at the pinned path and FAILS LOUDLY on a seeded duplicate.
[[ -x "$CONF" ]] \
  || fail "(6) meeting/personas-conformance.sh missing or not executable — the registry needs a check that fails when a name appears twice, or it will silently re-accrete (id:069b)"
printf '%s\n' '- 🔧 **Quinn** — a seeded duplicate.' >> "$FIX"
set +e
conf_err="$(bash "$CONF" "$FIX" 2>&1 >/dev/null)"
conf_rc=$?
set -e
(( conf_rc != 0 )) \
  || fail "(6) personas-conformance.sh exited 0 on a registry with a seeded duplicate **Quinn** — the check must FAIL (id:069b)"
grep -q 'Quinn' <<<"$conf_err" \
  || fail "(6) personas-conformance.sh failed without naming the duplicated persona — it must name the offender, not merely exit non-zero (id:069b). stderr was: '$conf_err'"
pass "(6) the conformance check fails loudly and names the duplicate"

echo "PASS test_personas_no_duplicate_names_069b"

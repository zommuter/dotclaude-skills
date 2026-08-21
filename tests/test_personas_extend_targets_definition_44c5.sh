#!/usr/bin/env bash
# DEFECT-FIX test for id:44c5 — deliberately NO `# roadmap:XXXX` header.
# This specs a confirmed (latent) defect, not an open roadmap item, so it must NEVER be
# reported EXPECTED-RED: its failures always count (CLAUDE.md §Testing).
#
# DEFECT: the personas extend locates its target by SUBSTRING — bash `grep -qF "**Name**"`
# and python `if needle in line` — so it rewrites the FIRST line that MENTIONS the name.
# A persona whose prose legitimately cites another persona's bolded name therefore absorbs
# that other persona's merged text. Latent, not live (the real registry has no
# cross-referencing line today); 89f6e1c reduced the damage from obliteration to a merge
# into the wrong entry, but the wrong line is still chosen.
#
# CONTRACT asserted here: the extend targets the line that DEFINES the persona — the
# registry's own format, `- <emoji> **Name** — lens…`, i.e. a list item whose FIRST bolded
# token is the name — never a line that merely cites it in prose.
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
FIX="$TMP/meeting/personas.md"

# Hank's entry comes FIRST and cites **Gil** in its prose; Gil's own entry is below it.
# The bug picks Hank's line because it is the first line containing the substring.
mk_fixture() {
  cat > "$FIX" <<'FIXTURE'
# Ad-hoc persona registry

- 🧠 **Hank** — caching lens; routinely cross-examines **Gil** on release-tag semantics. PROMPT-PROSE-AS-CACHE. Introduced 2026-06-09 (relay/prompt-cache).
- 🚚 **Gil** — release engineering. RELEASE-TAG-PUSH-SEMANTICS. Introduced 2026-06-02 (zkm/tags).
FIXTURE
}

# ── 1-4. Extending Gil must touch Gil's DEFINITION, not Hank's citation of him ─────────
mk_fixture
hank_before="$(grep -m1 -- '\*\*Hank\*\*' "$FIX")"
set +e
err="$(bash "$TMP/meeting/append.sh" -t personas \
  -e "- 🚚 **Gil** — release engineering; now also changelog derivation. Extended 2026-08-13 (dotclaude-skills/targeting)." 2>&1 >/dev/null)"
rc=$?
set -e
(( rc == 0 )) || fail "(1) append.sh exited $rc extending **Gil**. stderr: $err"

hank_after="$(grep -m1 -- '\*\*Hank\*\*' "$FIX")"
[[ "$hank_after" == "$hank_before" ]] \
  || fail "(1) extending **Gil** REWROTE **Hank**'s entry — the extend targets the first line CONTAINING the name, and Hank's prose cites **Gil** (id:44c5). Hank's line is now:
$hank_after"
pass "(1) a persona whose prose cites another persona's name is left untouched"

gil_line="$(head -1 < <(grep -nP '^\s*-\s+[^*]*\*\*Gil\*\*' "$FIX") )"
grep -qF -- 'changelog derivation' <<<"$gil_line" \
  || fail "(2) **Gil**'s own defining entry never received the extension (id:44c5). Gil's line: $gil_line"
pass "(2) the extension landed on the persona's defining entry"

grep -qF -- 'RELEASE-TAG-PUSH-SEMANTICS' <<<"$gil_line" \
  || fail "(3) **Gil**'s prior lens text was lost from his defining entry (routed:81b8/id:44c5). Gil's line: $gil_line"
pass "(3) the defining entry's prior text survives"

n_gil_def="$(grep -cP '^\s*-\s+[^*]*\*\*Gil\*\*' "$FIX" || true)"
(( n_gil_def == 1 )) \
  || fail "(4) the registry now has $n_gil_def defining entries for **Gil** — the extend must keep exactly one (id:069b)"
pass "(4) exactly one defining entry per persona name"

# ── 5. A name that is only CITED, never DEFINED, is not "already registered" ───────────
# The bash-side pre-check has the same substring blindness: a mere citation makes it take
# the extend branch and rewrite someone else's line, instead of appending a new definition.
cat > "$FIX" <<'FIXTURE'
# Ad-hoc persona registry

- 🧠 **Hank** — caching lens; routinely cross-examines **Gil** on release-tag semantics. PROMPT-PROSE-AS-CACHE. Introduced 2026-06-09 (relay/prompt-cache).
FIXTURE
hank_before="$(grep -m1 -- '\*\*Hank\*\*' "$FIX")"
set +e
err5="$(bash "$TMP/meeting/append.sh" -t personas \
  -e "- 🚚 **Gil** — release engineering. Introduced 2026-08-13 (dotclaude-skills/targeting)." 2>&1 >/dev/null)"
rc5=$?
set -e
(( rc5 == 0 )) || fail "(5) append.sh exited $rc5 registering a persona that was only CITED, never defined. stderr: $err5"
[[ "$(grep -m1 -- '\*\*Hank\*\*' "$FIX")" == "$hank_before" ]] \
  || fail "(5) registering **Gil** — cited in Hank's prose but never DEFINED — rewrote Hank's entry (id:44c5)"
n_gil_def="$(grep -cP '^\s*-\s+[^*]*\*\*Gil\*\*' "$FIX" || true)"
(( n_gil_def == 1 )) \
  || fail "(5) registering a cited-but-undefined persona produced $n_gil_def defining entries for **Gil**; expected exactly 1 new one (id:44c5)"
pass "(5) a cited-but-undefined name registers as a new entry, harming nothing"

# ── 6. Guard against over-correcting: a normal extend still works when the name is only
#       ever present as its own definition.
cat > "$FIX" <<'FIXTURE'
# Ad-hoc persona registry

- 🚚 **Gil** — release engineering. RELEASE-TAG-PUSH-SEMANTICS. Introduced 2026-06-02 (zkm/tags).
FIXTURE
bash "$TMP/meeting/append.sh" -t personas \
  -e "- 🚚 **Gil** — release engineering; now also changelog derivation. Extended 2026-08-13 (dotclaude-skills/targeting)." >/dev/null 2>&1
n_gil_def="$(grep -cP '^\s*-\s+[^*]*\*\*Gil\*\*' "$FIX" || true)"
(( n_gil_def == 1 )) || fail "(6) a plain extend produced $n_gil_def entries for **Gil** (id:069b)"
grep -qF -- 'RELEASE-TAG-PUSH-SEMANTICS' "$FIX" || fail "(6) a plain extend lost the prior text (routed:81b8)"
grep -qF -- 'changelog derivation' "$FIX" || fail "(6) a plain extend lost the new text (routed:81b8)"
pass "(6) a plain extend still merges losslessly into the single entry"

echo "PASS test_personas_extend_targets_definition_44c5"

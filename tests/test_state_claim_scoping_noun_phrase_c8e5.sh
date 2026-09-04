#!/usr/bin/env bash
# DEFECT FIX — no `# roadmap:` header on purpose: id:c8e5 is a defect filed by the
# 2026-08-13 relay review, not a ROADMAP item, so this file's failures always count.
#
# Defect (id:c8e5): roadmap-lint.sh's DECIDED-LEFT-OPEN rule (engine:
# lib-state-claim.sh:state_claim_direction_i) strips a terminal state-word only in the
# ADJACENT form `id:XXXX (is )?<TERMINAL_WORD>`. Prose that scopes the terminal word by a
# NOUN PHRASE instead — "both targets are `[x]` DONE and archived" — reads as a self-claim
# and false-fires. Live case: `3f983f4`'s gate-re-target note on id:d4ca/id:e405, where the
# DONE describes each item's GATE TARGETS, not the item (both items are correctly still open
# and correctly still gated).
#
# The fix must be NARROW: this lint exists to catch genuinely decided-but-left-open items, so
# an over-wide strip that silences a true positive is worse than the false positive it cures.
# Hence BOTH directions are asserted below — the scoped prose must go quiet AND every genuine
# self-claim must still fire, including a line that carries a scoped word and a self-claim at
# the same time.
#
# The lint is run as the PRODUCTION script over fixture ledgers; nothing here greps its source.
#
# LEDGER READS ARE UNION-ANCHORED (id:37ea, 2026-09-04). Case (C) reads the LEDGER +
# `docs/ledger-notes/` UNION, resolving each item's detail pointer off its own line,
# because the guarded prose now lives in those notes; it also REFUSES to pass when the
# guarded lexeme is in neither place. Do not narrow it back to `ROADMAP.md`.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$ROOT/relay/scripts/roadmap-lint.sh"
pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }

[[ -x "$LINT" ]] || { echo "roadmap-lint.sh not found/executable at $LINT"; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# fires <id> <roadmap-file> — does DECIDED-LEFT-OPEN fire for <id> in <roadmap-file>?
# The lint's output is CAPTURED, then matched: piping it straight into `grep -q` under
# `pipefail` makes grep exit at the first match, SIGPIPEs the lint (141), and the pipeline
# reports failure for a MATCH — i.e. every probe would silently read "did not fire".
fires() {
  local out
  out="$("$LINT" "$2" 2>&1 || true)"
  grep -q "DECIDED-LEFT-OPEN: open item id:$1" <<<"$out" && echo yes || echo no
}

# ── (A) the live false positive: a terminal word scoped by a noun phrase ────────────────
# Verbatim lexeme from 3f983f4's gate-re-target prose on id:d4ca / id:e405.
cat > "$TMP/scoped.md" <<'MD'
# Roadmap

## Items

- [ ] [ROUTINE] **`write-relay-status`: haiku → `model:'bash'`** 🚧 GATED (DEP: id:09e4) **GATE RE-TARGETED 2026-08-13**: the `gated-on:33b2`/`gated-on:93ac` markers were STALE — both targets are `[x]` DONE and archived to `ROADMAP.archive.md`, so they read as dangling and the item was blocked by accident. Re-targeted to two REAL gates. This keeps the item blocked — it does NOT make it actionable. **Acceptance**: the hop dispatches with `model: MECH_MODEL`. <!-- id:d4ca -->
- [ ] [HARD] **Convert the two remaining payload-trapped haiku hops** 🚧 GATED (DEP: id:b0b1) **GATE RE-TARGETED 2026-08-13**: its gate targets are DONE and archived, so they resolved as dangling. **Acceptance**: both hops carry `model: MECH_MODEL`. <!-- id:e405 -->
MD
for id in d4ca e405; do
  [[ "$(fires "$id" "$TMP/scoped.md")" == "no" ]] \
    && ok "noun-phrase-scoped terminal word does not fire DECIDED-LEFT-OPEN (id:$id)" \
    || bad "id:$id still false-fires DECIDED-LEFT-OPEN on gate-target prose"
done

# ── (B) genuine DECIDED-LEFT-OPEN items STILL fire (the anti-over-broadening controls) ──
cat > "$TMP/genuine.md" <<'MD'
# Roadmap

## Items

- [ ] [ROUTINE] **A thing** — DEFERRED until the substrate lands. **Acceptance**: n/a. <!-- id:aaa1 -->
- [ ] [ROUTINE] **Another thing** — SUPERSEDED by the new design. **Acceptance**: n/a. <!-- id:aaa2 -->
- [ ] [ROUTINE] **A third thing** — decided 2026-08-01, option B. **Acceptance**: n/a. <!-- id:aaa3 -->
- [ ] [ROUTINE] **A fourth thing** — its gate targets are DONE, and this item is DONE too. **Acceptance**: n/a. <!-- id:aaa4 -->
- [ ] [ROUTINE] **A fifth thing** — CLOSED as won't-fix. **Acceptance**: n/a. <!-- id:aaa5 -->
MD
for id in aaa1 aaa2 aaa3 aaa5; do
  [[ "$(fires "$id" "$TMP/genuine.md")" == "yes" ]] \
    && ok "genuine self-claim still fires DECIDED-LEFT-OPEN (id:$id)" \
    || bad "id:$id no longer fires — the scoping exemption over-broadened and silenced a true positive"
done
# The adversarial one: a scoped word AND a self-claim on the same line. Stripping the scoped
# occurrence must not swallow the self-claim.
[[ "$(fires aaa4 "$TMP/genuine.md")" == "yes" ]] \
  && ok "a line carrying BOTH a scoped word and a self-claim still fires (id:aaa4)" \
  || bad "id:aaa4 no longer fires — the strip swallowed a self-claim sitting beside a scoped word"

# ── (C) the LIVE ledger text, as it actually reads today ───────────────────────────────
# Extracted from the repo's own ledger (read-only) so the fixture above cannot drift away
# from the real prose. Skipped, loudly, if the items are gone/reworded.
#
# RE-ANCHORED 2026-09-04 (id:37ea) to the LEDGER + NOTES UNION. This case used to read
# `ROADMAP.md` alone. `tools/ledger-shrink.py` has since relocated both items' bodies into
# `docs/ledger-notes/<id>.md`, and the scoped "both targets are `[x]` DONE and archived"
# prose that this whole file exists to keep quiet went WITH them -- so the two probes below
# were still passing while the lexeme they guard was no longer in the text being probed.
# A vacuous check (id:0b70), and the exact silent blindness id:9ce0 / id:1447 name.
#
# The reassembly is exact, not clever: `ledger-shrink.py` cuts ONE item line into a slim
# head plus a residue, and writes that residue as the FIRST non-blank line under the note's
# `## From <LEDGER>` heading. Head line + that line IS the pre-shrink item line, which is
# what a per-line lint must be handed. Concatenating the WHOLE note would be wrong in the
# other direction: later sections say DECIDED / RESOLVED about other things and would make
# the lint fire. The pointer path is read OFF the line, never hardcoded, so an unshrunk
# item resolves to its line alone and behaves exactly as before.
#
# AND IT MUST NOT GO QUIET AGAIN: the scoped lexeme has to be found in the assembled text
# or this fails LOUDLY, instead of reporting a pass for prose that was deleted or reworded.
live="$TMP/live.md"
live_n=0
printf '# Roadmap\n\n## Items\n\n' > "$live"
for id in d4ca e405; do
  l="$(head -1 < <(grep -hE "^- \[ \].*<!-- id:$id -->" "$ROOT/ROADMAP.md") )"
  [[ -z "$l" ]] && continue
  d="$(head -1 < <(grep -oP 'detail:\s*`\K[^`]+' <<<"$l") )"
  if [[ -n "$d" && -f "$ROOT/$d" ]]; then
    b="$(awk '/^## From ROADMAP[[:space:]]*$/{f=1;next} f && /^## /{exit} f && NF{print;exit}' \
           "$ROOT/$d")"
    [[ -n "$b" ]] && l="$l $b"
  fi
  printf '%s\n' "$l" >> "$live"
  live_n=$((live_n+1))
done
if (( live_n == 2 )); then
  grep -qF 'DONE and archived' "$live" \
    && ok "the scoped gate-target lexeme is still present in the live ledger+notes union (this case asserts something)" \
    || bad "the scoped 'DONE and archived' lexeme is in NEITHER the ROADMAP.md lines NOR the relocated bodies of id:d4ca/id:e405 -- case (C) would assert nothing; re-point it at prose that still exists"
  for id in d4ca e405; do
    [[ "$(fires "$id" "$live")" == "no" ]] \
      && ok "the LIVE ledger+notes text for id:$id no longer false-fires" \
      || bad "the LIVE ledger+notes text for id:$id still false-fires DECIDED-LEFT-OPEN"
  done
else
  echo "  SKIP: id:d4ca/id:e405 are no longer open lines in ROADMAP.md (case A still covers the lexeme)"
fi

echo
echo "  ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]

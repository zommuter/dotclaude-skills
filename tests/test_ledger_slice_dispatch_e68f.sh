#!/usr/bin/env bash
# roadmap:e68f — the orchestrator must write the ledger SLICE to a tmp file and hand the child
# a PATH, never the whole ROADMAP.md + TODO.md plus a prose instruction to "slice it yourself".
#
# Today the child prompt embeds/points at the whole ledgers and the brief TELLS the child to
# read only its item. A prose instruction the child can get wrong is not a guard
# (`mechanize-first; reserve the LLM for loud failures`). The fix: BEFORE dispatch the
# orchestrator extracts exactly what the unit needs — the dispatched item's line, its
# `gated-on:` / `children:` / `children-of:` edges, and the repo-state header — writes that to
# a tmp file, and passes the PATH. The child then CANNOT over-read, because the bytes are not
# in its prompt at all. This DISSOLVES the prompt-size problem structurally rather than
# guarding it, and makes id:b018's estimate trivially correct: the slice size IS the prompt size.
#
# WHERE THE CODE MUST LIVE, and why this test drives a script rather than relay-loop.js:
# relay-loop.js runs inside the Workflow sandbox, which has no filesystem (id:2ec4) — it cannot
# read a ledger or write a tmp file. So the slicer is HOST-side, the same shape as
# classify-repo.sh / prompt-size-gate.mjs. This test exercises that host-side slicer directly;
# a structural grep then pins that relay-loop.js consumes the PATH. It does NOT prove a live
# pool round short-circuits end-to-end — the same honest limit as
# tests/test_prompt_size_gate_4f9b.sh.
#
# EXPECTED-RED while roadmap:e68f is unticked (the slicer does not exist yet).
# Hermetic: mktemp -d fixture repo, git + python3 only, no network, never touches ~/.claude.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SLICE="$ROOT/relay/scripts/ledger-slice.sh"
JS="$ROOT/relay/scripts/relay-loop.js"

pass=0; fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); }
bad() { echo "BAD: $*"; fail=$((fail+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ── Fixture repo: one dispatchable item with a gate edge, one gate target, and a lot of
#    unrelated ledger the child must NOT receive. ─────────────────────────────────────────
R="$TMP/repo"; mkdir -p "$R"
git -C "$R" init -q
git -C "$R" config user.email t@e
git -C "$R" config user.name t

{
  printf '# ROADMAP\n\n## Items\n\n'
  printf -- '<!-- gated-on:2222 -->\n'
  printf -- '- [ ] [ROUTINE] **THE DISPATCHED ITEM** — build the widget <!-- id:1111 -->\n'
  printf -- '  - **Acceptance**: the widget exists.\n'
  printf -- '  - **Done-check**: tests/test_widget.sh green.\n\n'
  printf -- '- [ ] [INPUT - decision] **THE GATE TARGET** — owner must pick a widget shape <!-- id:2222 -->\n\n'
  n=0
  while [[ $n -lt 800 ]]; do
    printf -- '- [x] [ROUTINE] **UNRELATED CLOSED ITEM %03d** — NEEDLE_UNRELATED, a long done note representative of the real ledger prose that accumulates inline and dominates the byte count. <!-- id:%04x -->\n' "$n" $(( 0x4000 + n ))
    n=$((n+1))
  done
} > "$R/ROADMAP.md"

{
  printf '# TODO\n\n## Current\n\n'
  n=0
  while [[ $n -lt 800 ]]; do
    printf -- '- [ ] NEEDLE_TODO_BULK design-ledger item %03d with enough prose to be representative <!-- id:%04x -->\n' "$n" $(( 0x7000 + n ))
    n=$((n+1))
  done
} > "$R/TODO.md"

git -C "$R" add -A
git -C "$R" commit -qm init

rm_bytes=$(wc -c < "$R/ROADMAP.md")
todo_bytes=$(wc -c < "$R/TODO.md")
total=$(( rm_bytes + todo_bytes ))
ok "fixture built (ROADMAP=$rm_bytes B, TODO=$todo_bytes B, total=$total B)"

# ── (A) The slicer must EXIST as a host-side script. ────────────────────────────────────────
if [[ -x "$SLICE" ]]; then
  ok "relay/scripts/ledger-slice.sh exists and is executable"
else
  bad "id:e68f: relay/scripts/ledger-slice.sh missing/not executable at $SLICE — the orchestrator has nothing to slice with"
fi

OUT="$TMP/slice.md"
rc=0
stdout="$("$SLICE" --repo repo --path "$R" --id 1111 --out "$OUT" 2>"$TMP/err")" || rc=$?

# ── (B) It must produce a FILE (the whole point: the bytes leave the prompt). ────────────────
if [[ "$rc" -eq 0 ]]; then
  ok "ledger-slice.sh exited 0"
else
  bad "id:e68f: ledger-slice.sh exited $rc — $(head -2 "$TMP/err" 2>/dev/null | tr '\n' ' ')"
fi
if [[ -s "$OUT" ]]; then
  ok "slice FILE written at $OUT ($(wc -c < "$OUT") B)"
else
  bad "id:e68f: no slice file produced at $OUT — a child cannot be handed a path that does not exist"
fi
if [[ "$stdout" == *"$OUT"* ]]; then
  ok "stdout carries the slice PATH (what the orchestrator captures and puts in the prompt)"
else
  bad "id:e68f: ledger-slice.sh did not print the slice path on stdout (got: '${stdout:0:80}')"
fi

# ── (C) CONTENT: the dispatched item + its gate edges, and NOT the rest of the ledger. ──────
if [[ -s "$OUT" ]]; then
  grep -q 'id:1111' "$OUT" \
    && ok "slice contains the DISPATCHED item (id:1111)" \
    || bad "id:e68f: slice omits the dispatched item id:1111 — the child cannot do the work"
  grep -q 'THE DISPATCHED ITEM' "$OUT" \
    && ok "slice carries the dispatched item's line text" \
    || bad "id:e68f: slice carries an id but not the item's line text"
  grep -q 'Acceptance' "$OUT" \
    && ok "slice carries the item's Acceptance sub-bullets" \
    || bad "id:e68f: slice drops the item's Acceptance/Done-check sub-bullets"
  grep -q 'gated-on:2222' "$OUT" \
    && ok "slice carries the item's gated-on: EDGE" \
    || bad "id:e68f: slice drops the gated-on: edge — the child cannot see it is gated"
  grep -q 'id:2222' "$OUT" \
    && ok "slice resolves the edge TARGET (id:2222) into the slice" \
    || bad "id:e68f: slice names an edge whose target line is absent — an unresolvable pointer"

  # NEGATIVE CONTROLS — the load-bearing half. A slicer that emits the whole ledger passes
  # every positive check above and fixes nothing.
  grep -q 'NEEDLE_UNRELATED' "$OUT" \
    && bad "id:e68f: slice contains UNRELATED ROADMAP items — it is not a slice, it is the ledger" \
    || ok "slice EXCLUDES unrelated ROADMAP items"
  grep -q 'NEEDLE_TODO_BULK' "$OUT" \
    && bad "id:e68f: slice contains the bulk TODO.md backlog — the second ledger leaked in whole" \
    || ok "slice EXCLUDES the bulk TODO.md backlog"

  sb=$(wc -c < "$OUT")
  if [[ "$sb" -lt $(( total / 10 )) ]]; then
    ok "slice is $sb B — under 10% of the $total B of ledger it replaces"
  else
    bad "id:e68f: slice is $sb B of $total B total ledger — no meaningful reduction, the prompt-size problem is not dissolved"
  fi

  # TRIANGULATION — a SECOND, differently-shaped item (no edges at all) must slice too, so a
  # hard-coded 'emit id:1111 and id:2222' implementation is not a pass.
  OUT2="$TMP/slice2.md"
  if "$SLICE" --repo repo --path "$R" --id 4001 --out "$OUT2" >/dev/null 2>&1 && [[ -s "$OUT2" ]]; then
    grep -q 'id:4001' "$OUT2" \
      && ok "slice works for a DIFFERENT item (id:4001), not just the fixture's first" \
      || bad "id:e68f: slicing id:4001 produced a file that does not contain it"
    grep -q 'id:1111' "$OUT2" \
      && bad "id:e68f: slicing id:4001 leaked the unrelated id:1111 item" \
      || ok "slicing a different item does not leak the first one"
  else
    bad "id:e68f: ledger-slice.sh could not slice a second, edge-free item (id:4001)"
  fi

  # A nonexistent id must fail LOUDLY, never emit an empty-but-successful slice that a child
  # would silently accept as 'no work here' (id:4347 no-silent-swallow).
  if "$SLICE" --repo repo --path "$R" --id ffff --out "$TMP/slice3.md" >/dev/null 2>&1; then
    bad "id:e68f: slicing an id that does not exist exited 0 — a silent empty slice"
  else
    ok "an unknown id fails LOUDLY (non-zero), never a silent empty slice"
  fi
fi

# ── (D) WIRING: relay-loop.js must consume the PATH, not the ledger bytes. ──────────────────
if [[ -f "$JS" ]]; then
  grep -q 'ledger-slice' "$JS" \
    && ok "relay-loop.js references the ledger slicer" \
    || bad "id:e68f: relay-loop.js never references ledger-slice.sh — the slicer would be built but unreferenced ([[relay-builtgreen-but-unreferenced]])"
  grep -q 'slice_path' "$JS" \
    && ok "relay-loop.js carries a slice_path on the unit / in the child prompt" \
    || bad "id:e68f: no slice_path on the unit — the child is still handed the whole ledger"
else
  bad "relay-loop.js missing at $JS"
fi

echo "---"
echo "summary: $pass ok, $fail bad"
[[ "$fail" -eq 0 ]] || exit 1
echo "ALL PASS: orchestrator hands the child a ledger SLICE path (id:e68f)"

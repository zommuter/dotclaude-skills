#!/usr/bin/env bash
# roadmap:0176
#
# RED SPEC for ROADMAP id:0176 -- authored by relay handoff C3, 2026-09-04. It is red
# today by construction; its redness IS the spec while the item is open.
#
# No `# fails-against-*` declaration: this is a roadmap-spec file, and
# `tests/verify-negative-cases.py` skips that bucket while the item is open (id:7c82).
#
# THE DEFECT. `cited_by`'s surviving-text escape asks "does this reader's pattern also
# match something the ledger STILL HOLDS after the move?" -- and if it does, the site is
# dropped, because the reader finds the same thing before and after. `scan()` computes
# that set as `rest = lines[:i+1] + lines[j:]`, i.e. the ledger with THIS block removed
# and every OTHER block still in place.
#
# A BATCH MOVE IS NOT MODELLED. When many blocks move together -- which is the shape of
# every real migration -- a pattern is cancelled by text that is ITSELF about to be
# relocated, and the reader is scored safe against a ledger state that will never exist.
#
# Measured on the live corpus: `tracker/ledger-map.py:493`, the only genuine
# continuation-body consumer on this tree and the consumer whose existence justified the
# `id:1447` untraced amendment, was SILENCED this way -- its
# `\*\*(Acceptance|Tests|Done-check|Context)\*\*` pattern matched `**Context**` in other
# blocks, all of which were also about to move.
#
# THE FIXTURE is that shape reduced to two blocks: one phrase, present in both bodies and
# nowhere else. Each block cancels the other, so both are cleared and the reader is left
# reading nothing once the batch completes.
#
# Either fix satisfies this spec: compute the surviving set against the ledger state AFTER
# the whole batch, or disable the escape for a multi-block run and report the sites.
# Refusing loudly beats clearing on a state that will not exist.
#
# Hermetic: mktemp only, no live ledger, no network.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/tools/ledger-continuations.py"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$TOOL" ]] || fail "setup: ledger-continuations.py not found at $TOOL"

TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/tree/relay/scripts" "$TMP/tree/docs/ledger-notes"

cat > "$TMP/tree/ROADMAP.md" <<'EOF'
# ROADMAP

## Queue

- [ ] **First block of the batch.** <!-- id:cc01 -->
  - detail: PHRASE-SHARED-BOTH lives in this body and in cc02's, nowhere else.
- [ ] **Second block of the batch.** <!-- id:cc02 -->
  - detail: PHRASE-SHARED-BOTH lives in this body and in cc01's, nowhere else.
- [ ] **A block nothing reads.** <!-- id:cc05 -->
  - detail: PHRASE-UNREAD sits in this continuation line and no consumer names it.
EOF

cat > "$TMP/tree/relay/scripts/batch_reader.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
roadmap="$ROOT/ROADMAP.md"
grep -q 'PHRASE-SHARED-BOTH' "$roadmap"
EOF

run() { python3 "$TOOL" --file ROADMAP.md --root "$TMP/tree" --dry-run 2>&1; }
out="$(run)" || fail "setup: the tool exited non-zero on the fixture tree"

# Consumers read from a HERE-STRING, never a pipe (id:81d5 / lint-pipefail-sigpipe.py).

# --- (A) THE DEFECT -------------------------------------------------------------------
# At least one of the mutually-cancelling pair must be reported. Both is also correct;
# neither is the bug.
if ! grep -qE 'id:cc0(1|2)' <<<"$out"; then
  fail "(A) neither cc01 nor cc02 was reported -- each was cleared by text in the OTHER block, which the same batch relocates, so the reader is scored against a ledger state that will not exist"
fi
pass "(A) a pattern cancelled only by text the same batch moves does not silence the site"

# --- (B) THE SITE IS NAMED, NOT MERELY COUNTED ----------------------------------------
grep -q 'batch_reader.sh' <<<"$out" || \
  fail "(B) the report must NAME the consumer -- a refusal that cannot name what motivated it cannot be acted on"
pass "(B) the consuming site is named"

# --- (C) NO BLANKET REFUSAL -----------------------------------------------------------
# Turning the escape off entirely would satisfy (A) by refusing everything, which is a
# different way of being useless. A block no reader names must still move.
if grep -q 'id:cc05' <<<"$out"; then
  fail "(C) a block that NO consumer reads was refused -- the fix must narrow the escape's evaluation state, not abandon the escape"
fi
pass "(C) an unread block still moves"

# --- (D) SINGLE-BLOCK BEHAVIOUR IS UNCHANGED ------------------------------------------
# The note is explicit that the escape is CORRECT for a single move. A ledger holding one
# movable block whose pattern also matches a SURVIVING head line must still be cleared.
mkdir -p "$TMP/one/relay/scripts" "$TMP/one/docs/ledger-notes"
cat > "$TMP/one/ROADMAP.md" <<'EOF'
# ROADMAP

## Queue

- [ ] **Head line carrying PHRASE-SURVIVES itself.** <!-- id:cc06 -->
  - detail: PHRASE-SURVIVES also appears in the head line above, which does not move.
EOF
cat > "$TMP/one/relay/scripts/survivor_reader.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
roadmap="$ROOT/ROADMAP.md"
grep -q 'PHRASE-SURVIVES' "$roadmap"
EOF
out2="$(python3 "$TOOL" --file ROADMAP.md --root "$TMP/one" --dry-run 2>&1)" || \
  fail "setup: the tool exited non-zero on the single-block fixture"
if grep -q 'id:cc06' <<<"$out2"; then
  fail "(D) a single-block move whose pattern still matches surviving ledger text was refused -- the escape must keep working where it is correct"
fi
pass "(D) single-block behaviour is unchanged"

echo "ALL PASS: id:0176 surviving-text escape is evaluated against the post-batch state"

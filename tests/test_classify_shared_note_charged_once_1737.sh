#!/usr/bin/env bash
# No roadmap header -- this is a defect-fix spec for TODO id:1737, authorised by the owner
# 2026-09-10. Failures always count.
#
# THE DEFECT. `relay/scripts/classify-repo.sh` measures `roadmap_bytes` and `todo_bytes`
# independently, each `sorted(set(...))`-deduped WITHIN its own ledger but never ACROSS the
# two. So a detail note pointed at from BOTH ROADMAP.md and TODO.md was charged TWICE, while
# the dispatched child reads that file ONCE. The repos this hit hardest are precisely the ones
# following the MANDATED single-id-two-views convention correctly: the same id lives in both
# views and both carry the same `-- detail:` pointer. Measured on loderite 2026-09-10: 67
# shared notes, 433,645 B, ~108,411 tok of pure over-charge -- gate 417,734 tok against a true
# unique payload of 309,323 tok, with a 300,000 tok Opus budget in between.
#
# WHY OVER-COUNTING IS NOT A HARMLESS SAFETY MARGIN HERE. The gate's own CHARS_PER_TOKEN
# comment says the estimate errs LOW so the gate "fires late, never early". Double-charging
# pushes the opposite way: it fires EARLY and refuses a dispatch that would have fitten. On
# loderite that burned 3 dispatch slots in run relay-20260908-174448-4421 and 2 more in
# relay-20260910-173729-12338, every one a byte-identical refusal with 0 integrates. Under-
# counting kills a child mid-work; over-counting costs a needless handback -- so this fix must
# remove the over-charge WITHOUT ever crossing into under-count. That is what case C pins.
#
# NOTE ON THE SIBLING SPEC. `test_classify_bytes_counts_detail_files_f3d2.sh`'s clause B prose
# named this exact behaviour as tolerated ("over-counting is safe by design (a file pointed at
# from two ledgers is counted in both)"). That sentence described the accounting as it stood,
# and its own rationale ("over-counting merely costs a needless handback") is the argument for
# this change rather than against it. That test still PASSES here -- its fixtures never share a
# note across ledgers -- and its stale sentence is corrected in the same commit as this spec.
#
# CONTRACT ASSERTED HERE:
#   A. REGRESSION GUARD, and first so an empty run cannot vacuously satisfy the rest: a note
#      pointed at from ROADMAP.md ONLY is still charged in full to `roadmap_bytes`.
#   B. THE FIX: a note pointed at from BOTH ledgers is charged EXACTLY ONCE across the pair.
#      Asserted as an exact equality on the SUM, because the sum is what the gate adds up.
#   C. NEVER UNDER-COUNTS: the sum still covers every distinct byte a child loads -- both head
#      lines plus the union of the notes pointed at. An inequality, since over-count is safe.
#   D. ATTRIBUTION ORDER IS FIRST-CHARGE-WINS AND ROADMAP IS FIRST. `countedLedgersFor`
#      (prompt-size-gate.mjs) counts ROADMAP.md and TODO.md for EVERY verdict and adds the
#      review-only pair only for `review`. Attributing a shared note to a review-only field
#      would make a non-review verdict UNDER-count it -- the one direction that kills children
#      -- so this pins that `roadmap_bytes` is the field that keeps the shared note.
#
# SHADOW-BINARY NOTE: the relay-core Lean shadow reimplements `classify-verdict.sh` and
# `gather-repo-state.sh`; neither mentions bytes, so the byte accounting is not on the parity
# surface. The shadow is disabled below via RELAY_CORE_BIN=/nonexistent anyway.
#
# fails-against: the defect and its fix land in the SAME commit as this spec, so there is no
# ancestor tree to check out; the negative case is the mutation below, which deletes the
# cross-ledger skip and so restores the per-ledger double-charge.
# fails-against-mutation: sed -i 's/^        if _abs in _CHARGED_NOTES:$/        if False:/' relay/scripts/classify-repo.sh
# fails-against-assertion: case B: a note pointed at from BOTH ledgers must be charged exactly once across the pair
#
# Hermetic: mktemp -d fixture repo, git + python3 only, no network, never touches ~/.claude.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CR="$ROOT/relay/scripts/classify-repo.sh"

[[ -x "$CR" ]] || { echo "FAIL: classify-repo.sh missing or not executable at $CR"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 not found"; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export RELAY_WORKTREE_BASE="$tmp/wt"
export RELAY_TOML="$tmp/relay.toml"; printf '[repos]\n' > "$RELAY_TOML"
export RELAY_CORE_BIN=/nonexistent   # kill the shadow-parity log write in a hermetic test

mkrepo() {
  local d="$1"
  mkdir -p "$d/docs/ledger-notes"
  git -C "$d" init -q
  git -C "$d" config user.email "test@example.com"
  git -C "$d" config user.name "Test"
}

field() {
  local repo_dir="$1" key="$2" json
  json="$("$CR" --emit unit --repo fixture --path "$repo_dir" 2>/dev/null)" || return 1
  printf '%s' "$json" | python3 -c \
    'import sys,json;print(json.load(sys.stdin).get(sys.argv[1],"<<MISSING>>"))' "$key"
}

size() { wc -c < "$1" | tr -d ' '; }

# A distinctive, easily-sized note body so an off-by-one cannot hide behind small numbers.
mknote() { # <repo> <id> <kbytes>
  local d="$1" id="$2" kb="$3"
  python3 -c 'import sys;open(sys.argv[1],"w").write("x"*(int(sys.argv[2])*1024))' \
    "$d/docs/ledger-notes/$id.md" "$kb"
}

# ── case A -- REGRESSION GUARD, FIRST. A note pointed at from ROADMAP.md alone is charged in
#    full. If the cross-ledger skip were over-eager (e.g. keyed on the id rather than on
#    whether it was already charged), this is what would collapse.
A="$tmp/single"; mkrepo "$A"
mknote "$A" aaaa 40
printf -- '- [ ] [ROUTINE] alpha -- detail: `docs/ledger-notes/aaaa.md` <!-- id:aaaa -->\n' > "$A/ROADMAP.md"
printf -- '- [ ] beta with no pointer <!-- id:bbbb -->\n' > "$A/TODO.md"
a_rm="$(field "$A" roadmap_bytes)"
a_expect=$(( $(size "$A/ROADMAP.md") + $(size "$A/docs/ledger-notes/aaaa.md") ))
if [[ "$a_rm" != "$a_expect" ]]; then
  echo "FAIL: case A: a ROADMAP-only note must still be charged in full to roadmap_bytes (got $a_rm, want $a_expect)"
  exit 1
else
  echo "ok: case A -- ROADMAP-only note charged in full ($a_rm B)"
fi

# ── case B -- THE FIX. One note, pointed at from BOTH ledgers (the single-id-two-views shape).
#    The SUM of the two always-counted fields must charge it exactly once.
B="$tmp/shared"; mkrepo "$B"
mknote "$B" cccc 100
printf -- '- [ ] [ROUTINE] gamma -- detail: `docs/ledger-notes/cccc.md` <!-- id:cccc -->\n' > "$B/ROADMAP.md"
printf -- '- [ ] gamma (TODO view) -- detail: `docs/ledger-notes/cccc.md` <!-- id:cccc -->\n' > "$B/TODO.md"
b_rm="$(field "$B" roadmap_bytes)"; b_td="$(field "$B" todo_bytes)"
note_b="$(size "$B/docs/ledger-notes/cccc.md")"
b_sum=$(( b_rm + b_td ))
b_expect=$(( $(size "$B/ROADMAP.md") + $(size "$B/TODO.md") + note_b ))
if [[ "$b_sum" != "$b_expect" ]]; then
  echo "FAIL: case B: a note pointed at from BOTH ledgers must be charged exactly once across the pair (sum $b_sum, want $b_expect, note is $note_b B)"
  exit 1
else
  echo "ok: case B -- shared note charged once across the pair (sum $b_sum B)"
fi

# ── case C -- NEVER UNDER-COUNTS. The sum must still cover every distinct byte the child
#    loads: both head lines plus the UNION of pointed-at notes (one shared, one per-ledger).
C="$tmp/union"; mkrepo "$C"
mknote "$C" dddd 60; mknote "$C" eeee 30; mknote "$C" ffff 20
printf -- '- [ ] [ROUTINE] d -- detail: `docs/ledger-notes/dddd.md` <!-- id:dddd -->\n- [ ] [ROUTINE] e -- detail: `docs/ledger-notes/eeee.md` <!-- id:eeee -->\n' > "$C/ROADMAP.md"
printf -- '- [ ] d (TODO view) -- detail: `docs/ledger-notes/dddd.md` <!-- id:dddd -->\n- [ ] f -- detail: `docs/ledger-notes/ffff.md` <!-- id:ffff -->\n' > "$C/TODO.md"
c_sum=$(( $(field "$C" roadmap_bytes) + $(field "$C" todo_bytes) ))
c_union=$(( $(size "$C/ROADMAP.md") + $(size "$C/TODO.md") \
          + $(size "$C/docs/ledger-notes/dddd.md") \
          + $(size "$C/docs/ledger-notes/eeee.md") \
          + $(size "$C/docs/ledger-notes/ffff.md") ))
if (( c_sum < c_union )); then
  echo "FAIL: case C: the sum must never UNDER-count the union a child loads (sum $c_sum < union $c_union)"
  exit 1
else
  echo "ok: case C -- sum covers the full union, no under-count ($c_sum >= $c_union)"
fi

# ── case D -- ATTRIBUTION ORDER. ROADMAP.md is measured first, so it is the field that keeps
#    the shared note. Pinned because attributing it to a review-only field would make a
#    non-review verdict under-count -- the direction that kills children mid-work.
d_rm="$(field "$B" roadmap_bytes)"
d_rm_expect=$(( $(size "$B/ROADMAP.md") + note_b ))
d_td_expect=$(size "$B/TODO.md")
if [[ "$d_rm" != "$d_rm_expect" ]]; then
  echo "FAIL: case D: roadmap_bytes must keep the shared note (first-charge-wins); got $d_rm, want $d_rm_expect"
  exit 1
elif [[ "$b_td" != "$d_td_expect" ]]; then
  echo "FAIL: case D: todo_bytes must be the bare file once the shared note is charged to ROADMAP; got $b_td, want $d_td_expect"
  exit 1
else
  echo "ok: case D -- first-charge-wins, ROADMAP keeps the shared note"
fi

echo "PASS: a detail note shared between ledgers is charged exactly once, without under-counting (id:1737)"

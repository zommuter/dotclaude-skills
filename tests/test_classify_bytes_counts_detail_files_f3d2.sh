#!/usr/bin/env bash
# No roadmap header -- this is a defect-fix spec for TODO id:f3d2, filed from the ratified
# format meeting docs/meeting-notes/2026-09-01-2226-ledger-line-shrink-format.md. Failures
# always count.
#
# THE DEFECT. `relay/scripts/classify-repo.sh` emits `roadmap_bytes` / `todo_bytes` /
# `review_me_bytes` (id:4f9b, id:b018, id:7c5f) by stat-ing the ledger FILE. Those figures
# size the assembled child prompt before dispatch and exist specifically to stop a child
# dying with a bare `Prompt is too long`. The ratified line-shrink (D3) moves an item's
# PROSE off its ledger line into `docs/ledger-notes/<id>.md`, leaving a slim head line plus
# a pointer -- prose the dispatched child still loads, and which the stat does not see. So
# post-shrink the gate goes systematically OPTIMISTIC: it under-counts, waves the dispatch
# through, and the child dies of the exact failure the gate was built for. The shrink would
# partly DISARM the guard against its own founding failure (Fable finding 4 of the closing
# pass). The fix teaches the byte accounting to follow the pointers.
#
# CONTRACT ASSERTED HERE:
#   A. Regression, the common case: a ledger with NO pointers reports EXACTLY the file size,
#      byte for byte, as it does today.
#   D. Fail-open survives: an absent ledger still reports 0, and 0 still means "unmeasured".
#   C. A pointer naming a MISSING detail file must not silently count zero. Pinned choice:
#      count a conservative constant AND say so loudly on stderr, rather than refuse the
#      dispatch. WHY THIS AND NOT FAIL-LOUD: a refusal turns one broken pointer into a total
#      dispatch stop for the repo, which is strictly worse than the child death the gate
#      prevents; over-counting merely costs a needless handback. Counting zero is the defect
#      itself, so it is the one option ruled out.
#   B. The shrink case: for a ledger whose item bodies were relocated, the reported figure is
#      NOT LOWER than the bytes a child actually loads (head lines + the detail files they
#      point at). The INEQUALITY is asserted, never an exact number -- over-counting is safe
#      by design (a file pointed at from two ledgers is counted in both), under-counting is
#      the defect.
#
# SHADOW-BINARY NOTE: the relay-core Lean shadow reimplements `classify-verdict.sh` and
# `gather-repo-state.sh`. Neither mentions bytes at all; the byte accounting lives in
# classify-repo.sh alone, so this change does not touch the parity surface. The shadow is
# disabled below anyway via RELAY_CORE_BIN=/nonexistent (the documented kill switch).
#
# fails-against: the defect and its fix land in the SAME commit as this spec, so there is no
# ancestor tree to check out; the negative case is the mutation below, which makes the
# detail-file accounting return zero -- i.e. restores the pre-fix stat-only behaviour.
# fails-against-mutation: sed -i 's/^    return notes_total$/    return 0/' relay/scripts/classify-repo.sh
# fails-against-assertion: case B: todo_bytes must not be LOWER than the bytes a child loads from TODO.md plus its detail files
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

fail=0
report() { echo "FAIL: $1"; fail=1; }

# Build a repo. $1 = dir, then the caller writes the ledgers.
mkrepo() {
  local d="$1"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email "test@example.com"
  git -C "$d" config user.name "Test"
}

commit_repo() {
  git -C "$1" add -A
  git -C "$1" commit -qm fixture
}

# Read one field out of `--emit unit`. stderr goes to $2 so case C can inspect it.
field() {
  local repo_dir="$1" errfile="$2" key="$3" json
  json="$("$CR" --emit unit --repo fixture --path "$repo_dir" 2>"$errfile")" || return 1
  printf '%s' "$json" | python3 -c \
    'import sys,json;print(json.load(sys.stdin).get(sys.argv[1],"<<MISSING>>"))' "$key"
}

size() { wc -c < "$1" | tr -d ' '; }

# ── case A -- REGRESSION GUARD, and FIRST so that a run which emits nothing at all cannot
#    vacuously satisfy the later cases. A ledger with no `docs/ledger-notes/` pointer must
#    report exactly what it reports today: the file size, byte for byte. This is the common
#    case in every repo that has not been shrunk, and it must not move.
A="$tmp/plain"; mkrepo "$A"
printf '# ROADMAP\n\n- [ ] [ROUTINE] do the thing <!-- id:1111 -->\n' > "$A/ROADMAP.md"
{ printf '# TODO\n\n## Current\n\n'
  n=0; while [[ $n -lt 40 ]]; do
    printf -- '- [ ] a backlog item with ordinary inline prose %02d <!-- id:%04x -->\n' "$n" $((0x3000 + n))
    n=$((n + 1))
  done
} > "$A/TODO.md"
printf '# REVIEW_ME\n\n- [ ] look at the thing <!-- id:1111 -->\n' > "$A/REVIEW_ME.md"
commit_repo "$A"

a_err="$tmp/a.err"
a_rm="$(field "$A" "$a_err" roadmap_bytes || echo '<<ERROR>>')"
a_td="$(field "$A" "$a_err" todo_bytes || echo '<<ERROR>>')"
a_rv="$(field "$A" "$a_err" review_me_bytes || echo '<<ERROR>>')"
[[ "$a_rm" == "$(size "$A/ROADMAP.md")" ]] \
  || report "case A: a pointer-free ROADMAP.md must report its exact file size (got '$a_rm', file is $(size "$A/ROADMAP.md") B)"
[[ "$a_td" == "$(size "$A/TODO.md")" ]] \
  || report "case A: a pointer-free TODO.md must report its exact file size (got '$a_td', file is $(size "$A/TODO.md") B)"
[[ "$a_rv" == "$(size "$A/REVIEW_ME.md")" ]] \
  || report "case A: a pointer-free REVIEW_ME.md must report its exact file size (got '$a_rv', file is $(size "$A/REVIEW_ME.md") B)"

# ── case D -- FAIL-OPEN. An absent ledger reports 0, which the gate reads as "unmeasured"
#    and lets through. Blocking on ABSENT data would be strictly worse than the death the
#    gate prevents, so the fix must not turn a missing ledger into a non-zero figure.
D="$tmp/empty"; mkrepo "$D"
printf '# ROADMAP\n\n- [ ] [ROUTINE] lonely <!-- id:2222 -->\n' > "$D/ROADMAP.md"
mkdir -p "$D/docs/ledger-notes"
printf 'stray note nobody points at\n' > "$D/docs/ledger-notes/9999.md"
commit_repo "$D"
d_err="$tmp/d.err"
d_td="$(field "$D" "$d_err" todo_bytes || echo '<<ERROR>>')"
[[ "$d_td" == "0" ]] \
  || report "case D: an ABSENT TODO.md must still report 0 (fail-open), got '$d_td'"

# ── case C -- a pointer whose target does not exist. Counting zero is the defect; the pinned
#    behaviour is a conservative charge plus a LOUD stderr line naming the path (see the
#    header for why this rather than refusing the dispatch).
C="$tmp/dangling"; mkrepo "$C"
printf '# ROADMAP\n\n- [ ] [ROUTINE] slim head line -- detail: docs/ledger-notes/dead.md <!-- id:3333 -->\n' \
  > "$C/ROADMAP.md"
printf '# TODO\n\n## Current\n\n- [ ] nothing relocated here <!-- id:3334 -->\n' > "$C/TODO.md"
mkdir -p "$C/docs/ledger-notes"
commit_repo "$C"
c_err="$tmp/c.err"
c_rm="$(field "$C" "$c_err" roadmap_bytes || echo '<<ERROR>>')"
c_file="$(size "$C/ROADMAP.md")"
if [[ "$c_rm" =~ ^[0-9]+$ ]] && (( c_rm > c_file )); then
  :
else
  report "case C: a pointer to a MISSING detail file must not be counted as zero bytes (roadmap_bytes '$c_rm' vs file $c_file B)"
fi
grep -q 'docs/ledger-notes/dead.md' "$c_err" \
  || report "case C: a MISSING detail file must be announced LOUDLY on stderr, naming the path"

# ── case B -- THE DEFECT. Both ledgers are shrunk: item bodies live in
#    docs/ledger-notes/<id>.md and the head line carries only a pointer. The figure the gate
#    reports must be NOT LOWER than what a child actually loads, which is the ledger file
#    plus every detail file it points at. Asserted as an inequality: over-counting is safe.
B="$tmp/shrunk"; mkrepo "$B"
mkdir -p "$B/docs/ledger-notes"
{ printf '# ROADMAP\n\n'
  for id in aa01 aa02 aa03; do
    printf -- '- [ ] [ROUTINE] slim head line for %s -- detail: [notes](docs/ledger-notes/%s.md) <!-- id:%s -->\n' "$id" "$id" "$id"
  done
} > "$B/ROADMAP.md"
{ printf '# TODO\n\n## Current\n\n'
  for id in bb01 bb02; do
    printf -- '- [ ] slim head line for %s -- detail: `docs/ledger-notes/%s.md` <!-- id:%s -->\n' "$id" "$id" "$id"
  done
} > "$B/TODO.md"
# Bodies large enough that dropping them is unmistakable in the byte figure.
for id in aa01 aa02 aa03 bb01 bb02; do
  { printf '# %s\n\n## From ROADMAP\n\n' "$id"
    n=0; while [[ $n -lt 120 ]]; do
      printf 'relocated acceptance-criteria prose for %s, line %03d, which a dispatched child must load in full.\n' "$id" "$n"
      n=$((n + 1))
    done
  } > "$B/docs/ledger-notes/$id.md"
done
commit_repo "$B"

b_err="$tmp/b.err"
b_rm="$(field "$B" "$b_err" roadmap_bytes || echo '<<ERROR>>')"
b_td="$(field "$B" "$b_err" todo_bytes || echo '<<ERROR>>')"

rm_loads=$(( $(size "$B/ROADMAP.md") \
  + $(size "$B/docs/ledger-notes/aa01.md") \
  + $(size "$B/docs/ledger-notes/aa02.md") \
  + $(size "$B/docs/ledger-notes/aa03.md") ))
td_loads=$(( $(size "$B/TODO.md") \
  + $(size "$B/docs/ledger-notes/bb01.md") \
  + $(size "$B/docs/ledger-notes/bb02.md") ))

if [[ "$b_rm" =~ ^[0-9]+$ ]] && (( b_rm >= rm_loads )); then
  :
else
  report "case B: roadmap_bytes must not be LOWER than the bytes a child loads from ROADMAP.md plus its detail files (got '$b_rm', child loads $rm_loads B)"
fi
if [[ "$b_td" =~ ^[0-9]+$ ]] && (( b_td >= td_loads )); then
  :
else
  report "case B: todo_bytes must not be LOWER than the bytes a child loads from TODO.md plus its detail files (got '$b_td', child loads $td_loads B)"
fi

if (( fail )); then
  echo "--- fixture figures ---"
  echo "A: roadmap=$a_rm todo=$a_td review_me=$a_rv"
  echo "C: roadmap=$c_rm (file $c_file)"
  echo "B: roadmap=$b_rm (child loads $rm_loads)  todo=$b_td (child loads $td_loads)"
  echo "--- case C stderr ---"
  cat "$c_err" || true
  exit 1
fi
echo "PASS: the prompt-size byte accounting follows ledger-note pointers and never under-counts (id:f3d2)"

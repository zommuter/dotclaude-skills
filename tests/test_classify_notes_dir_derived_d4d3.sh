#!/usr/bin/env bash
# No roadmap header -- this is a defect-fix spec for TODO id:d4d3. Failures always count.
#
# THE DEFECT. `relay/scripts/classify-repo.sh` HARDCODED the ledger-notes directory, in both a
# constant and the pointer regex literal:
#
#     LEDGER_NOTES_DIR = "docs/ledger-notes"
#     LEDGER_NOTE_POINTER_RE = re.compile(r"docs/ledger-notes/([0-9A-Za-z][0-9A-Za-z._-]*)\.md")
#
# `docs/ledger-notes` is THIS repo's spelling and no other's. That accounting is where id:f3d2
# landed: it folds note bytes into `roadmap_bytes`/`todo_bytes` so relocating an item's prose
# behind a pointer cannot buy a false green on the pre-dispatch prompt-size gate. On a repo
# whose notes live elsewhere -- loderite uses `docs/roadmap-notes`, with 188 notes already
# there -- the regex matched nothing and the accounting silently added 0 B, reopening exactly
# the failure f3d2 was ratified to close, for 45 of the 46 repos id:03a3 will migrate. The gate
# goes optimistic precisely where a migration has just moved prose behind pointers.
#
# THE FIX. Derive the directory from the item's OWN POINTER, as `meeting/orphan-scan.sh` and
# `relay/scripts/todo-conformance.sh` (SHAPE_POINTER_RE) already do, rather than from a
# constant. What the format actually fixes is the trailing `<4-hex>.md` basename, so that is
# what anchors the match; the directory is whatever precedes it.
#
# CONTRACT ASSERTED HERE, in run order:
#   A. REGRESSION, first so a run that emits nothing cannot vacuously satisfy the later cases:
#      a repo using `docs/ledger-notes` still counts EXACTLY what it counted before -- file
#      size plus every note it points at.
#   B. FAIL-OPEN END TO END, in a repo whose notes live elsewhere: an ABSENT ledger still
#      reports 0 (0 means "unmeasured" to the gate, never a block), and a pointer that resolves
#      to nothing is charged the conservative constant with a LOUD stderr line -- never zero,
#      never a crash.
#   C. LINK SYNTAX is not narrowed by the fix: a bare path, a backticked path and a markdown
#      link all count, in the foreign directory too.
#   E. A pointer whose path ESCAPES the repo root is ignored, loudly, and does not crash the
#      run. Deriving the directory is what makes this reachable at all; a constant could not
#      express `../`.
#   D. THE DEFECT ITSELF, ordered LAST so it is the last FAIL line a failing run emits: a repo
#      whose notes live in `docs/roadmap-notes` gets those bytes counted, where the hardcoded
#      spelling added 0.
#
# fails-against: the defect and its fix land in the SAME commit as this spec, so there is no
# ancestor tree to check out; the negative case is the mutation below, which restores the
# hardcoded `docs/ledger-notes` spelling of the pointer regex (the pre-fix behaviour, written
# in the post-fix whole-path capture shape so nothing else in the function has to change).
# fails-against-mutation: sed -i 's#^LEDGER_NOTE_POINTER_RE = .*#LEDGER_NOTE_POINTER_RE = re.compile(r"(docs/ledger-notes/[0-9a-f]{4}\\.md)")#' relay/scripts/classify-repo.sh
# fails-against-assertion: case D: a repo whose ledger notes live in a directory OTHER than docs/ledger-notes must have those note bytes counted
#
# Hermetic: mktemp -d fixture repos, git + python3 only, no network, never touches ~/.claude.
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

# Read one field out of `--emit unit`. stderr goes to $2 so the loud cases can inspect it.
field() {
  local repo_dir="$1" errfile="$2" key="$3" json
  json="$("$CR" --emit unit --repo fixture --path "$repo_dir" 2>"$errfile")" || return 1
  printf '%s' "$json" | python3 -c \
    'import sys,json;print(json.load(sys.stdin).get(sys.argv[1],"<<MISSING>>"))' "$key"
}

size() { wc -c < "$1" | tr -d ' '; }

# write_note <path> <id> — a body big enough that dropping it is unmistakable in the figure.
write_note() {
  local out="$1" id="$2" n=0
  { printf '# %s\n\n## Continuation detail (verbatim, moved from TODO.md)\n\n' "$id"
    while [[ $n -lt 120 ]]; do
      printf 'relocated acceptance-criteria prose for %s, line %03d, which a dispatched child must load in full.\n' "$id" "$n"
      n=$((n + 1))
    done
  } > "$out"
}

# ── case A -- REGRESSION GUARD, and FIRST. This repo's own spelling must keep counting exactly
#    what it counts today: ledger file size plus each pointed-at note, byte for byte.
A="$tmp/native"; mkrepo "$A"; mkdir -p "$A/docs/ledger-notes"
{ printf '# TODO\n\n## Current\n\n'
  for id in aa01 aa02; do
    printf -- '- [ ] slim head line for %s -- detail: `docs/ledger-notes/%s.md` <!-- id:%s -->\n' "$id" "$id" "$id"
  done
} > "$A/TODO.md"
printf '# ROADMAP\n\n- [ ] [ROUTINE] lonely <!-- id:1111 -->\n' > "$A/ROADMAP.md"
write_note "$A/docs/ledger-notes/aa01.md" aa01
write_note "$A/docs/ledger-notes/aa02.md" aa02
commit_repo "$A"
a_err="$tmp/a.err"
a_td="$(field "$A" "$a_err" todo_bytes || echo '<<ERROR>>')"
a_expect=$(( $(size "$A/TODO.md") + $(size "$A/docs/ledger-notes/aa01.md") + $(size "$A/docs/ledger-notes/aa02.md") ))
[[ "$a_td" == "$a_expect" ]] \
  || report "case A: a repo using docs/ledger-notes must keep counting file + notes exactly (todo_bytes '$a_td', expected $a_expect)"

# ── case B -- FAIL-OPEN END TO END, in a repo whose notes live elsewhere. An ABSENT ledger is
#    0 (unmeasured, never a block); a pointer that resolves to nothing is charged the
#    conservative constant and announced loudly, never counted as zero and never a crash.
B="$tmp/failopen"; mkrepo "$B"; mkdir -p "$B/docs/roadmap-notes"
printf '# ROADMAP\n\n- [ ] [ROUTINE] slim head -- detail: `docs/roadmap-notes/dead.md` <!-- id:2222 -->\n' \
  > "$B/ROADMAP.md"
commit_repo "$B"
b_err="$tmp/b.err"
b_td="$(field "$B" "$b_err" todo_bytes || echo '<<ERROR>>')"
b_rm="$(field "$B" "$b_err" roadmap_bytes || echo '<<ERROR>>')"
b_file="$(size "$B/ROADMAP.md")"
[[ "$b_td" == "0" ]] \
  || report "case B: an ABSENT TODO.md must still report 0 (fail-open), got '$b_td'"
if [[ "$b_rm" =~ ^[0-9]+$ ]] && (( b_rm > b_file )); then
  :
else
  report "case B: a foreign-directory pointer to a MISSING note must not be counted as zero (roadmap_bytes '$b_rm' vs file $b_file B)"
fi
grep -q 'docs/roadmap-notes/dead.md' "$b_err" \
  || report "case B: a MISSING note behind a foreign-directory pointer must be announced LOUDLY on stderr, naming the path"

# ── case C -- LINK SYNTAX is not narrowed. A bare path, a backticked path and a markdown link
#    all count, in the foreign directory too (the pre-fix comment promised this for the
#    hardcoded directory; the fix must not trade it away for portability).
C="$tmp/syntax"; mkrepo "$C"; mkdir -p "$C/notes/ledger"
{ printf '# TODO\n\n## Current\n\n'
  printf -- '- [ ] bare spelling -- detail: notes/ledger/cc01.md <!-- id:cc01 -->\n'
  printf -- '- [ ] backticked spelling -- detail: `notes/ledger/cc02.md` <!-- id:cc02 -->\n'
  printf -- '- [ ] markdown link spelling -- detail: [notes](notes/ledger/cc03.md) <!-- id:cc03 -->\n'
} > "$C/TODO.md"
printf '# ROADMAP\n\n- [ ] [ROUTINE] lonely <!-- id:3333 -->\n' > "$C/ROADMAP.md"
for id in cc01 cc02 cc03; do write_note "$C/notes/ledger/$id.md" "$id"; done
commit_repo "$C"
c_err="$tmp/c.err"
c_td="$(field "$C" "$c_err" todo_bytes || echo '<<ERROR>>')"
c_expect=$(( $(size "$C/TODO.md") \
  + $(size "$C/notes/ledger/cc01.md") \
  + $(size "$C/notes/ledger/cc02.md") \
  + $(size "$C/notes/ledger/cc03.md") ))
[[ "$c_td" == "$c_expect" ]] \
  || report "case C: bare, backticked and markdown-link pointers must ALL count (todo_bytes '$c_td', expected $c_expect)"

# ── case E -- a pointer whose path ESCAPES the repo root is ignored, loudly, and the run still
#    completes. Deriving the directory from the line is what makes this reachable; a constant
#    could not express `../`. It must not size a file outside the repo, and must not crash.
E="$tmp/escape/repo"; mkrepo "$E"; mkdir -p "$tmp/escape/outside"
write_note "$tmp/escape/outside/ee01.md" ee01
printf '# TODO\n\n## Current\n\n- [ ] escaping pointer -- detail: `../outside/ee01.md` <!-- id:ee01 -->\n' \
  > "$E/TODO.md"
printf '# ROADMAP\n\n- [ ] [ROUTINE] lonely <!-- id:4444 -->\n' > "$E/ROADMAP.md"
commit_repo "$E"
e_err="$tmp/e.err"
e_td="$(field "$E" "$e_err" todo_bytes || echo '<<ERROR>>')"
e_outside="$(size "$tmp/escape/outside/ee01.md")"
[[ "$e_td" == "$(size "$E/TODO.md")" ]] \
  || report "case E: a pointer escaping the repo root must be ignored, not sized (todo_bytes '$e_td', TODO.md is $(size "$E/TODO.md") B, the outside file is $e_outside B)"
grep -q 'escapes the repo root' "$e_err" \
  || report "case E: an escaping pointer must be announced LOUDLY on stderr"

# ── case D -- THE DEFECT, LAST. A repo whose notes live in `docs/roadmap-notes` (loderite's
#    spelling) must have those bytes folded into todo_bytes. Before the fix the hardcoded
#    `docs/ledger-notes` regex matched nothing here and the accounting added exactly 0 B, so
#    todo_bytes equalled the bare file size and the prompt-size gate went optimistic.
D="$tmp/foreign"; mkrepo "$D"; mkdir -p "$D/docs/roadmap-notes"
{ printf '# TODO\n\n## Current\n\n'
  for id in dd01 dd02 dd03; do
    printf -- '- [ ] slim head line for %s -- detail: `docs/roadmap-notes/%s.md` <!-- id:%s -->\n' "$id" "$id" "$id"
  done
} > "$D/TODO.md"
printf '# ROADMAP\n\n- [ ] [ROUTINE] lonely <!-- id:5555 -->\n' > "$D/ROADMAP.md"
for id in dd01 dd02 dd03; do write_note "$D/docs/roadmap-notes/$id.md" "$id"; done
commit_repo "$D"
d_err="$tmp/d.err"
d_td="$(field "$D" "$d_err" todo_bytes || echo '<<ERROR>>')"
d_file="$(size "$D/TODO.md")"
d_notes=$(( $(size "$D/docs/roadmap-notes/dd01.md") \
  + $(size "$D/docs/roadmap-notes/dd02.md") \
  + $(size "$D/docs/roadmap-notes/dd03.md") ))
d_expect=$(( d_file + d_notes ))
[[ "$d_td" == "$d_expect" ]] \
  || report "case D: a repo whose ledger notes live in a directory OTHER than docs/ledger-notes must have those note bytes counted (todo_bytes '$d_td', expected $d_expect = file $d_file + notes $d_notes)"

if (( fail )); then
  echo "--- fixture figures ---"
  echo "A native:   todo=$a_td (expected $a_expect)"
  echo "B failopen: todo=$b_td roadmap=$b_rm (file $b_file)"
  echo "C syntax:   todo=$c_td (expected $c_expect)"
  echo "E escape:   todo=$e_td (TODO.md $(size "$E/TODO.md"), outside file $e_outside)"
  echo "D foreign:  todo=$d_td (expected $d_expect = $d_file + $d_notes)"
  echo "--- case B stderr ---"; cat "$b_err" || true
  echo "--- case E stderr ---"; cat "$e_err" || true
  exit 1
fi
echo "PASS: the ledger-note byte accounting DERIVES the notes directory from the pointer (id:d4d3)"

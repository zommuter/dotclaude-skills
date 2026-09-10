#!/usr/bin/env bash
# No roadmap header -- defect-fix spec for TODO id:8cc6. Failures always count.
#
# THE DEFECT. `clean-tree-gate.sh` (the id:aa93 foreign-dirty guard) read
# `git status --porcelain` with NO `git diff` cross-check. `git status` is CLEAN-FILTER-BLIND:
# on a git-annex repo with `annex.addunlocked`, checkout writes the 100-byte pointer, git stats
# it into the index, annex swaps in the real content a fraction of a second later, and git never
# re-stats. Those paths then report ` M` forever while their worktree-vs-index DIFF IS EMPTY.
# Measured 2026-09-10 on ~/src/code.lawless: 111 paths ` M`, `git diff` empty, and
# `git hash-object --path` against the index blob gave identical=111 / differing=0. Uncarved,
# the gate defers such a repo FOREVER -- nothing a human can do clears dirt that is not there.
#
# WHY NO REFRESH FIXES IT, measured with GIT_TRACE rather than assumed: `git update-index
# --really-refresh` spawns ZERO subprocesses, never runs the clean filter, compares the large
# worktree file against the small blob and reports `needs update`. `git diff` on the same path
# DOES run the filter and reports equal. Case A below re-proves this inside the fixture, so the
# claim is checked here and not merely repeated from a comment.
#
# THE ONE WAY TO GET THE FIX CATASTROPHICALLY WRONG is to read "empty diff means clean". Plain
# `git diff` sees WORKTREE-vs-INDEX only; a STAGED change is invisible to it. A blanket
# relaxation would therefore collapse real staged work into "clean" and hand it to a merge --
# the exact data loss aa93 exists to prevent. Case D pins that.
#
# CONTRACT ASSERTED HERE:
#   A. FIXTURE PROOF, and first so nothing below can be vacuously satisfied: a clean repo reads
#      clean, and the filter fixture genuinely reproduces the condition (status ` M`, `git diff`
#      empty, index blob smaller than the worktree file, `--really-refresh` does not heal it).
#   B. THE FIX: a tree whose ONLY dirt is stat-cache dirt PASSES the gate.
#   C. A genuine tracked edit alongside that stat-cache dirt still BLOCKS, and the reported
#      entry is the genuine one only.
#   D. A STAGED change alongside it still BLOCKS. This is the catastrophic-wrong case.
#   E. id:27b4 is untouched: untracked-only still passes, RELAY_STRICT_UNTRACKED=1 still strict.
#   F. RELAY_STRICT_STATCACHE=1 restores the pre-fix strict behaviour.
#   G. The dirty line NAMES the path it inspected (the id:8cc6 mislabelling half: a consumer
#      called a WORKTREE "the main checkout" and sent an operator to a checkout that was clean).
#
# fails-against: the defect and its fix land in the SAME commit as this spec, so there is no
# ancestor tree to check out; the negative case is the mutation below, which disables the
# carve-out's activation test and so restores the pre-fix "every ` M` blocks" behaviour.
# fails-against-mutation: perl -0pi -e 's/if \[ "\$\{RELAY_STRICT_STATCACHE:-0\}" != "1" \]; then/if false; then/' relay/scripts/clean-tree-gate.sh
# fails-against-assertion: case B: a tree whose only dirt is stat-cache dirt must PASS the gate
#
# Hermetic: mktemp -d fixtures, git only, no network, no git-annex needed, never touches
# ~/.claude (CLEAN_TREE_LOG is redirected into the scratch dir) and never a repo under ~/src.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/relay/scripts/clean-tree-gate.sh"
[[ -x "$GATE" ]] || { echo "FAIL: clean-tree-gate.sh missing or not executable at $GATE"; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export CLEAN_TREE_LOG="$tmp/clean-tree.log"

# A repo with one commit and no filters.
mkrepo() { # <dir>
  local d="$1"
  mkdir -p "$d"; git -C "$d" init -q -b main
  git -C "$d" config user.email t@e; git -C "$d" config user.name T
  echo seed > "$d/plain.txt"; git -C "$d" add -A
  git -C "$d" -c commit.gpgsign=false commit -qm seed
}

# Reproduce the annex stat-cache condition WITHOUT git-annex: a clean filter that collapses any
# content to a short constant, a file committed in its SHORT (pointer) form, and then the long
# (content) form written into the worktree behind git's back. That is exactly annex's sequence:
# the index holds the pointer blob, the worktree holds the real content, and the cached stat was
# taken on the pointer. `git status` compares sizes and says ` M`; `git diff` runs the filter and
# says equal.
add_statcache_dirt() { # <repo>
  local d="$1"
  cat > "$d/../ptr-clean.sh" <<'CLEANF'
#!/usr/bin/env bash
# stand-in for git-annex's clean filter: any content collapses to the pointer
cat >/dev/null
printf 'POINTER\n'
CLEANF
  chmod +x "$d/../ptr-clean.sh"
  git -C "$d" config filter.ptr.clean "$d/../ptr-clean.sh"
  printf 'asset.bin filter=ptr\n' > "$d/.gitattributes"
  printf 'POINTER\n' > "$d/asset.bin"
  git -C "$d" add .gitattributes asset.bin
  git -C "$d" -c commit.gpgsign=false commit -qm asset
  # annex swaps the real content in, after git has already stat'd the pointer
  python3 -c "import sys; open(sys.argv[1],'wb').write(b'X'*15641)" "$d/asset.bin"
}

# --- case A -- FIXTURE PROOF, FIRST -----------------------------------------------------------
A="$tmp/a/repo"; mkrepo "$A"
if out="$("$GATE" "$A" 2>&1)" && [[ "$out" == "clean" ]]; then
  echo "ok: case A(1) -- a genuinely clean repo reads clean (calibration)"
else
  echo "FAIL: case A(1): a genuinely clean repo must read clean (out: ${out//$'\n'/ })"
  exit 1
fi
add_statcache_dirt "$A"
a_status="$(git -C "$A" status --porcelain)"
a_diff="$(git -C "$A" diff --name-only)"
a_blob="$(git -C "$A" cat-file -s :asset.bin)"
a_wt="$(stat -c%s "$A/asset.bin")"
if [[ "$a_status" == " M asset.bin" && -z "$a_diff" && "$a_blob" -lt "$a_wt" ]]; then
  echo "ok: case A(2) -- fixture reproduces the condition: status ' M', diff EMPTY, blob ${a_blob}B < worktree ${a_wt}B"
else
  echo "FAIL: case A(2): fixture does NOT reproduce the stat-cache condition, so every case below would be vacuous (status='$a_status' diff='$a_diff' blob=$a_blob wt=$a_wt)"
  exit 1
fi
git -C "$A" update-index --really-refresh >/dev/null 2>&1 || true
if [[ "$(git -C "$A" status --porcelain)" == " M asset.bin" ]]; then
  echo "ok: case A(3) -- 'update-index --really-refresh' does NOT heal it (the obvious cheap fix, re-proved not to work)"
else
  echo "FAIL: case A(3): a refresh healed the fixture, so it is not the filter-blind condition this test claims to pin"
  exit 1
fi

# --- case B -- THE FIX ------------------------------------------------------------------------
if out="$("$GATE" "$A" 2>&1)" && [[ "$out" == "clean" ]]; then
  echo "ok: case B -- a stat-cache-dirty tree PASSES (the aa93 guard no longer defers it forever)"
else
  echo "FAIL: case B: a tree whose only dirt is stat-cache dirt must PASS the gate (out: ${out//$'\n'/ })"
  exit 1
fi

# --- case C -- a genuine tracked edit alongside it still BLOCKS -------------------------------
printf 'edited by a concurrent human\n' >> "$A/plain.txt"
rc=0; out="$("$GATE" "$A" 2>&1)" || rc=$?
if [[ "$rc" -eq 2 ]] && grep -q 'plain\.txt' <<<"$out" && ! grep -q 'asset\.bin' <<<"$out"; then
  echo "ok: case C -- a genuine tracked edit still BLOCKS, and only the genuine entry is reported"
else
  echo "FAIL: case C: a genuine tracked edit must still block and must be the only entry reported (rc=$rc, out: ${out//$'\n'/ })"
  exit 1
fi
git -C "$A" checkout -- plain.txt

# --- case D -- a STAGED change still BLOCKS ---------------------------------------------------
# `git diff` (no --cached) cannot see this. A naive "empty diff means clean" relaxation would
# report the whole tree clean here and let a merge run over staged foreign work.
printf 'staged content\n' > "$A/staged.txt"
git -C "$A" add staged.txt
rc=0; out="$("$GATE" "$A" 2>&1)" || rc=$?
if [[ "$rc" -eq 2 ]] && grep -q 'staged\.txt' <<<"$out"; then
  echo "ok: case D -- a STAGED change still BLOCKS (the carve-out is keyed on the ' M' pair, not on an empty diff)"
else
  echo "FAIL: case D: a staged change must still block the gate (rc=$rc, out: ${out//$'\n'/ })"
  exit 1
fi
git -C "$A" rm -q --cached staged.txt >/dev/null; rm -- "$A/staged.txt"

# --- case E -- id:27b4 untouched --------------------------------------------------------------
printf 'stray\n' > "$A/stray.png"
if out="$("$GATE" "$A" 2>&1)" && [[ "$out" == "clean" ]]; then
  echo "ok: case E(1) -- untracked alongside stat-cache dirt still passes (id:27b4 intact)"
else
  echo "FAIL: case E(1): untracked entries must still be non-blocking per id:27b4 (out: ${out//$'\n'/ })"
  exit 1
fi
rc=0; out="$(RELAY_STRICT_UNTRACKED=1 "$GATE" "$A" 2>&1)" || rc=$?
if [[ "$rc" -eq 2 ]] && grep -q 'stray\.png' <<<"$out"; then
  echo "ok: case E(2) -- RELAY_STRICT_UNTRACKED=1 still restores strict untracked handling"
else
  echo "FAIL: case E(2): RELAY_STRICT_UNTRACKED=1 must still block on untracked (rc=$rc, out: ${out//$'\n'/ })"
  exit 1
fi
rm -- "$A/stray.png"

# --- case F -- RELAY_STRICT_STATCACHE=1 restores the pre-fix behaviour ------------------------
rc=0; out="$(RELAY_STRICT_STATCACHE=1 "$GATE" "$A" 2>&1)" || rc=$?
if [[ "$rc" -eq 2 ]] && grep -q 'asset\.bin' <<<"$out"; then
  echo "ok: case F -- RELAY_STRICT_STATCACHE=1 restores strict blocking (escape hatch works)"
else
  echo "FAIL: case F: RELAY_STRICT_STATCACHE=1 must restore the strict pre-fix behaviour (rc=$rc, out: ${out//$'\n'/ })"
  exit 1
fi

# --- case G -- the dirty line names the path it inspected -------------------------------------
G="$tmp/g/repo"; mkrepo "$G"
printf 'foreign\n' >> "$G/plain.txt"
rc=0; out="$("$GATE" "$G" 2>&1)" || rc=$?
first="$(printf '%s\n' "$out" | sed -n '1p')"
if [[ "$rc" -eq 2 && "$first" == dirty\ * ]] && grep -qF "$G" <<<"$first"; then
  echo "ok: case G -- the dirty line names the inspected path and still prefix-matches 'dirty '"
else
  echo "FAIL: case G: the dirty line must name the inspected path while staying prefix-compatible (rc=$rc, first: '$first')"
  exit 1
fi

echo "PASS: stat-cache dirt no longer blocks the aa93 gate, and staged/tracked/strict cases still do (id:8cc6)"

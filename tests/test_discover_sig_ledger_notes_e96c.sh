#!/usr/bin/env bash
# DEFECT-FIX test (TODO id:e96c). No `# roadmap:XXXX` header on purpose: this closes a
# regression the id:0d7c ledger line-shrink introduced, and has no ROADMAP item of its own.
# Failures here always count.
#
# WHY THIS EXISTS. `discover-sig.sh` promises to hash a SUPERSET of every input the classifier
# shard reads, so the pool may reuse last round's verdict when the sig is unchanged. Its sole
# documented hazard is UNDER-invalidation (CLAUDE.md: "If you add a NEW signal to the shard
# prompt, add it to discover-sig.sh's blob too, or its verdict can go stale").
#
# The ratified line-shrink moves an item's PROSE off its ledger line into a per-id detail note,
# and `classify-repo.sh` (id:f3d2) stats every pointed-to note to compute roadmap_bytes /
# todo_bytes. The notes are therefore shard inputs. They reached the blob only via
# `git status --porcelain`, which records THAT a file changed and never WHAT changed, so N
# substantively different UNCOMMITTED edits to one note collapsed to ONE signature.
#
# The second thing pinned here is the id:d4d3 trap: the notes directory must be DERIVED from
# the item's pointer, never hardcoded to `docs/ledger-notes`, or the fix is inert on the 45
# fleet repos that name the directory differently.
#
# fails-against: the tree immediately before the id:e96c fix, i.e. a discover-sig.sh whose blob
#   carries no `== ledger_notes ==` section. The mutation below reproduces exactly that state
#   by deleting that one printf from the blob, leaving everything else intact.
# fails-against-mutation: grep -v '== ledger_notes ==' relay/scripts/discover-sig.sh > .e96c-mutant.tmp && cat .e96c-mutant.tmp > relay/scripts/discover-sig.sh && rm -- .e96c-mutant.tmp
# fails-against-assertion: a SECOND uncommitted edit to the pointed-to note left the signature IDENTICAL

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SIG="$SRC_DIR/relay/scripts/discover-sig.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

TMP="$(mktemp -d)"
trap 'chmod -R u+rwX "$TMP" 2>/dev/null || true; rm -rf "$TMP"' EXIT
export RELAY_TOML="$TMP/relay.toml"
export RELAY_WORKTREE_BASE="$TMP/worktrees"
mkdir -p "$RELAY_WORKTREE_BASE"

REPO="$TMP/widget"
git init -q "$REPO"
git -C "$REPO" config user.email t@example.invalid
git -C "$REPO" config user.name tester
mkdir -p "$REPO/docs/ledger-notes" "$REPO/docs/roadmap-notes"
printf '# Roadmap\n- [ ] [ROUTINE] work -- detail: `docs/ledger-notes/ca02.md` <!-- id:ca02 -->\n' \
  > "$REPO/ROADMAP.md"
printf '# TODO\n- [ ] [ROUTINE] other -- detail: `docs/roadmap-notes/ab12.md` <!-- id:ab12 -->\n' \
  > "$REPO/TODO.md"
printf '# id:ca02\n\nbody v0\n' > "$REPO/docs/ledger-notes/ca02.md"
printf '# id:ab12\n\nforeign-dir body v0\n' > "$REPO/docs/roadmap-notes/ab12.md"
git -C "$REPO" add -A
git -C "$REPO" commit -qm init
cat > "$RELAY_TOML" <<'TOML'
[repos.widget]
classification = "own"
income = false
TOML

sig_of() {
  printf '{"repos":[{"repo":"widget","path":"%s"}],"liveClaims":[]}\n' "$REPO" \
    | "$SIG" | python3 -c 'import sys,json; print(json.loads(sys.stdin.readline())["sig"])'
}

S0="$(sig_of)"
[[ -n "$S0" ]] || fail "signature empty for a valid repo (should only be empty on fail-open)"
pass "baseline signature is non-empty"

# --- Case 1. THE DEFECT: three successive UNCOMMITTED edits to one pointed-to note must
# produce three DIFFERENT signatures. Pre-fix they produced one: the first edit moved the sig
# only because `git status --porcelain` gained an `M` line, and every edit after that was
# invisible.
printf 'body v1\n' >> "$REPO/docs/ledger-notes/ca02.md"
S1="$(sig_of)"
[[ "$S1" != "$S0" ]] \
  || fail "the FIRST uncommitted edit to the pointed-to note left the signature IDENTICAL"
printf 'body v2\n' >> "$REPO/docs/ledger-notes/ca02.md"
S2="$(sig_of)"
[[ "$S2" != "$S1" ]] \
  || fail "a SECOND uncommitted edit to the pointed-to note left the signature IDENTICAL -- only the porcelain M line is hashed, not the note's CONTENT, so the cache would serve a STALE verdict (under-invalidation)"
printf 'body v3\n' >> "$REPO/docs/ledger-notes/ca02.md"
S3="$(sig_of)"
[[ "$S3" != "$S2" ]] \
  || fail "a THIRD uncommitted edit to the pointed-to note left the signature identical to the second"
pass "three uncommitted note edits produce three different signatures"

# --- Case 2. Determinism: unchanged on-disk state, identical sig.
S3b="$(sig_of)"
[[ "$S3b" == "$S3" ]] || fail "signature is not deterministic on unchanged state: '$S3b' != '$S3'"
pass "still deterministic on unchanged state"

# --- Case 3. COMMITTED note edits move the sig too (via HEAD, and via the note hash).
git -C "$REPO" commit -qam "note edit"
S4="$(sig_of)"
[[ "$S4" != "$S3" ]] || fail "committing the note edit left the signature identical"
printf 'body v4 committed\n' >> "$REPO/docs/ledger-notes/ca02.md"
git -C "$REPO" commit -qam "note edit 2"
S5="$(sig_of)"
[[ "$S5" != "$S4" ]] || fail "a second COMMITTED note edit left the signature identical"
pass "committed note edits move the signature"

# --- Case 4. THE id:d4d3 TRAP: the notes directory is DERIVED from the pointer. This repo's
# TODO.md points into `docs/roadmap-notes` (loderite's spelling), which a hardcoded
# `docs/ledger-notes` would never see.
printf 'foreign-dir body v1\n' >> "$REPO/docs/roadmap-notes/ab12.md"
S6="$(sig_of)"
[[ "$S6" != "$S5" ]] \
  || fail "editing a note in a NON-default notes directory left the signature identical -- the notes directory is hardcoded, not derived from the pointer (id:d4d3)"
printf 'foreign-dir body v2\n' >> "$REPO/docs/roadmap-notes/ab12.md"
S7="$(sig_of)"
[[ "$S7" != "$S6" ]] \
  || fail "a second edit in the NON-default notes directory left the signature identical"
pass "a pointer-derived notes directory is followed, not just docs/ledger-notes"

# --- Case 5. Round-trip: restoring the exact prior content restores the prior signature
# (the blob is a pure function of state, not an accumulator).
git -C "$REPO" checkout -q -- docs/roadmap-notes/ab12.md
git -C "$REPO" checkout -q -- docs/ledger-notes/ca02.md 2>/dev/null || true
S8="$(sig_of)"
[[ "$S8" == "$S5" ]] \
  || fail "restoring the notes' committed content did not restore the signature -- the blob is not a pure function of on-disk state"
pass "signature round-trips when note content is restored"

# --- Case 6. A MISSING pointer target is a normal, stable state, not a fail-open trigger.
printf -- '- [ ] [ROUTINE] dangling -- detail: `docs/ledger-notes/dead.md` <!-- id:dead -->\n' \
  >> "$REPO/ROADMAP.md"
S9="$(sig_of)"; S9b="$(sig_of)"
[[ -n "$S9" ]] || fail "signature went empty merely because a pointer names a missing note"
[[ "$S9" == "$S9b" ]] || fail "signature is not stable when a pointer names a missing note"
printf '# id:dead\n\nnow it exists\n' > "$REPO/docs/ledger-notes/dead.md"
S10="$(sig_of)"
[[ "$S10" != "$S9" ]] || fail "creating a previously-missing pointed-to note left the signature identical"
pass "a missing pointer target is stable, and creating it moves the sig"

# --- Case 7. FAIL-OPEN, unchanged: a non-git path still yields the empty sentinel.
mkdir -p "$TMP/notarepo"
SNG="$(printf '{"repos":[{"repo":"notarepo","path":"%s"}],"liveClaims":[]}\n' "$TMP/notarepo" \
        | "$SIG" | python3 -c 'import sys,json; print(json.loads(sys.stdin.readline())["sig"])')"
[[ -z "$SNG" ]] || fail "fail-open broken: a non-git path produced a CONFIDENT signature '$SNG'"
pass "fail-open preserved: non-git path yields the empty sentinel"

# --- Case 8. FAIL-OPEN on an UNREADABLE pointed-to note: the sig must NOT go confident and
# stale behind input it could not read. Two successive calls must differ (a nonce forces a
# re-classify). Skipped for root, for whom chmod 000 is not a read barrier.
if [[ "$(id -u)" != "0" ]]; then
  chmod 000 "$REPO/docs/ledger-notes/dead.md"
  if [[ -r "$REPO/docs/ledger-notes/dead.md" ]]; then
    echo "SKIP: chmod 000 did not make the note unreadable on this filesystem"
  else
    U1="$(sig_of)"; U2="$(sig_of)"
    [[ -n "$U1" ]] || fail "an unreadable note collapsed the whole signature to the empty sentinel"
    [[ "$U1" != "$U2" ]] \
      || fail "an UNREADABLE pointed-to note produced a stable, CONFIDENT signature -- a failure to read an input must force a re-classify, never freeze the cache"
    pass "fail-open preserved: an unreadable note forces a re-classify"
  fi
  chmod 644 "$REPO/docs/ledger-notes/dead.md"
else
  echo "SKIP: running as root, chmod 000 is not a read barrier"
fi

echo "OK: test_discover_sig_ledger_notes_e96c.sh"

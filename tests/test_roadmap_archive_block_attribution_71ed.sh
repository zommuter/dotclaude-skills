#!/usr/bin/env bash
# No roadmap header -- this is a defect-fix spec for inbox item routed:71ed, which has no
# ROADMAP twin in this repo. Failures always count.
#
# THE DEFECT, observed live in the it-infra repo on 2026-09-01 and repaired there by hand
# (it-infra 3f49174, which reverses 090247f):
#
#   `relay/scripts/roadmap-archive.sh` gathers an item's "block" as its header line plus
#   every following line up to the next top-level bullet or heading. When a NEW item line is
#   INSERTED between an existing item's header and its own indented bullets, that rule
#   re-attributes the bullets to the insertee. Archiving the closed insertee then sweeps the
#   OPEN item's Why / gate / Acceptance bullets into ROADMAP.archive.md under the WRONG id.
#
#   Concretely there: a 10:28 mini-handoff inserted `- [x] ... <!-- id:5f19 -->` directly
#   between the header of the OPEN `<!-- id:f6d3 -->` and f6d3's three continuation bullets.
#   The 10:47 archive run moved all three into the archive under id:5f19. Nothing failed.
#   An open [INPUT - access] item was left as a bare title with its acceptance criterion
#   filed under a closed id where nobody would look.
#
# WHY DEFER-AND-WARN RATHER THAN RE-ATTRIBUTE, and why not the filed lint suggestion:
#
#   The shape is genuinely ambiguous LOCALLY. These two are character-identical:
#       - [ ] open item            - [ ] open item with no body of its own
#       - [x] closed item          - [x] closed item that owns the bullets below
#         - bullets (open's)         - bullets (closed's)
#   so no local rule can decide ownership, and this repo's own
#   tests/test_roadmap_archive_leaves_stub.sh case 2 relies on the SECOND reading.
#
#   The item's filed suggestion -- flag a continuation block whose text names a different id
#   than its header -- was EVALUATED AND REJECTED: it would have MISSED this very incident.
#   f6d3's three bullets name no id at all (they name id:cf06, a gate, which is not the
#   owning header either way), while the 5f19 header line itself DOES mention "id:f6d3" in
#   prose. The heuristic points the wrong way on the case that produced it.
#
#   So the archiver DEFERS instead of guessing, and says so loudly on stderr naming the id.
#
# WHAT THE DEFERRAL DOES, AND WHY IT CHANGED (id:2eba, 2026-09-03):
#   It USED to archive the header line only, leave the continuation body in ROADMAP.md, and
#   leave a stub above that body. That split relied on the STUB to hold the retained body
#   apart from the live bullet above it. id:2eba removed the stub, so the retained body would
#   silently re-attach to that neighbour -- the archiver would be GUESSING an attribution,
#   which is the one thing routed:71ed exists to refuse.
#   The deferral is therefore now TOTAL: on the ambiguous shape the item is NOT archived at
#   all. Header and body both stay verbatim in the live ROADMAP.md, and stderr names the id.
#   Nothing is lost in either direction, and the state is still a fixed point -- the next run
#   re-derives the same refusal and mutates nothing.
#
# Contract asserted here:
#   1. REGRESSION: an unambiguous closed item still archives with its whole body, exactly as
#      before -- body gone from the live file, present in the archive.
#   2. THE LIVE SHAPE: the OPEN item's bullets stay in ROADMAP.md and do NOT reach
#      ROADMAP.archive.md.
#   3. The deferral is LOUD -- stderr names the ambiguous id. A silent skip is the same
#      defect class wearing a different coat (id:4347).
#   4. The closed item is NOT archived at all: it keeps its whole live line and nothing of it
#      reaches ROADMAP.archive.md, so a human can repair the attribution from the live file.
#
# fails-against: the defect and its fix land in the SAME commit as this spec, so there is no
# ancestor tree to check out; the negative case is the mutation below, which disables the
# guard and restores the pre-fix block rule verbatim.
# fails-against-mutation: sed -i 's/^AMBIGUITY_GUARD = True/AMBIGUITY_GUARD = False/' relay/scripts/roadmap-archive.sh
# fails-against-assertion: case 2a: the OPEN item's Acceptance bullet was REMOVED from the live ROADMAP.md
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_SCRIPT="$ROOT/relay/scripts/roadmap-archive.sh"

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }

[[ -x "$ARCHIVE_SCRIPT" ]] || fail "roadmap-archive.sh not found/executable at $ARCHIVE_SCRIPT"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

make_repo() {
    # make_repo <dir> <roadmap-content>
    local repo="$1" content="$2"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" config user.email t@example.com
    git -C "$repo" config user.name tester
    printf '%s' "$content" > "$repo/ROADMAP.md"
    git -C "$repo" add ROADMAP.md
    git -C "$repo" commit -qm "seed ROADMAP.md"
}

# ─────────────────────────────────────────────────────────────────────────────
# Case 1 -- REGRESSION GUARD, run FIRST so a script that archives nothing at all
# cannot vacuously satisfy case 2. An unambiguous closed item (its header is NOT
# preceded by a live top-level bullet) archives with its own body, as it always has.
# ─────────────────────────────────────────────────────────────────────────────
repo1="$tmp/repo1"
make_repo "$repo1" "# Roadmap

## Items

- [x] [ROUTINE] **A closed item that genuinely owns its body** <!-- id:aa11 -->
  - **Why**: this bullet belongs to id:aa11 and must travel with it.
  - **Acceptance**: aa11 acceptance text.
- [ ] [ROUTINE] **An unrelated open item** <!-- id:bb22 -->
"

"$ARCHIVE_SCRIPT" "$repo1" >/dev/null 2>&1 || true

grep -qF 'aa11 acceptance text' "$repo1/ROADMAP.md" \
  && fail "case 1: an unambiguous closed item's body was left in the live ROADMAP.md"
grep -qF 'aa11 acceptance text' "$repo1/ROADMAP.archive.md" 2>/dev/null \
  || fail "case 1: an unambiguous closed item's body did not reach ROADMAP.archive.md"
grep -qF 'this bullet belongs to id:aa11' "$repo1/ROADMAP.archive.md" 2>/dev/null \
  || fail "case 1: an unambiguous closed item's body was only partly archived"
pass "case 1: normal archiving is unchanged -- a closed item's own body still moves with it"

grep -qF 'id:bb22' "$repo1/ROADMAP.md" || fail "case 1: the open item vanished from ROADMAP.md"
pass "case 1: the neighbouring open item is untouched"

# ─────────────────────────────────────────────────────────────────────────────
# Case 2 -- THE LIVE SHAPE (it-infra 090247f). The OPEN header is on one line, the
# CLOSED item is inserted directly beneath it, and the indented bullets that follow
# belong to the OPEN item. Fixture mirrors the real one: the open item carries a
# `gated-on:` edge and an [INPUT - access] lane, the closed one is a long single-line
# [ROUTINE] mini-handoff, and the bullets are Why / gate / Acceptance.
# ─────────────────────────────────────────────────────────────────────────────
repo2="$tmp/repo2"
make_repo "$repo2" "# Roadmap

## Items

- [ ] [INPUT - access] **Live-verify the stack comes up** [host:zomni] <!-- gated-on:cf06 --> <!-- id:f6d3 -->
- [x] [ROUTINE] **Lint: a file that generates NO unit must fail LOUDLY** <!-- id:5f19 --> Mini-handoff 2026-09-01 (relay review), id REUSED not minted. Idiom already proven in-repo at ROADMAP.md's id:f6d3 note.
  - **Why INPUT - access**: needs the real stack started against a real database; a
    relay child must not start or stop the owner's running services unattended.
  - **Why gated**: pointless before id:cf06 makes the unit generate at all.
  - **Acceptance**: the open item's acceptance criterion, which must stay live.
- [ ] [ROUTINE] **A later open item** <!-- id:cc33 -->
"

err2="$("$ARCHIVE_SCRIPT" "$repo2" 2>&1 >/dev/null || true)"

# 2a -- the defect itself: the OPEN item keeps its body.
grep -qF "the open item's acceptance criterion, which must stay live" "$repo2/ROADMAP.md" \
  || fail "case 2a: the OPEN item's Acceptance bullet was REMOVED from the live ROADMAP.md"
grep -qF "relay child must not start or stop" "$repo2/ROADMAP.md" \
  || fail "case 2b: the OPEN item's Why bullet was REMOVED from the live ROADMAP.md"
grep -qF "pointless before id:cf06" "$repo2/ROADMAP.md" \
  || fail "case 2c: the OPEN item's gate-history bullet was REMOVED from the live ROADMAP.md"
pass "case 2: the open item retains its Why / gate / Acceptance bullets"

# 2d -- and the archive did not gain them under the closed id.
if [[ -f "$repo2/ROADMAP.archive.md" ]]; then
  grep -qF "the open item's acceptance criterion, which must stay live" "$repo2/ROADMAP.archive.md" \
    && fail "case 2d: the OPEN item's Acceptance bullet was filed in ROADMAP.archive.md under a closed id"
  grep -qF "relay child must not start or stop" "$repo2/ROADMAP.archive.md" \
    && fail "case 2e: the OPEN item's Why bullet was filed in ROADMAP.archive.md under a closed id"
fi
pass "case 2: the archive did not gain the open item's body"

grep -qF 'id:f6d3' "$repo2/ROADMAP.md" || fail "case 2f: the OPEN item's header vanished from ROADMAP.md"
grep -qE '^- \[ \].*id:f6d3' "$repo2/ROADMAP.md" >/dev/null \
  || fail "case 2g: the OPEN item stopped being an open top-level bullet"
pass "case 2: the open item is still an open top-level bullet"

# ─────────────────────────────────────────────────────────────────────────────
# Case 3 -- the deferral must be LOUD. A silent skip is the same defect wearing a
# different coat (id:4347, no-silent-swallow).
# ─────────────────────────────────────────────────────────────────────────────
grep -qF '5f19' <<<"$err2" \
  || fail "case 3: the ambiguous item was handled silently -- stderr never named id:5f19"
grep -qiE 'ambiguous|attribution' <<<"$err2" \
  || fail "case 3: stderr names id:5f19 but never says the attribution was ambiguous"
pass "case 3: the ambiguous shape is announced on stderr, naming the id"

# ─────────────────────────────────────────────────────────────────────────────
# Case 4 -- the deferral is TOTAL (id:2eba): the ambiguous item is NOT archived at
# all. Its whole live line stays, and nothing of it reaches the archive, so the
# attribution can be repaired from the live file with both halves in front of you.
# ─────────────────────────────────────────────────────────────────────────────
live2="$(grep -F 'id:5f19' "$repo2/ROADMAP.md" || true)"
[[ -n "$live2" ]] || fail "case 4: id:5f19 was archived despite the ambiguous body -- the deferral must refuse the whole item"
grep -qF '(archived' <<<"$live2" \
  && fail "case 4: id:5f19's live line carries an archive stub -- id:2eba writes none"
grep -qE '^- \[x\] .*Lint: a file that generates NO unit' <<<"$live2" \
  || fail "case 4: id:5f19's live line is not its original header verbatim -- got: >>>$live2<<<"
if [[ -f "$repo2/ROADMAP.archive.md" ]]; then
  grep -qF 'id:5f19' "$repo2/ROADMAP.archive.md" \
    && fail "case 4: the ambiguous item reached ROADMAP.archive.md -- the deferral must archive nothing"
fi
pass "case 4: the ambiguous item is refused whole -- header and body both stay live, archive untouched"

# ─────────────────────────────────────────────────────────────────────────────
# Case 5 -- IDEMPOTENCE. Re-running must not re-open the question, re-archive the
# stub, or start moving the retained body. The deferred state is a fixed point.
# ─────────────────────────────────────────────────────────────────────────────
git -C "$repo2" add -A >/dev/null 2>&1 || true
git -C "$repo2" commit -qm 'after run 1' >/dev/null 2>&1 || true
before_live="$(cat "$repo2/ROADMAP.md")"
before_arch="$(cat "$repo2/ROADMAP.archive.md" 2>/dev/null || true)"
"$ARCHIVE_SCRIPT" "$repo2" >/dev/null 2>&1 || true
[[ "$before_live" == "$(cat "$repo2/ROADMAP.md")" ]] \
  || fail "case 5: a second run mutated ROADMAP.md -- the deferred state is not a fixed point"
[[ "$before_arch" == "$(cat "$repo2/ROADMAP.archive.md" 2>/dev/null || true)" ]] \
  || fail "case 5: a second run grew ROADMAP.archive.md -- the deferred state is not a fixed point"
pass "case 5: the deferred state is a fixed point across runs"

echo "ALL PASS"

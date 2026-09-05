#!/usr/bin/env bash
# roadmap:4839
#
# RED SPEC for dimension (b) of id:4839: the ratchet baselines key on
# `<ledger BASENAME>/<4-hex id>` (todo-conformance.sh:769 builds LENGTH_LEDGER_KEY from
# `basename "$path"`; :725 and :522 do the lookups). Every repo in the fleet has a TODO.md and
# a ROADMAP.md and the 4-hex id space is per-repo, not fleet-unique -- 187 adjudicated
# cross-repo homonyms already sit in tracker/homonym-allowlist.txt -- so one repo's baseline
# row silently supplies the ceiling for an unrelated item in another repo.
#
# The live instance: token 55c7 is baselined here as `ROADMAP.md<TAB>55c7<TAB>642`
# (relay/head-length-baseline.txt:56, em-dash migration S7) and exists unrelated in loderite,
# whose 968-char ROADMAP line would read as REGROWTH against our ceiling while its 208-char
# TODO twin would be silently GRANDFATHERED against the SAME entry. Both failure directions,
# one token, one row, no warning in either.
#
# WHAT THIS PINS, and deliberately what it does NOT. It does not pin a spelling for the repo
# dimension -- the acceptance leaves that to the implementer. It pins the OBSERVABLE: a
# baseline generated in repo A must not classify repo B's same-token item at all. Regen in A,
# check in B, assert B reports a NOT-BASELINED class in BOTH directions (B over A's ceiling,
# and B under it). That assertion holds for any correct repo dimension and fails for every
# basename-only key.
#
# TRIANGULATION (id:108e): four cases, two per ratchet, covering both over- and under-ceiling,
# so the only way to pass is to actually scope the lookup rather than special-case a number.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$ROOT/relay/scripts/todo-conformance.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
report() { echo "FAIL: $1"; fail=1; }

# Two fixture REPOS. Each is a real git repo with a real repo name, because whatever the repo
# dimension turns out to be (git remote, toplevel basename, an explicit env/flag), it has to be
# derivable from a checkout.
mkrepo() { # <name>
  local d="$tmp/$1"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email t@example.invalid
  git -C "$d" config user.name t
  printf '%s\n' "$d"
}

filler() { # <n> -> 60 chars per repeat, neutral prose, no state-claim or dependency words
  local i
  for ((i = 0; i < $1; i++)); do
    printf 'padding prose about ledger head lines, segment %02d here; ' "$i"
  done
}

# The shared token. Same 4 hex chars in both repos, unrelated items -- the 55c7 shape.
TOK=55c7

roadmap_line() { # <filler-repeats>
  printf -- '- [ ] [ROUTINE] **Title for %s** %s<!-- id:%s -->\n' "$TOK" "$(filler "$1")" "$TOK"
}

REPO_A="$(mkrepo repo-alpha)"
REPO_B="$(mkrepo repo-beta)"

# Repo A: the BASELINING repo. A long line -- 12 filler repeats, ~720 chars, over the
# 500-char budget, so it lands in the length baseline; its residue lands in the shape one.
roadmap_line 12 > "$REPO_A/ROADMAP.md"

# Repo B, case OVER: longer than A's ceiling. Under a basename-only key this reads as
# `length-regrowth` / `shape-regrowth` against a ceiling it has never been measured against.
roadmap_line 20 > "$REPO_B/ROADMAP-over.md"
# Repo B, case UNDER: shorter than A's ceiling but still over the shipped 500-char budget, so
# it IS reported. Under a basename-only key this is silently forgiven as
# `length-grandfathered` / `shape-grandfathered` -- the quieter, worse direction.
roadmap_line 10 > "$REPO_B/ROADMAP-under.md"

# Both fixtures must be named ROADMAP.md at check time (the key is the basename), so give
# each its own directory inside repo B.
mkdir -p "$REPO_B/over" "$REPO_B/under"
mv "$REPO_B/ROADMAP-over.md" "$REPO_B/over/ROADMAP.md"
mv "$REPO_B/ROADMAP-under.md" "$REPO_B/under/ROADMAP.md"

git -C "$REPO_A" add -A >/dev/null 2>&1 || true
git -C "$REPO_A" commit -qm fixture >/dev/null 2>&1 || true
git -C "$REPO_B" add -A >/dev/null 2>&1 || true
git -C "$REPO_B" commit -qm fixture >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# Generate BOTH baselines from repo A.
# ---------------------------------------------------------------------------
LEN_BL="$tmp/length-baseline.txt"
SHAPE_BL="$tmp/shape-baseline.txt"

( cd "$REPO_A" && LENGTH_BASELINE="$tmp/absent-len.txt" SHAPE_BASELINE="$tmp/absent-shape.txt" \
    bash "$SH" --regen-length-baseline ROADMAP.md ) > "$LEN_BL"
( cd "$REPO_A" && LENGTH_BASELINE="$tmp/absent-len.txt" SHAPE_BASELINE="$tmp/absent-shape.txt" \
    bash "$SH" --regen-shape-baseline ROADMAP.md ) > "$SHAPE_BL"

grep -q "$TOK" "$LEN_BL"   || report "fixture sanity: repo A did not enter the LENGTH baseline (token $TOK absent) -- the rest of this file would be vacuous"
grep -q "$TOK" "$SHAPE_BL" || report "fixture sanity: repo A did not enter the SHAPE baseline (token $TOK absent) -- the rest of this file would be vacuous"

# ---------------------------------------------------------------------------
# Check repo B against repo A's baselines.
# ---------------------------------------------------------------------------
check_b() { # <subdir> -> classification lines for $TOK on stdout
  ( cd "$REPO_B/$1" && LENGTH_BASELINE="$LEN_BL" SHAPE_BASELINE="$SHAPE_BL" \
      bash "$SH" ROADMAP.md 2>/dev/null || true ) | grep -F "id:$TOK" || true
}

over="$(check_b over)"
under="$(check_b under)"

# (a) LENGTH, over-ceiling: must NOT be attributed to repo A's row.
if grep -q 'length-regrowth' <<<"$over"; then
  report "(a) LENGTH over-ceiling: repo B's $TOK was reported length-regrowth against repo A's baseline row -- the baseline key has no repo dimension (id:4839 dimension b)"
fi
# (b) LENGTH, under-ceiling: the silent direction.
if grep -q 'length-grandfathered' <<<"$under"; then
  report "(b) LENGTH under-ceiling: repo B's $TOK was silently grandfathered against repo A's baseline row -- the baseline key has no repo dimension (id:4839 dimension b)"
fi
# (c) SHAPE, over-ceiling.
if grep -q 'shape-regrowth' <<<"$over"; then
  report "(c) SHAPE over-ceiling: repo B's $TOK was reported shape-regrowth against repo A's baseline row -- the baseline key has no repo dimension (id:4839 dimension b)"
fi
# (d) SHAPE, under-ceiling -- and this is the LAST assertion in the file on purpose: it is the
# quietest failure of the four (no finding escalates, nothing is printed to a human), so it is
# the one a partial fix is most likely to leave standing.
if grep -q 'shape-grandfathered' <<<"$under"; then
  report "(d) SHAPE under-ceiling: repo B's $TOK was silently grandfathered against repo A's baseline row -- the baseline key has no repo dimension (id:4839 dimension b)"
fi

if [[ "$fail" -eq 0 ]]; then
  echo "PASS: baseline rows do not cross repo boundaries (id:4839 dimension b)"
fi
exit "$fail"

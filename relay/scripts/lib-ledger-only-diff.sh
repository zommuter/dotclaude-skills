#!/usr/bin/env bash
# lib-ledger-only-diff.sh — ONE shared "does this commit range touch ONLY the
# id:c144-sanctioned ledger file set" predicate (id:88f0).
#
# Motivation (observed live 2026-07-28, run relay-20260728-105959-1379): the isolation
# gate (verify-isolation.sh, id:f682) false-positived on a repo whose main advanced via
# three id:c144-sanctioned ledger-only commits (ROADMAP promotion + inbox ingest stubs)
# — id:c144 explicitly exempts ledger-only writes from the relay lease and mandates
# doing them directly in the main checkout under flock (the documented `/relay human` /
# `/meeting` write-back path, id:15d5/2147). Two other filed consumers also want this
# exact classification: id:0f1e (classify-repo.sh's substantive_unaudited counting a
# ledger-only commit and producing same-run echo reviews) and routed:68d7 (the
# classifier should treat a ledger-only unaudited diff as audit-exempt so it cannot
# co-schedule a review against an execute round). Build it ONCE here (the
# lib-typed-edges.sh / lib-state-claim.sh "one engine, N callers" pattern) — this item
# (88f0) wires only the isolation-gate consumer; 0f1e/68d7 wire the other two
# separately, reusing this same function.
#
# Usage (source, don't execute):
#   source relay/scripts/lib-ledger-only-diff.sh
#   if ledger_only_diff "$repo_path" "$rev_range"; then …
#
# ledger_only_diff <repo-path> <rev-range>
#   <rev-range> is anything `git diff --name-only <rev-range>` accepts, e.g. "base..head".
#   Returns 0 (true, shell success) iff every changed path in the range is one of the
#   sanctioned ledger files below. Returns 1 (false) if the range touches anything else,
#   OR if the range is empty (an empty diff is NEVER vacuously "ledger-only" — id:88f0
#   fixture requirement: "an empty range → FALSE, never vacuously true").
#   Never mutates; a single read-only `git diff --name-only`.
LEDGER_ONLY_DIFF_FILES="TODO.md ROADMAP.md REVIEW_ME.md RELAY_LOG.md CHANGELOG.md"

ledger_only_diff() {
  local repo="$1" range="$2"
  local files
  files="$(git -C "$repo" diff --name-only "$range" -- 2>/dev/null || true)"
  [ -n "$files" ] || return 1   # empty range: never vacuously ledger-only

  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case " $LEDGER_ONLY_DIFF_FILES " in
      *" $f "*) ;;
      *) return 1 ;;
    esac
  done <<< "$files"
  return 0
}

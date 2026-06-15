# Strong-model audit — Run 7 (2026-06-15)

Recurring item id:401c. Window: `relay-ckpt-20260615-2129..HEAD` — the delta since
Run 6 (2026-06-15-1937b, window 1937..HEAD, which last audited up to and including
`7456e1f`, the `paused` filter). HEAD on arrival = `83d8614`.

## Window contents

```
83d8614 relay: warn on nested worktrees in gather-human-backlog (stale-checkout guard)
cb9c91b relay: checkpoint 20260615-2129                (non-code: ckpt commit)
```

`cb9c91b` is the pure checkpoint commit that closes Run 6's window (already
audited). **The only first-time-seen code change in this window is the
`warn_nested_worktrees` function added to `relay/scripts/gather-human-backlog.sh`
(`83d8614`).**

Diffstat (`git show 83d8614 --stat`): +28 lines in
`relay/scripts/gather-human-backlog.sh`, no other files.

## Pass 1 — code review

The added `warn_nested_worktrees()` and its call site in `scan_repo()`:

```bash
warn_nested_worktrees() {
  local name="$1" path="$2"
  git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  local main_wt nested
  main_wt="$(git -C "$path" rev-parse --show-toplevel 2>/dev/null)"
  [[ -n "$main_wt" ]] || return 0
  nested="$(git -C "$path" worktree list --porcelain 2>/dev/null \
    | sed -n 's/^worktree //p' \
    | { grep -vxF "$main_wt" || true; } \
    | { grep -F "$main_wt/" || true; } \
    | { grep -vE '/\.(claude|git)/' || true; } \
    | tr '\n' ' ')"
  if [[ -n "$nested" ]]; then
    printf 'WARN: %s has nested worktree(s) inside its checkout: %s— relay may be reading a STALE tree; relocate worktrees out of the checkout.\n' \
      "$name" "$nested" >&2
  fi
}
```

- **Correct & well-placed.** Called first thing in `scan_repo()`, before the
  REVIEW_ME/ROADMAP emission, so the warning precedes the per-repo TSV without
  interleaving with it. Non-git dirs early-return cleanly
  (`rev-parse --is-inside-work-tree ... || return 0`) — so the existing plain-dir
  fixtures in `test_relay_human.sh` (sections 1–3) stay silent, no false warnings.
- **`set -euo pipefail` safety is handled.** Every `grep` in the pipeline that can
  legitimately match nothing is guarded with `{ grep ... || true; }`, so an
  exit-1-on-no-match never trips `set -e`. The leading `rev-parse` redirects stderr
  and is `|| return 0`-guarded. Verified by running against a clean repo: exit 0,
  no output.
- **Prefix-match correctness.** The nested test is `grep -F "$main_wt/"` *with a
  trailing slash*, so a sibling worktree at `/path/repo-other` is NOT mis-flagged
  as nested under `/path/repo`. `grep -vxF "$main_wt"` (whole-line, fixed-string)
  correctly drops the main worktree's own entry. Both use `-F`, so a checkout path
  containing regex metacharacters cannot corrupt the match.
- **Exclusion list is right.** `grep -vE '/\.(claude|git)/'` drops ephemeral
  harness sandboxes under `.claude/` and git-internal worktrees under `.git/` —
  these are not the "stale operator layout" the warning targets, so excluding them
  avoids noise.
- **stdout/stderr separation correct.** The warning is `>&2`; the TSV stays on
  stdout. A downstream consumer parsing the TSV is unaffected.

**Finding F1 (fixed inline): the new warning shipped without a regression guard.**
This is the *same class* of gap Run 6 fixed for the `paused` filter — a new
behaviour-bearing feature with no test. `tests/test_relay_human.sh` had no
nested-worktree case. Fixed inline by adding **section (4)** to that test: a real
git repo with a worktree nested inside its checkout (asserts a stderr `WARN` naming
the nested path), a clean git repo (asserts silence — non-vacuous negative
control), and an assertion that the `WARN` never contaminates stdout. Verified
non-vacuous: neutering the `warn_nested_worktrees` call turns the new assertion red
(`0 passed, 1 failed`); restoring it returns the suite to 50/0.

## Pass 2 — security audit

No new attack surface.

- **No command injection.** No `eval`; every value (`$path`, `$main_wt`, the
  worktree paths) flows only into `git -C "$path"`, `grep -F`/`-vxF`/`-vE`, and a
  `printf` whose format string is a literal with `%s` placeholders. `-F` on the
  prefix/whole-line greps means even a path with grep-special characters cannot be
  interpreted as a pattern.
- **No path traversal / no new file I/O.** The function only *reads* git metadata
  via `git worktree list --porcelain`; it opens no files and changes no path
  resolution (resolution still happens in `own_repos()`, unchanged).
- **Trust boundary unchanged.** `path` originates from `relay.toml` (local,
  operator-controlled, already fully trusted by this script); worktree paths come
  from local git's own output. No network or untrusted input. No secrets, no file
  permission assumptions.

Nothing to fix.

## Pass 3 — design coherence

- **Directly addresses a real incident.** The commit message cites the
  ai-codebench 2026-06-15 case (main at top level, `claude/opusplan` in
  `./opusplan/`) where `/relay human` read a stale tree. This is the same stale-tree
  hazard tracked in the broader sync/divergence work (id:c3f7's origin-sync guard,
  id:3ac8's stale-worktree reaping). A *warning* (not a hard block) is the right
  altitude here: `gather-human-backlog.sh` is a read-only triage helper, so it
  surfaces the layout smell to the human rather than refusing to run — consistent
  with the "human as 3rd actor" framing of id:2892. No contradiction with the
  prune/reap machinery, which operates on the relay's *own* worktree cache, not on
  a repo's in-checkout nested worktrees.
- **No contradiction with other relay invariants.** The change is additive and
  read-only; it does not touch path resolution, the `own`/`clone`/`paused`
  filtering, or the TSV contract.
- **Cross-ledger state still coherent.** 0 open `[ROUTINE]`; 3 open `[HARD]` —
  id:401c (recurring-by-design, this item), id:414a (dispatchable; gate CLEARED in
  Run 4), id:3346 (GATED — parked in TODO, do not start). Matches Runs 5–6; this
  window added no roadmap items and closed none.

## Outcome

Window is **clean** — no correctness, security, or design-coherence defects. One
forward-robustness gap (the new `warn_nested_worktrees` shipped without a test)
**fixed inline** with a verified non-vacuous regression guard in
`tests/test_relay_human.sh` section (4). No new TODO/ROADMAP item required. Full
suite 50/0.

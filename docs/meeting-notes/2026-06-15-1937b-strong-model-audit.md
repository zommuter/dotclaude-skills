# Strong-model audit — Run 6 (2026-06-15)

Recurring item id:401c. Window: `relay-ckpt-20260615-1937..HEAD` (HEAD =
`cb9c91b`, checkpoint 20260615-2129). This window is the delta since Run 5
(2026-06-15-1937, window 1748..HEAD).

## Window contents

```
cb9c91b relay: checkpoint 20260615-2129          (non-code: ckpt commit)
7456e1f relay: honor `paused = true` in gather-human-backlog.sh own-repo filter
0b35c9f relay: checkpoint 20260615-1949          (non-code: ckpt commit)
d9708fc merge(relay): HARD id:401c audit run 5    (Run 5's own artifacts)
c3f13d1 relay(hard): C5 id:401c audit run 5       (Run 5's own artifacts)
```

Diffstat (`git diff --stat relay-ckpt-20260615-1937..HEAD`): 109 insertions
across 4 files — of which RELAY_LOG.md / ROADMAP.md / the Run-5 meeting note are
Run 5's already-audited deliverables and the two checkpoint commits are pure
state. **The only first-time-seen code change in this window is the 2-line
`paused`-filter addition to `relay/scripts/gather-human-backlog.sh` (7456e1f).**

## Pass 1 — code review

`gather-human-backlog.sh` `own_repos()` (the changed function):

```python
for name, entry in data.get("repos", {}).items():
    if entry.get("classification") != "own":
        continue
    if entry.get("paused"):          # added
        continue
    path = entry.get("path") or os.path.join(src, name)
    print(f"{name}\t{path}")
```

- **Correct & well-placed.** The new guard sits after the `classification ==
  "own"` gate and before path resolution, so a paused repo is dropped from the
  TSV the all-repos sweep consumes. `entry.get("paused")` is truthy only for an
  explicit `paused = true` (or any truthy TOML value); absent key → `None` →
  falsy → not skipped. No behavior change for existing repos that omit the key.
- **Dispatch interaction (intentional, not a bug).** The named-repo branch
  (`gather-human-backlog.sh repoX`) builds `PATH_OF` from `own_repos()`, which
  now excludes paused repos, then falls back to `$SRC_DIR/$name`. So an
  *explicitly named* paused repo is still scanned (via the default path). This
  matches the commit's stated scope — "skipped in relay **sweeps**" — an operator
  who names a paused repo on the command line gets it. Acceptable; documented
  here so a future reader doesn't mistake it for an inconsistency.
- No quoting/escaping issues: the change touches only Python dict access; no new
  shell interpolation, no new subprocess, no new file I/O. `set -euo pipefail`
  unaffected.

**Finding F1 (fixed inline): the filter shipped without a regression guard.**
The existing hermetic test `tests/test_relay_human.sh` (part 3) exercises own /
clone / @manual paths but had no paused-repo case, so the new contract was
untested. Fixed inline by adding a `repoD` fixture (`classification = "own"`,
`paused = true`, with an open REVIEW_ME box) and asserting it never appears in
the all-repos sweep. Verified the guard is non-vacuous: deleting the two filter
lines turns the new assertion red (`0 passed, 1 failed`); restoring them returns
the suite to 50/0.

## Pass 2 — security audit

No new attack surface. The change reads one additional TOML key
(`entry.get("paused")`) from `relay.toml`, a local operator-controlled config
already fully trusted by this script (it already drives path resolution and the
`own`/`clone` classification). No new command construction, no path traversal
(path resolution is unchanged), no injection vector, no secrets. `relay.toml`
remains the trust boundary it already was. Nothing to fix.

## Pass 3 — design coherence

- The `paused` flag is a clean, additive, opt-in convention: a key absence is
  the previous behavior. It supersedes the prose-only "ON HIATUS … skip in relay
  sweeps" comment that the commit message notes was being ignored (rawrora was
  swept despite it) — converting an unenforced comment into an enforced filter is
  the right direction.
- No contradiction with other relay invariants: the sweep-vs-named asymmetry is
  coherent (a human explicitly asking for a paused repo overrides the hiatus).
- Cross-ledger state still coherent: 0 open `[ROUTINE]`, 3 open `[HARD]`
  (id:401c recurring-by-design, id:414a dispatchable, id:3346 GATED). Matches the
  Run-5 finding; this window added no roadmap items and closed none.

## Outcome

Window is **clean** — no correctness, security, or coherence defects. One
forward-robustness gap (untested new filter) **fixed inline** with a verified
regression guard; no new TODO/ROADMAP item required. Suite 50/0.

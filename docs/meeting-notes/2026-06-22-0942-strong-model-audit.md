# Strong-model audit — Run 37 (2026-06-22 09:42)

ROADMAP id:401c — recurring code-review + security + design-coherence audit.
Run as an Opus-apex `[HARD — pool]` relay child (id:da26 hard-execute).

## Window

First-seen change since Run 36's own audit merge `b93f024`
(`b93f024..HEAD`, HEAD = checkpoint `relay-ckpt-20260622-0942` / `183a272`).

**SUBSTANTIVE CODE window** — breaks the Run 31/32/33/35/36 ledger-only streak.
`git diff --stat b93f024..HEAD`:

```
 Makefile                         |   6 +-
 RELAY_LOG.md                     |  20 ++++
 ROADMAP.md                       |  10 ++
 TODO.md                          |   2 +
 relay/scripts/roadmap-archive.sh | 167 ++++++++++++++++++++++++++++++++
 tests/test_roadmap_archive.sh    | 201 +++++++++++++++++++++++++++++++++++++++
 6 files changed, 403 insertions(+), 3 deletions(-)
```

First-seen code (`git diff --name-only b93f024..HEAD -- '*.sh' '*.py' '*.js' Makefile`):
- **`relay/scripts/roadmap-archive.sh`** (NEW, 167 L) — the Relay ROADMAP archiver, id:6b67
  ([ROUTINE], shipped by a Sonnet executor in commit `f6f594b`). Moves done `[x]` ROADMAP
  item-blocks → `ROADMAP.archive.md` under the same conservative prior-commit/≥30d gate as
  `todo-update/archive-done.sh`, no section pruning, flock-guarded.
- **`tests/test_roadmap_archive.sh`** (NEW, 201 L, `# roadmap:6b67`) — 9 hermetic cases.
- **`Makefile`** — registers `roadmap-archive.sh` in `relay_FILES`/`relay_EXEC`/`relay_ALLOW`.

Ledger changes in the window: ROADMAP id:6b67 spec'd + `[x]`; TODO id:93cc meta-issue
("Prompt is too long") + its id:6b67 child note; RELAY_LOG checkpoint paragraphs.

## Pass 1 — Code review (correctness)

**CLEAN — no inline fixes.** `roadmap-archive.sh` reviewed line by line:

- `set -euo pipefail`; root arg defaults to `git rev-parse --show-toplevel`; short stdout,
  details to `~/.claude/logs/roadmap-archive.log` — all per house conventions.
- **Trap ordering correct.** Two `trap … EXIT` statements; bash keeps only the last, and the
  final one cleans BOTH `$PRIOR_DONE_FILE` and `$LOCK_FILE`, so the earlier (lock-only) trap
  being overwritten is harmless — no temp/lock leak.
- **Prior-commit gate sound.** `git show "HEAD:$ROADMAP_REL"` (via `realpath --relative-to`)
  is grepped for `^- \[x\]` lines; an item is archived only if its stripped header line was
  already `[x]` in HEAD (prior-commit) OR carries a trailing `done YYYY-MM-DD` ≥30 d old.
  A working-tree-only tick is NEVER archived — verified by tests T3 (positive)/T4 (negative).
- **Block capture correct.** `is_continuation()` treats blank or leading-whitespace lines as
  continuations, and a new top-level `- [` bullet or `^#{1,6}\s` heading as a boundary; trailing
  blank lines are trimmed back to the gap. Multi-line blocks (sub-bullets + prose) move as one
  unit (T1) and the `<!-- id:XXXX -->` token survives verbatim (T8).
- **Header preservation / no pruning** verified — open items, `## ` headings, and the preamble
  are untouched; an emptied section heading is LEFT (T2, T9) — the deliberate contrast with
  `archive-done.sh` (ROADMAP headers are structural).
- **Idempotent** (T7): a second run with everything already archived is a clean no-op.
- **Heredoc safety.** Python body is a quoted heredoc `<<'PYEOF'` — no shell interpolation;
  all inputs (paths, cutoff, prior-done file) passed via `argv`, parsed with `pathlib`/`re`/
  `datetime`. No string-built shell from file content.

Suite: **81 passed, 0 failed, 0 expected-red** (was 80/0; +1 for `test_roadmap_archive.sh`).

## Pass 2 — Security

**CLEAN — no defects.**

- **No injection.** No `eval`; no shell built from ROADMAP content. The Python heredoc is
  quoted; `git -C "$REPO_ABS" show "HEAD:$ROADMAP_REL"` interpolates a `realpath`-derived
  relative path (trusted local repo, not attacker data). All `git -C` args quoted.
- **No path traversal beyond the repo.** Operates only on `$REPO_ROOT/ROADMAP.md` and
  `ROADMAP.archive.md`; `REPO_ROOT` is a CLI arg or `git rev-parse` (trusted local input,
  consistent with every sibling helper).
- **No secrets / no network / stdlib-only Python.** Reads/writes two markdown files + a log.
- **Lock file** `.roadmap-archive.lock` is covered by the gitignored `*.lock` glob — no
  accidental commit of the lock.

## Pass 3 — Design coherence

**Coherent.**

- **id:93cc → id:6b67 chain sound.** id:93cc is the TODO meta-issue (executor "Prompt is too
  long" on large-ROADMAP repos, hit live on ai-codebench's ~400-line ROADMAP); id:6b67 is
  fix-direction (b) — the ROADMAP archiver — promoted to ROADMAP as a `[ROUTINE]` executor
  unit. Single-id-two-views correctly maintained: id:6b67 carries the same token in both
  ROADMAP (`[x]`) and the TODO child note; id:93cc stays TODO-only (a design meta-issue, the
  durable fix-direction (a) "pass only OPEN items to the child" still tracked there). No
  duplicate-id minting.
- **Test maps its item** (`# roadmap:6b67`); the item's checkbox is `[x]` and the suite is
  fully green, satisfying the CLAUDE.md §Testing definition-of-done (ticked item ⇒ green).
- **gaming-scan clean** — the test file is wholly NEW (additions only); `git diff b93f024..HEAD
  -- tests/` shows no deleted assertions / added skips / removed `grep -q`/`[[ ]]` checks.

## Findings tracked / accepted (no inline fix)

1. **LOW (accepted) — lock-file unlink-race.** The `trap 'rm -f "$LOCK_FILE"'` removes the
   flock'd lock file while fd 9 is still held — a classic unlink-race (a concurrent run could
   create a fresh inode and both hold "the lock" on different inodes). The canonical house
   pattern (`append.sh`, `git-lock-push.sh`) does NOT `rm` the lock file; it leaves it
   persistent and just releases the fd. **Accepted, not fixed inline:** the script is `-n`
   non-blocking (a concurrent run cleanly *skips*, never corrupts), has NO automated caller
   today (manually-invoked tool — grep across the repo finds zero non-doc callers), and the
   operation is rare + idempotent + single-writer. The race is theoretical, not a live path.
   If/when an automated caller is added (e.g. an integrator post-merge archive step), drop the
   `rm "$LOCK_FILE"` from the trap to match the house pattern (leave the persistent lock file).

2. **Pre-existing (out of window, accepted) — two cross-ledger `[ ]`/`[x]` disagreements.**
   `orphan-scan.sh --cross-ledger` flags `id:78ff` and `id:d9b0` as TODO:[ ] / ROADMAP:[x].
   Both predate this window (NOT introduced by id:6b67) and are the intended single-id-two-
   views shape: the ROADMAP execution unit closed while the broader TODO *design ledger* entry
   legitimately stays open (id:78ff's TODO is the full lane-taxonomy umbrella with a residual
   cross-repo back-fill; id:d9b0's TODO is the "why" design item whose ROADMAP twin was the
   executor unit). Not drift from this audit window — noted, not actioned (audit scope = since
   last checkpoint).

## Coherence drift fixed inline (recurring Run 4/8/17/21–30/35/36 class)

- **1 fix** — the TODO id:401c MIRROR line still read "Latest ✓ Run 36 2026-06-22-0737";
  refreshed to **Run 37 2026-06-22-0942** with this window's verdict.
- **d5e0 summary line NOT stale this run** — it already reads "5 open ROADMAP items, all
  HARD" + "ZERO open ROUTINE items", which is correct after id:6b67 (the sole window ROUTINE)
  closed: re-derivation gives **0 open ROUTINE / 5 executable HARD** (401c [pool] / 3346
  [meeting] / dba3 [decision-gate] / 7809 [meeting] / 98f0 [meeting]) + de4e DEFERRED
  non-executable. No edit needed.

## Cross-ledger state (re-derived)

0 open ROUTINE / 5 executable HARD — id:401c [pool] / id:3346 [meeting] / id:dba3
[decision-gate] / id:7809 [meeting] / id:98f0 [meeting]; id:de4e DEFERRED non-executable; all
five open in both ROADMAP+TODO; d5e0 agrees (no count drift this run). The two pre-existing
single-id-two-views ROADMAP-closed/TODO-open umbrellas (78ff, d9b0) are intended, not drift.

Both tracked flakes (id:16e9, id:05e8) did NOT recur. Suite **81/0** on a clean run.

## Verdict

**CLEAN.** Substantive code window (roadmap-archive.sh + tests, 403 insertions) audited across
all three passes — no code or security defects, no design contradictions. 1 LOW finding
accepted with a documented future-fix trigger; 1 inline coherence drift (mirror line) fixed.
The new archiver is sound, well-tested, and faithfully mirrors the `archive-done.sh` gate while
correctly diverging on header-pruning (ROADMAP headers are structural).

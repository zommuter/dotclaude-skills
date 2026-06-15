# Strong-model audit — Run 4 (2026-06-15 17:59)

Recurring item id:401c. Window: `relay-ckpt-20260615-1748`..HEAD (the latest checkpoint
before this relay run, per the item's "diff against the most recent `*-ckpt-*` tag" rule).

## Window

```
bf70a52 statusline: make install checks CLI deps by functional severity (jq=error, rest=warn)
```

One commit. It adds `statusline/check-deps.sh` (40 lines), wires it into
`make install-statusline` + a standalone `make check-statusline-deps` target, and adds the
hermetic `tests/test_statusline_deps.sh`. (Checkpoints 1623/1712/1731 and their merged work
were already covered by Run 3, whose window header was `1559..HEAD` as of 17:45 and which
audited everything present at that moment.)

## Pass 1 — Code review

`statusline/check-deps.sh` reviewed line-by-line:

- **Empty-array expansion under `set -u`** — `for t in "${opt_missing[@]}"` with an empty
  `opt_missing` is **safe on bash 4.4+** (confirmed on the host: bash 5.3, `rc=0`). The repo
  targets modern bash; not a defect.
- **`declare -A why` + in-loop mutation** (`why[stat]=...`) — correct; keys are only read via
  `${why[$t]:-a feature}` with a default fallback, so a missing key can't error.
- **Severity classification is accurate** (verified against `statusline-command.sh`):
  `jq` is used 16× and parses every stdin field + the usage cache → genuinely CRITICAL;
  `bc` (9 sites) drives gradient colors + extrapolation; `curl` (1 site, L88) is the live
  fetch with a cache fallback; `sha1sum` (L25) drives hash colors; `stat -c %Y` (L68/78/339)
  drives cache-age. Every OPTIONAL tool degrades exactly one feature and the script's `why[]`
  text matches. The `command -v`/`stat -c %Y .` probe correctly distinguishes "no stat" from
  "BSD stat lacks -c".
- **Minor under-description (NOT changed)**: `stat -c %Y` is also used at L339 to gate the
  KV-cache-expiry display, not only cache-age; `why[stat]` names only "cache-age detection".
  Both degrade gracefully via the `2>/dev/null || echo 0` fallback, so the user-facing claim
  ("the bar still renders") holds. Cosmetic wording, not a correctness issue — **accepted as
  acceptable**, no change.

## Pass 2 — Security audit

`check-deps.sh` has **no injection surface**: it takes no arguments and reads no external
input; tool names are fixed literals iterated with `command -v`; there is no `eval`, no command
substitution on untrusted data, and the only interpolations into messages are the fixed tool
names and static strings (`pamac install jq`). The Makefile invocation
(`bash $(SRC_DIR)/statusline/check-deps.sh`) passes no user data. Runs robustly under a
stripped PATH (builtins + `command -v` only). **Clean — no finding.**

## Pass 3 — Design coherence

Swept the three currently-open `[HARD — strong model]` items:

- **id:401c** (this item) — recurring, correct by design.
- **id:3346** (sub-agent meeting simulation) — explicitly `GATED — do not start` (gate:
  opencode port + a >200k-ctx meeting). Gate has NOT fired. Correctly parked. No action.
- **id:414a** (Tier-B canary harness) — **coherence drift found.** The item's `**GATED**` line
  said "implement id:fa05 + id:dfaf first". Both shipped (done 2026-06-15): `relay/scripts/
  gaming-scan.sh` exists and `review.md` references it 3×, so the review procedure the harness
  invokes already delegates mechanical checks. The gate has fired but the prose still read
  GATED — a future strong session could have skipped a now-dispatchable item.
  **Fixed inline**: rewrote the line to "Gate CLEARED 2026-06-15 (audit run 4)…", noting the
  item stays HARD for fixture-craft judgment, not for an unmet dependency. The checkbox is
  **left open** (the harness itself is not built).

## Verdict

No code or security defects in the window. One design-coherence drift (id:414a stale GATED
marker) fixed inline. Item id:401c stays open (recurring by design); Run-4 log entry appended.
Full suite green (49 passed) on arrival and unchanged by this note + the two ROADMAP edits
(doc/prose only).

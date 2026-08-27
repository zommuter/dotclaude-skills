# Migration: kill the em dash as a lane-tag delimiter

**Status:** handoff spec. Nothing here is implemented. No delimiter was changed, no
ledger was touched, no checkbox ticked.

**Owner ruling (2026-08-27, not re-litigated here):** every structured tag where the
em dash is a DELIMITER becomes a plain hyphen — `[INPUT — meeting]` → `[INPUT - meeting]`,
`[INTENSIVE — local-llm]` → `[INTENSIVE - local-llm]`, `[HARD — pool]` → `[HARD - pool]`.
Bare `[HARD]` / `[ROUTINE]` / `[MECHANICAL]` have no delimiter and are unaffected.
Prose em dashes are a separate, later pass and are **out of scope**.

Two coupled changes: **(A)** the delimiter migration; **(B)** dropping the dual-vocab
blindness once (A) is complete.

---

## 0. The finding that shapes the whole plan

A big-bang delimiter flip is **not available**, for two independent reasons:

1. **Blast radius.** The em-dash delimiter appears in **18 files under `relay/scripts/`**,
   **26 markdown contract/doc files**, **86 test files**, `meeting/classify.sh`,
   `meeting/orphan-scan.sh`, `meeting/SKILL.md`, `Makefile`, two `docs/diagrams/*.mmd`,
   the tracker fixtures — plus 138 occurrences in `TODO.md`, 92 in `ROADMAP.md`, 140 in
   `TODO.archive.md`, 242 in `ROADMAP.archive.md`, 2 in `REVIEW_ME.md`. That cannot
   land in one Sonnet turn, and it cannot land atomically.
2. **The suite would go red in the middle.** The 86 test files are *fixtures* written in
   em-dash spelling. Flip the readers to hyphen-only and every one of them fails until
   the fixture seam lands. There is no ordering of a hyphen-only flip that keeps
   `tests/run-tests.sh` green between seams.

So the migration is **tolerant-read / canonical-emit**, mirroring how the id:4f02
vocabulary window was run:

- Readers accept **both** delimiters through an explicit, single-source alternation.
- Every **emitter** and every **stored** tag is rewritten to the hyphen.
- A new **detector** measures completion mechanically.
- Seam (B) then deletes the em-dash half of the alternation *and* the dual-vocab
  blindness, in one strictness commit.

**This is a recommendation, not a settled decision.** The alternative — a single
flag-day commit rewriting all ~500 files at once, no window, suite red in between — is
cheaper in seams and much riskier; the owner may prefer it. What is *not* optional is
that hazard 4 (readers that already silently absorb a partial migration) makes a window
safe **only if the detector exists first**. Seam S0 is therefore load-bearing under
either choice.

---

## 1. Hazard verification — what I found, including two corrections

Every hazard in the brief was checked against the code. Two are wrong.

| # | Hazard as briefed | Verdict |
|---|---|---|
| 1 | Silent-fallback landmine in 3 scrapers | **CONFIRMED, and worse than stated** — see below |
| 2 | `gather-repo-state.sh` maps new vocab BACKWARDS to old-vocab strings | **CONFIRMED** (`:337-351`) |
| 3 | `[INTENSIVE — <res>]` shares the delimiter, own hardcoded copies | **CONFIRMED** (`lane-convert.sh:152/160`, `gather-repo-state.sh:361/364/378`) |
| 4 | Some readers accept BOTH delimiters and absorb a partial migration | **CONFIRMED for 2 of 3; the third is WRONG** — see below |
| 5 | The ratchet may BLOCK the migration commit | **WRONG — refuted empirically** — see below |
| 6 | Emitters outside `relay/scripts/` | **CONFIRMED and INCOMPLETE** — the list is longer |
| 7 | Prose carve-out must survive | **CONFIRMED**, and `7a86cdb3` is the right anchoring |
| 8 | Cross-repo consumers reimplement the matching | **CONFIRMED** (named in `hard-lanes.md`'s own header) |

### Hazard 1 — confirmed, with a third silent reader

All three scrapers are em-dash-hardcoded and all three fall back to a hardcoded
em-dash vocabulary:

| Reader | scrape | fallback | on fallback |
|---|---|---|---|
| `relay/scripts/lane-convert.sh` | `:73`, `:81` | `:76`, `:84` | **SILENT** |
| `relay/scripts/roadmap-lint.sh` | `:131`, `:189` | `:135`, `:193` | warns twice |
| `hooks/pre-commit-lane-vocab.sh` | `:81`, `:89` | `:84`, `:92` | **SILENT** |

Reproduced: with `hard-lanes.md` flipped to hyphens and a ROADMAP holding
`- [ ] [HARD — pool] leftover old tag <!-- id:aaaa -->`:

```
$ lane-convert.sh --dry-run ROADMAP.md
- [ ] [HARD] leftover old tag <!-- id:aaaa -->      # rc=0, stderr EMPTY
```

The SSOT no longer contains `[HARD — pool]` anywhere, yet the converter still renamed
it — from the fallback set — and said nothing. `roadmap-lint.sh` at least printed
`WARNING — could not read lanes from …; using built-in fallback set` (twice).

This is the id:d35a silent-no-op class inside the tooling built to prevent it. The
fallbacks must be **deleted**, not updated: a fallback that merely gets a new delimiter
still makes a broken scrape look like a working one.

### Hazard 4 — one of the three named readers does NOT tolerate the target spelling

- `relay/scripts/mechanical-orphan-scan.sh:98` — `RES_RE = re.compile(r"\[INTENSIVE\s*[—-]\s*([^\]]+?)\s*\]")` — **tolerant, confirmed.**
- `relay/scripts/gather-human-backlog.sh:403` — `clean !~ /\[INPUT[[:space:]]*[—-]/` — **tolerant, confirmed.**
- `relay/scripts/todo-conformance.sh:144` — `[[ … == *'[HARD —'* || … == *'[HARD-'* ]]` — **NOT tolerant of the target spelling.** `'[HARD-'` has no space; the migration target is `[HARD - pool]` (space-hyphen-space), which matches **neither** arm. This is not a silent absorber; it is a *third* spelling that will silently start missing heading-items the moment a lane tag is hyphenated. It fails in the opposite direction from the one briefed, and it fails **loudly-in-effect** only if something notices the heading-detection change — nothing will. Treat it as a live defect, not a tolerance.

### Hazard 5 — WRONG, refuted empirically, and the truth is worse

`hooks/pre-commit-lane-vocab.sh` recognises a candidate tag from `all_lane_tags`
(**scraped**), but decides old-vocab-ness by looking it up in `old_vocab_replacement`
(`:101-105`), an associative array whose keys are **hardcoded with em dashes** and are
not derived from the scrape at all. The two halves disagree under any delimiter change,
in both directions:

- SSOT still em-dash → `all_lane_tags` has no `[HARD - pool]`; `first_lane_tag` returns
  `""` for a hyphen line → no block.
- SSOT flipped → `all_lane_tags` *has* `[HARD - pool]`, but the map key `[HARD — pool]`
  misses → no block.

Measured in a throwaway git repo, SSOT untouched:

```
### CASE 1: staged `- [ ] [HARD - pool] b <!-- id:bbbb -->`
exit=0                                   # no output at all
### CASE 2 (control): staged `- [ ] [HARD — pool] c <!-- id:cccc -->`
lane-vocab: BLOCKED — a staged (added) line introduces an old-vocab lane tag.
  [HARD — pool] → [HARD]    | - [ ] [HARD — pool] c <!-- id:cccc -->
exit=1
```

So the ratchet **will not block the migration commit**. It will silently stop working
during it. Do not plan a `--no-verify` escape hatch for a block that never happens;
plan a seam that makes the ratchet delimiter-agnostic (S3) *before* any ledger is
rewritten, or the migration disarms the fleet's only lane-vocab guard.

### Hazard 6 — the emitter list is longer than briefed

Beyond `meeting/classify.sh`, `meeting/orphan-scan.sh`, `meeting/SKILL.md`: `Makefile`,
`hooks/lane-vocab.claude-rule.md`, `docs/diagrams/meeting-classification.mmd`,
`docs/diagrams/relay-dispatch.mmd`, `tracker/ledger-map.py`, `tracker/SCHEMA.md`,
`tracker/fixtures/**`, `tests/shard-canary/**` (4 files incl. a baseline prompt),
`relay/SKILL.md` and eight files under `relay/references/`. The `todo-conformance.sh
--fix` claim holds: it mints ids only and never rewrites lane tags, so it needs the
delimiter *matching* change (hazard 4) and no vocabulary change.

### Hazard 7 — the carve-out and its anchoring

Confirmed necessary. `7a86cdb3` is the reference: rule 3(g) now anchors on
`leading_lane_run` (`roadmap-lint.sh:210-232`) — the contiguous run of recognised lane
brackets at the start of the item text, computed after backtick-quoted spans are masked,
with `[INTENSIVE - <res>]` resource brackets stripped first so a resource-FIRST item
does not stop the run dead. Its commit message records three real false positives that
the unanchored version produced (loderite affd, loderite 1e21, toesnail 8807), all of
them audit-trail prose. **Every strictness check in this migration uses that anchoring
and only that anchoring.** A global string ban would make it impossible to write the
history of this migration — including this document.

---

## 2. Seam decomposition

Ordered. Each seam is scoped to one Sonnet executor turn against a repo with a 384 KB
`TODO.md`; **no seam reads a ledger whole** — every ledger touch is `grep -n` to locate
then a line-scoped rewrite.

### S0 — the completion detector (`lane-delimiter-scan.sh`) — **must be first**

**Why first:** hazard 4 means a partial migration is silently absorbed and looks
identical to a finished one. Without a detector there is no rollback story, no seam-(B)
closing condition, and no way to tell a half-applied fleet from a done one.

**Artefact:** `relay/scripts/lane-delimiter-scan.sh`

```
usage: lane-delimiter-scan.sh [--live-only] <ledger-file>...
  prints  <file>:<lineno>: <tag>            per LIVE em-dash-delimited lane tag
  prints  <file>:<lineno>: <tag> (prose)    per backtick'd/trailing MENTION
  --live-only  suppresses (prose) lines and is the closing-condition mode
  exit 0 = no LIVE findings; nonzero = at least one
```

Liveness is decided **exactly** by `roadmap-lint.sh`'s `leading_lane_run` anchoring
(strip `[INTENSIVE - <res>]`/`[INTENSIVE — <res>]` brackets, mask backticks, take the
leading contiguous run). Reuse it — do not reimplement it.

- **Acceptance:** `tests/test_lane_delimiter_scan.sh` green. A migrated ledger that
  quotes old spellings in backticked prose reports **zero**; a half-migrated ledger
  reports exactly its live tags and exits nonzero; a lane bracket appearing *after*
  prose does not count.
- **Done-check (RED today):**
  `bash tests/test_lane_delimiter_scan.sh`
  → `FAIL: relay/scripts/lane-delimiter-scan.sh missing or not executable — the migration's closing-condition detector does not exist yet`, **exit 1**.
  This is an **unreached command**, not a genuine behavioural failure: the script does
  not exist, so nothing under test ran. Stated plainly because a green run of this spec
  after S0 only proves the *first* assertion was reached; read the PASS lines.
- **Context:** `relay/scripts/roadmap-lint.sh` (the `leading_lane_run` idiom, `:204-232`),
  `relay/scripts/lib-roadmap-sections.sh`, `tests/test_lane_delimiter_scan.sh`,
  `relay/references/hard-lanes.md`.

### S1 — SSOT + the three scrapers, **atomic**

Flip `relay/references/hard-lanes.md` to hyphen delimiters; change all six scrape
regexes to an explicit two-delimiter alternation (`\[HARD[[:space:]]*[—-][[:space:]]*…`);
**delete** all six hardcoded fallbacks and replace each with a loud non-zero exit.

- **Acceptance:** `hard-lanes.md` contains no em-dash *delimiter*; the three readers
  contain no hardcoded lane vocabulary; an unreadable/empty SSOT makes each reader exit
  nonzero with a message naming the doc path; `tests/run-tests.sh` still fully green
  (the alternation keeps every em-dash fixture working).
- **Done-check (RED today):**
  `bash tests/test_lane_delimiter_ssot_no_silent_fallback.sh`
  → `FAIL: relay/scripts/lane-convert.sh still carries a HARDCODED lane-vocabulary fallback … (grep: 76:  hard_lanes=$'[HARD — pool]\n… 84:  input_lanes=$'[INPUT — meeting]\n…)`, **exit 1**.
  **Genuine failure**, reached the assertion, with the offending lines quoted.
- **Context:** `relay/references/hard-lanes.md`, `relay/scripts/lane-convert.sh`,
  `relay/scripts/roadmap-lint.sh`, `hooks/pre-commit-lane-vocab.sh`,
  `tests/test_lane_delimiter_ssot_no_silent_fallback.sh`.

### S2 — `gather-repo-state.sh`: the backwards map and the INTENSIVE hardcodes

`:337-351` normalises the NEW vocabulary *backwards* into old-vocab strings
(`[HARD]` → `[HARD — pool]`, `[INPUT — meeting]` → `[HARD — meeting]`, …) so downstream
comparisons have one canonical value. The canonical value must become the hyphen
spelling, and the recognition list must accept both delimiters. Same file, `:361/364/378`,
carries `[INTENSIVE — ` in three `grep -P` patterns and one exclusion regex.

- **Acceptance:** `roadmap_primary_lane` returns the hyphen canonical form for every
  input spelling; `top_intensive` / `top_intensive_routine` / `top_intensive_hard` fire
  on both delimiters; `open_hard_pool` unchanged.
- **Done-check (RED today):** none of the existing specs pin the canonical *spelling*.
  Author the RED spec in this seam:
  `bash tests/test_gather_lane_canonical_delimiter.sh` — assert `roadmap_primary_lane`
  on a `[HARD - pool]` line returns the same canonical string as on `[HARD — pool]`.
  Today the hyphen input falls through the hardcoded `for tag in …` list at `:337` and
  returns the empty string. *This spec does not exist yet — writing it is part of S2,
  and its RED evidence must be captured before the fix, not after.*
- **Context:** `relay/scripts/gather-repo-state.sh`, `relay/scripts/classify-verdict.sh`,
  `relay/references/hard-lanes.md`, `tests/test_gather_lane_anchor.sh`.

### S3 — the ratchet becomes delimiter-agnostic — **before any ledger rewrite**

Derive `old_vocab_replacement` from the same SSOT scrape that populates `all_lane_tags`,
keyed on the **lane name**, not the delimiter byte.

- **Acceptance:** a newly added `[HARD - pool]` / `[HARD - meeting]` is blocked exactly
  as its em-dash twin is; bare `[HARD]` and `[INPUT - meeting]` stay unblocked; a
  backtick'd prose mention of old vocab on a human-lane item stays unblocked.
- **Done-check (RED today):**
  `bash tests/test_lane_vocab_ratchet_delimiter.sh`
  → `PASS: control: em-dash [HARD — pool] is blocked (rc=1)` then
  `FAIL: hyphen-delimited [HARD - pool] was NOT blocked (rc=0, out='', err='') — old-vocab-ness must key on the LANE NAME, not the delimiter byte`, **exit 1**.
  **Genuine failure with a passing control** — the control proves the hook ran and the
  fixture reached it, so the RED is behavioural, not an unreached command.
- **Context:** `hooks/pre-commit-lane-vocab.sh`, `relay/references/hard-lanes.md`,
  `tests/test_lane_vocab_ratchet_delimiter.sh`, `tests/test_lane_vocab_ratchet_hook.sh`.

### S4 — remaining `relay/scripts/` readers (bash) — 12 files

`classify-repo.sh`, `classify-verdict.sh`, `gather-human-backlog.sh`,
`lib-roadmap-sections.sh`, `mechanical-orphan-draft.sh`, `unpromoted-scan.sh`,
`todo-conformance.sh` (**including the `'[HARD-'` defect from hazard 4**),
`relay-doctor.sh`, `acquire-resource.sh`, plus `lane-convert.sh`'s `[INTENSIVE — ]`
regexes at `:152/160`. Every match site becomes the two-delimiter alternation.

- **Acceptance:** `git grep -nE '\[(HARD|INPUT|INTENSIVE)[[:space:]]*—' relay/scripts/*.sh`
  returns only comment/doc lines, never a match pattern; suite green.
- **Done-check (RED today):** that grep currently returns match patterns in 12 files —
  e.g. `todo-conformance.sh:144`, `gather-human-backlog.sh` — **genuine**, the command
  runs and finds them.
- **Context:** the 12 scripts (do them in two batches of 6 if the turn gets long),
  `relay/references/hard-lanes.md`.

### S5 — non-bash relay consumers — `relay-loop.js`, `drain.mjs`, `handback-guard.mjs`, `handback-followup.py`, `backtest-historical.py`

Separate seam because a template-string change in `relay-loop.js` is the
`loop-crash-class` runtime hazard: `node --check` + grep do not catch it.

- **Acceptance:** `node --check relay/scripts/relay-loop.js`; the exec-smoke guard
  (id:5bac/aec5) passes; suite green.
- **Done-check (RED today):** `git grep -nE '\[(HARD|INPUT|INTENSIVE) — ' relay/scripts/*.js relay/scripts/*.mjs relay/scripts/*.py` returns matches — **genuine**.
- **Context:** the five files, `tests/test_relay_loop_structure.sh`.

### S6 — `meeting/` + `Makefile` + `hooks/lane-vocab.claude-rule.md`

`meeting/classify.sh` (the lane floor at `:101-128`), `meeting/orphan-scan.sh`,
`meeting/SKILL.md`, `Makefile`, the rule doc.

- **Acceptance:** `meeting/classify.sh` routes `[INPUT - meeting]` → C3,
  `[INPUT - decision]` → HUMAN, `[INPUT - access]`/`[INPUT - author]` → HANDS,
  `[HARD - pool]` → POOL, identically to their em-dash twins; suite green.
- **Done-check (RED today):** `git grep -nE '\[(HARD|INPUT) — ' meeting/` returns
  matches in all three files — **genuine**.
- **Context:** `meeting/classify.sh`, `meeting/orphan-scan.sh`, `meeting/SKILL.md`,
  `Makefile`.

### S7 — contract docs (26 markdown files)

`relay/references/*.md` (8), `relay/SKILL.md`, `ARCHITECTURE.md`,
`docs/diagrams/*.mmd` (2), `tracker/SCHEMA.md`, `hooks/lane-vocab.claude-rule.md`.
**Historical `docs/HANDOVER-*.md` and `docs/meeting-notes/**` are NOT migrated** — they
are the record of what was written when, and rewriting them destroys exactly the audit
trail hazard 7 protects. Same for `CHANGELOG.md` and `*.archive.md` prose.

- **Acceptance:** every *normative* doc reads the hyphen spelling; every *historical*
  doc is byte-identical; `tests/test_hard_lane_buckets.sh` (marker-set cross-check
  against `hard-lanes.md`) green.
- **Done-check (RED today):** `git grep -lE '\[(HARD|INPUT|INTENSIVE) — ' relay/references/ ARCHITECTURE.md` returns 9+ files — **genuine**.
- **Context:** `relay/references/hard-lanes.md`, `relay/references/conventions.md`,
  `relay/references/human.md`, `ARCHITECTURE.md`.

### S8 — test fixtures (86 files) — split into 3 batches

Purely mechanical: rewrite the delimiter inside fixture heredocs and assertion strings.
Batch by prefix (`test_classify_*`, `test_gather_*`/`test_relay_*`, the rest, plus
`tests/shard-canary/**` and `tracker/fixtures/**`).

- **Acceptance:** after each batch, `tests/run-tests.sh` is **519 passed / 0 failed /
  1 expected-red** plus the new specs.
- **Done-check (RED today):** `git grep -lE '\[(HARD|INPUT|INTENSIVE) — ' tests/ tracker/fixtures | wc -l` → **86+** — **genuine**.
- **Context:** one batch's files only; never open all 86 in one turn.

### S9 — this repo's own ledgers

`TODO.md` (138), `ROADMAP.md` (92), `REVIEW_ME.md` (2). **Live tags only** — a
backtick'd audit-trail mention stays em-dash. `TODO.archive.md` (140) and
`ROADMAP.archive.md` (242): live tags on archived items are still *live tags* by the
seam-(B) closing condition, so they migrate too; their prose does not.

**These are shared non-union ledgers.** The rewrite goes through
`meeting/md-merge.py --update-sections` / `relay/scripts/commit-ledger.sh`, never `Edit`,
never `sed -i` — the flock is the point.

- **Acceptance:** `lane-delimiter-scan.sh --live-only TODO.md ROADMAP.md REVIEW_ME.md
  TODO.archive.md ROADMAP.archive.md` exits 0.
- **Done-check (RED today):** that command — **unreached today** (S0 has not built the
  script). Its pre-S0 stand-in, `grep -c '\[HARD — \|\[INPUT — \|\[INTENSIVE — '`, gives
  `TODO.md:138 ROADMAP.md:92 TODO.archive.md:140 ROADMAP.archive.md:242 REVIEW_ME.md:2` —
  a **superset** including prose, which is precisely why the stand-in cannot close the
  seam and S0 must exist.
- **Context:** `relay/scripts/lane-delimiter-scan.sh`, `meeting/md-merge.py`,
  `relay/scripts/commit-ledger.sh`.

### S10 — **(B)** drop the dual-vocab blindness and the em-dash tolerance

Gated on the closing condition in §6. Delete the em-dash arm of every alternation; make
a live old-delimiter or old-vocabulary lane tag a **LOUD error** (nonzero) in
`roadmap-lint.sh`, `gather-human-backlog.sh` and the ratchet; delete the ratchet's
grandfathering of pre-existing lines; close the id:4f02/8111 dual-vocab window in
`hard-lanes.md`.

- **Acceptance:** a live `[HARD — pool]` or `[HARD - pool]` anywhere is an ERROR, not a
  WARN; a **backtick'd prose mention of either remains silent** — this is the assertion
  that must not regress.
- **Done-check:** authored in S10; it cannot be RED today because the code it inverts is
  the code S1-S9 build.
- **Context:** `roadmap-lint.sh`, `hooks/pre-commit-lane-vocab.sh`,
  `relay/references/hard-lanes.md`, `relay/scripts/lane-delimiter-scan.sh`.

---

## 3. Ordering and parallelism

```
S0 ──► S1 ──► S2 ──► S3 ──┬──► S4 ──┐
                          ├──► S5 ──┤
                          ├──► S6 ──┼──► S8 (a,b,c) ──► S9 ──► S10
                          └──► S7 ──┘
```

- **S0 → S1 → S2 → S3 is a strict chain.** S1 must not land before the detector exists
  (no way to observe the result). S3 must land before S9, or rewriting the ledgers
  disarms the ratchet silently (hazard 5's real form).
- **S4, S5, S6, S7 are mutually parallel** — disjoint files, all gated on S3.
- **S8 batches are parallel with each other** but must follow S4-S7 (fixtures assert
  against reader behaviour).
- **S9 after S8**; **S10 last**, gated on §6.
- **One unit per repo per round** (dc5b C2) applies: S9 touches shared non-union
  ledgers, so it never runs concurrently with any other dotclaude-skills unit.

---

## 4. The atomicity boundary

**MUST be one commit (S1):**

- `relay/references/hard-lanes.md` delimiter flip
- the six scrape regexes in `lane-convert.sh`, `roadmap-lint.sh`,
  `pre-commit-lane-vocab.sh`
- **deletion** of all six hardcoded fallbacks

Splitting these leaves a window in which the SSOT reads new and all three readers
silently enforce old — the exact reproduction in §1. Deleting the fallbacks in the same
commit is what converts the failure mode from silent to loud; a follow-up commit is
too late, because the intervening state is unobservable.

**MAY follow in separate commits:** everything else. S2-S9 are individually revertible
and, because the readers tolerate both delimiters throughout, none of them can break the
suite on its own.

**MUST NOT be bundled:** S10 with anything. The strictness flip is the one change that
turns latent half-migration into a hard failure fleet-wide; it gets its own commit and
its own revert.

---

## 5. Rollback / half-applied detection

Hazard 4 is exactly why "the suite is green" does not mean "the migration finished".
Two readers already absorb both spellings, so a stalled migration is invisible.

**The mechanical half-applied test:**

```bash
# per repo — nonzero means live em-dash lane tags remain
relay/scripts/lane-delimiter-scan.sh --live-only \
  TODO.md TODO.archive.md ROADMAP.md ROADMAP.archive.md \
  REVIEW_ME.md REVIEW_ME.archive.md
```

Three distinguishable states:

| `--live-only` exit | `git grep -lE '\[(HARD\|INPUT\|INTENSIVE) — ' relay/ meeting/ hooks/ tests/` | meaning |
|---|---|---|
| nonzero | non-empty | **not started / in progress** |
| **0** | **non-empty** | **HALF-APPLIED** — ledgers migrated, code not (or vice versa). This is the dangerous state and the one hazard 4 hides. |
| 0 | empty | complete for this repo |

**Rollback:** each seam is a single commit touching disjoint files; `git revert <sha>`
per seam, in reverse order, is sufficient — *except* S1, which must be reverted whole
(reverting only the doc restores the silent-fallback window). S9's ledger rewrite is
reverted through `commit-ledger.sh`, not a bare revert, because concurrent ledger writes
may have landed on top.

---

## 6. Seam (B): the closing condition

**Not** "zero occurrences of the em-dash string" — that would ban writing the history of
this migration, which is hazard 7 and which this document itself violates by design.

**Closing condition:** *zero **LIVE** old-delimiter or old-vocabulary lane tags across
every relay own repo, INCLUDING archive ledgers*, where "live" is
`leading_lane_run`-anchored after backtick masking and resource-bracket stripping — the
anchoring `roadmap-lint.sh` rule 3(g) adopted in `7a86cdb3`.

**The command that decides it:**

```bash
#!/usr/bin/env bash
set -uo pipefail
cd ~/src/dotclaude-skills
source relay/scripts/lib-own-repos.sh          # provides own_repos()
rc=0
while IFS= read -r repo; do
  [[ -d "$repo" ]] || continue
  files=()
  for f in TODO.md TODO.archive.md ROADMAP.md ROADMAP.archive.md \
           REVIEW_ME.md REVIEW_ME.archive.md; do
    [[ -f "$repo/$f" ]] && files+=("$repo/$f")
  done
  [[ ${#files[@]} -eq 0 ]] && continue
  relay/scripts/lane-delimiter-scan.sh --live-only "${files[@]}" || rc=1
done < <(own_repos)
exit $rc
```

Exit 0 **licenses S10**. Exit nonzero names every remaining live tag by
`file:line: tag`. Two properties that make this the right gate and not a proxy: it
reads the **own-repo set from `relay.toml` via `own_repos()`**, never a `~/src/*` glob
(the improvised-sweep trap); and it counts **live tags**, never string occurrences, so
audit-trail prose about the migration never blocks its own completion.

**It is a recommendation, not a licence.** Exit 0 is evidence the owner may act on;
S10 still needs his ratification, because it is the irreversible half.

---

## 7. Proving run

1. **dotclaude-skills first.** After each seam: `tests/run-tests.sh` must read
   **519 passed / 0 failed / 1 expected-red** (the baseline on `main` at `7a86cdb3`)
   plus the seam's own new specs. Any other number stops the seam.
2. **After S9,** run the §6 command scoped to dotclaude-skills alone; it must exit 0.
3. **Then the fleet,** repo by repo, S9-equivalent only (their code is this repo's, via
   symlink — only their ledgers need migrating). Use the relay pool one repo per round.
4. **S10 last,** after the §6 command exits 0 fleet-wide **and** the owner ratifies.

The `relay-ckpt-*` tag at each seam close is the rollback anchor.

---

## 8. Cross-repo consumers — route, never edit

`hard-lanes.md`'s own header names `project_manager`'s `scan.py` as the second consumer
that MUST agree on the marker set, and relay-core carries a shadow binary that
reimplements `classify-verdict.sh`/`gather-repo-state.sh` semantics — parity goes RED
there the moment S2/S4 land. Both are **other repos**. File them:

```bash
~/.claude/skills/meeting/append.sh new-id     # mint ID1, then:
~/.claude/skills/meeting/append.sh -t inbox -e \
  "- [ ] [project_manager] scan.py lane-tag matching must accept the hyphen delimiter \`[HARD - pool]\`/\`[INPUT - meeting]\`/\`[INTENSIVE - local-llm]\` alongside the em dash — hard-lanes.md names scan.py as the second consumer that must agree, and tests/test_hard_lane_buckets.sh cross-checks the marker set (from dotclaude-skills em-dash delimiter migration, seam S4) <!-- routed:ID1 -->"

~/.claude/skills/meeting/append.sh new-id     # mint ID2, then:
~/.claude/skills/meeting/append.sh -t inbox -e \
  "- [ ] [relay-core] shadow binary reimplements classify-verdict.sh/gather-repo-state.sh lane matching — parity goes RED when dotclaude-skills seams S2/S4 land the hyphen delimiter; bash stays authoritative (from dotclaude-skills em-dash delimiter migration) <!-- routed:ID2 -->"
```

Mint the ids with `append.sh new-id` — **never invent tokens**. Both lines are single
conforming entries (checkbox + `[target]` + `routed:XXXX`), per the inbox contract.

---

## 9. RED specs delivered with this document

| File | Seam | RED evidence |
|---|---|---|
| `tests/test_lane_delimiter_scan.sh` | S0 | `FAIL: relay/scripts/lane-delimiter-scan.sh missing or not executable …`, exit 1 — **unreached command** (script absent) |
| `tests/test_lane_delimiter_ssot_no_silent_fallback.sh` | S1 | `FAIL: relay/scripts/lane-convert.sh still carries a HARDCODED lane-vocabulary fallback …`, exit 1 — **genuine**, quotes lines 76 and 84 |
| `tests/test_lane_vocab_ratchet_delimiter.sh` | S3 | `PASS: control: em-dash [HARD — pool] is blocked (rc=1)` then `FAIL: hyphen-delimited [HARD - pool] was NOT blocked (rc=0, out='', err='')`, exit 1 — **genuine, with a passing control** |

All three are hermetic (`mktemp -d`, no `~/.claude`, no network) and carry no
`# roadmap:` header — they trace to a TODO item, so their failures always count.

The ratchet spec initially produced a **false PASS**: `git checkout -- ROADMAP.md`
between cases left the previous case's line in the *index*, so every later case
re-tested the first one. It now does `git reset --hard HEAD` and asserts the staged diff
contains the line under test before invoking the hook. Recorded because it is the
unreached-fixture trap in a harness I wrote myself, and the fix is what makes the
control meaningful.

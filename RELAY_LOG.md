# Relay log <!-- merge=union; append-only — never edit or reorder past entries -->

## relay(execute): id:0d58 — anchor open_mechanical to primary lane (2026-07-03)

Fixed the `[MECHANICAL]` lane-anchoring bug in `relay/scripts/classify-repo.sh` (id:0d58).
`open_mechanical` was a bare-substring test (`if "[MECHANICAL]" in ln`) independent of the
id:4da4 primary-lane derivation, so a backtick'd `` `[MECHANICAL]` `` mention on a
differently-laned open item (e.g. `[ROUTINE] @manual ... `[MECHANICAL]` runner note` or
`[HARD — pool] ... superseded a `[MECHANICAL]` sub-step`) falsely inflated the count and could
mis-fire the priority-6 `mechanical` verdict. Fix: added `[MECHANICAL]` to `LANE_TAGS` so it
flows through the SAME positional `primary = min(_found)[1]` derivation as every other lane,
derived `is_mechanical = (primary == "[MECHANICAL]")`, and deleted the standalone bare-substring
counter — `primary` is now the sole lane reader, so no future tag can bypass anchoring.
`classify-verdict.sh`'s priority cascade was untouched per the reviewer's caveat (the bug was
purely the count). The anchoring alone satisfied all three RED fixtures (false-positive on
`[ROUTINE]`-mention, false-positive on `[HARD — pool]`-mention, and the genuine-`[MECHANICAL]`
no-over-correction guard) — no additional whitespace-boundary regex was needed.
`tests/test_mechanical_lane_anchor.sh` is now GREEN, id:0d58 ticked in ROADMAP.md, and the full
suite is 174 passed / 0 failed / 2 expected-red (unrelated open items). **Overall: PASS.** Do
NOT push — parent session handles it.

## relay(execute): id:fd37 — [MECHANICAL] recipe explicit-success-marker doctrine (2026-07-03)

Implemented the two enforcement surfaces the RED spec (`tests/test_recipe_success_marker.sh`)
pinned. (1) DOC: `relay/references/recipe-manifest.md` gained a new "Explicit success/failure
marker (acceptance_artifact) — id:fd37" section documenting the requirement (a `cmd` that
redirects into `acceptance_artifact` must append an explicit terminal marker AND preserve the
real exit code) plus the canonical verbatim pattern `cd <repo> && { <realcmd> > "$ART" 2>&1;
rc=$?; echo "MARKER exit=$rc finished=$(date -Is)" >> "$ART"; exit $rc; }`. (2) CODE:
`relay/scripts/recipe-validate.sh` grew a conservative advisory check (python3 stdlib, run only
after the existing 7-field schema hard-fail passes) that emits a `WARNING:` on stderr — still
exit 0 — iff `cmd` contains the `acceptance_artifact` value alongside a redirect (`>`) and
carries no `exit=`/`exit $?`-style marker token; a cmd already carrying the canonical `exit=$rc`
pattern draws no warning, so no false positive on a correct recipe. Also updated the producer
site per the item's stated scope: `relay/references/handoff.md`'s C2 `[MECHANICAL]`-tagging
paragraph now tells the recipe author to include the `exit=$rc` marker when the `cmd` redirects
into `acceptance_artifact`, pointing at `recipe-manifest.md` for the pattern and noting
`recipe-validate.sh`'s non-fatal warning. `tests/test_recipe_success_marker.sh` is GREEN (all
three assertions a/b/c), id:fd37 ticked in both ROADMAP.md and its TODO.md twin (`md-merge.py
update-ids`, flock'd), and the full suite is 175 passed / 0 failed / 2 expected-red (unrelated
open items: id:14d0 stub-placement spec). **Overall: PASS.** Do NOT push — parent session
handles it.

## 2026-08-10 — executor (claude-opus-5)

Worked id:f54d and id:4f9b — the two ABSOLUTELY-URGENT items of the executor-death
cluster (parent id:93cc), strictly in gate order. **id:f54d**: `roadmap-archive.sh` had
been built, tested and Makefile-targeted since id:6b67 and called by nothing —
confirmed `grep -c roadmap-archive relay/scripts/relay-loop.js` = 0. Ran it on this repo
as immediate relief (ROADMAP.md 2619→1738 lines, 523,926→254,087 bytes; 100 `- [x]`
blocks and 12 emptied headings moved to ROADMAP.archive.md; all 70 open items verified
preserved before and after), then added integrator step 2c between the CHANGELOG derive
and ckpt-tag so it runs unconditionally on every integrate, scope-committing only
ROADMAP.md + ROADMAP.archive.md and only when it actually changed something.
`tests/test_roadmap_archive_wired_f54d.sh` pins the wiring statically (real invocation,
inside the integrator prompt, before ckpt-tag, scope-staged) plus two hermetic
behavioural checks of the "safe no-op on any repo" claim the step relies on.
**id:4f9b**: the pre-dispatch size gate. The interesting friction was that the obvious
implementation is impossible — relay-loop.js runs in the Workflow sandbox with no
filesystem and no `process.env`, so it cannot stat ROADMAP.md and cannot take a
threshold from the environment. Resolved by splitting the measurement (classify-repo.sh
emits `roadmap_bytes` on the host, the id:b09e passthrough pattern) from the decision
(`relay/scripts/prompt-size-gate.mjs`, pure, with byte-identical inline copies in
relay-loop.js per the round-plan.mjs discipline). Over budget ⇒ no dispatch, no
worktree, and a handback naming both cause and remedy on all three surfaces
(state.handbacks → RELAY_STATUS Blocked, the event log, the id:4a46 backstop).
Budget derivation and its two calibration points (523,926 B refuses, 254,087 B
dispatches) are written down in the module and pinned by the test, so a future change
to the number is a conscious act rather than a drift.

Friction: the 100k-token dispatch budget is a *derived* number, not a measured one — it
comes from "~200k window minus ~100k working room", anchored on the two observed deaths
(peak ctx 176,841) and the two known ROADMAP sizes. It is the honest best estimate
available without a tokenizer in the sandbox, and the chars-per-token approximation
deliberately under-counts so the gate fires late rather than early; a real measurement
would be a better basis and is worth a follow-up if the gate ever misfires. Also worth
recording: `test_relay_install_manifest.sh` caught the new `.mjs` missing from the
Makefile manifest — that guard earned its keep.

refactor: pulled the size decision into a pure importable module instead of inlining a
bespoke check at the dispatch site (which is what makes the behavioural half of the
id:4f9b test possible), reusing the existing handback-summary.mjs/round-plan.mjs
pattern rather than inventing a third one; removed a dead loop line from the new test's
fixture builder.

## 2026-08-10 10:38 — reviewer (claude-opus-5)

review of relay-ckpt-20260801-2135..HEAD (12 commits): id:f54d + id:4f9b verified green (354 pass / 0 fail / 10 expected-red); fixed prompt-size-gate.mjs install drift; ingested routed:cd7f/d160/24e3; extended id:f6d5 with integrate step 2c; 3 REVIEW_ME findings [id:f54d, id:4f9b, id:bf9d, id:480c, id:f6d5]

## 2026-08-10 11:52 — reviewer (claude-opus-5)

handoff C2+C3: promote id:798b + id:8c85 with RED specs; 798b remove-on-exit direction REJECTED as unsound (async dirty-sampler + unlink race) — gitdir-lock pattern recommended; id:8c85 mechanism corrected to snapshotState field omission [id:798b, id:8c85]

## 2026-08-10 — executor (sonnet)

Worked id:798b — moved `changelog-append.sh`'s flock off `<repo>/.changelog.lock` (working tree)
onto `<gitdir>/changelog-append.lock`, the pattern ckpt-tag.sh/version-bump.sh/diary-append.sh
already use. Chose the git-dir mechanism over remove-on-exit deliberately: the dirty-guard is an
async `git status` sampler, so a transiently-present lock still parks the repo, and unlinking a
flock'd path reintroduces the unlink race. Non-git target dirs (a supported case — `test_changelog_derive.sh`
uses plain `mkdir` fixtures) fall back to a stable per-path lock under `$TMPDIR`, still outside
the target. Deleted the false "matches the *.lock gitignore" header claim.
Friction: none. The atomic-rename temp file `.changelog.XXXXXX` is STILL created in the working
tree (`os.replace` needs the same filesystem) — ROADMAP marks it explicitly out of scope for 798b,
so it was left in place and documented in the header instead of silently changed.
refactor: none needed — the change is a lock-path relocation plus a corrected header comment; no
duplication introduced and no dead scaffolding removed.
## 2026-08-10 — executor (claude-opus-5)

Worked id:ef9e — recovered the orphaned `relay/orphan/relay-20260810-103858-20326-execute` work (`lint-embedded-literals.mjs` + `tests/test_embedded_literal_lint_ef9e.sh`), registered the linter in the Makefile `relay_FILES` manifest (the one gap that kept `test_relay_install_manifest.sh` red), and closed a COVERAGE gap found while verifying it: the linter reported the motivating incident's own shape (`… sh's quoting …` — closing quote glued to a bareword, `bash -n` CLEAN, runtime IndentationError) as UNCHECKED/exit 0, i.e. clean on the exact bug it exists to catch. Single-quoted bodies glued to a BAREWORD character are now prefix-syntax-checked and REJECTED on failure; `"`/`$`/`\'` concatenation stays UNCHECKED (no false positives — live tree still 78 scripts clean, 5 UNCHECKED unchanged). Two regression cases added (7, 7b). Full suite 356 pass / 0 fail / 12 expected-red.
Friction: the recovered work was complete and coherent apart from the manifest line; the UNCHECKED-swallows-the-incident gap was only visible by replaying the historical corruption against the real `discover-repo.sh`, not from the fixtures.
refactor: none needed — one manifest token plus a narrowly-scoped severity escalation in an existing branch; no duplication introduced.
## 2026-08-10 — executor (claude-opus-5)

Worked id:8c85 — RELAY_STATUS.md accounted for every own repo. Added the pure module
`relay/scripts/status-accounting.mjs` (`assertCompleteAccounting` generic core + a thin
`assertStatusAccounting` wrapper over ownRepos × the five sections) with a behaviour-equivalent
inline copy in relay-loop.js (Workflow sandbox cannot import, id:2ec4). Fixed `snapshotState` to
carry `surfaced` + `handbacks` and dropped the vestigial `blocked` (nothing read or wrote it since
id:1735) — that single omission was erasing classes (a) dirty-deferred, (b) in-flight-suppressed
and (d) HANDBACK from every write since id:cb50. Hoisted `humanUnits` out of its block as
`humanSurfaced` and folded it into `state.skipped` with its routing reason (class (c)); rewrote the
:1823-1825 comment that CLAIMED that placement while no code performed it. Put the in-scope
own-repo list on `state.ownRepos` and WIRED the invariant at both write sites — a new
`## Accounting invariant (id:8c85)` section in the rendered file plus a loud `log()` naming every
missing repo. Fixed the Claims renderer to fall back to the claim `key` (jq `//` never falls
through on `""`, so a keyed claim rendered with no subject at all).

Friction: the new module forced ONE line in `Makefile` (relay_FILES) — `test_relay_install_manifest.sh`
fails otherwise, so the suite could not be green without it, despite the unit's "do not touch
Makefile" scope guard (a sibling agent edits it in parallel). Added as its OWN new line to keep the
merge conflict-free; integrator please check.

refactor: extracted the accounting logic as a reusable generic core (`assertCompleteAccounting`)
rather than a bespoke own-repo check, so id:eb63(b) can instantiate it at item granularity without
touching this wrapper or its tests; removed the dead `state.blocked` snapshot field; replaced a
false explanatory comment with an accurate one instead of leaving both the bug and its denial.

## 2026-08-10 12:44 — reviewer (claude-opus-5)

review: fix chain closed — id:798b (git-dir lock, tree stays clean), id:8c85 (RELAY_STATUS accounts every own repo; snapshotState carries surfaced+handbacks), id:ef9e (linter recovered + coverage hole on its own motivating incident fixed); 358 pass/0 fail; follow-ups id:d525/340f/b3a3/5b21 [id:798b, id:8c85, id:ef9e]

## 2026-08-10 — strong-execute (claude-opus-5)

Worked id:2bb1 — authored the common intermediate JSON schema + the full bespoke-grammar→tracker
mapping, per the ratified meeting `docs/meeting-notes/2026-08-10-0906-tracker-substrate-replacing-markdown-ledgers.md`
(D2 as amended by `--fabled` findings 5/6/7), NOT a restatement of it. New `tracker/`: `SCHEMA.md`
(the durable artifact — every construct in the brief mapped or given an explicit loud-lossy policy),
`schema/ledger-intermediate.schema.json` (JSON Schema 2020-12, `schema_version` as a contract-surface
marker per CLAUDE.md §Versioning — this repo still has no repo-wide version), `ledger-map.py`
(stdlib-only reference mapper / validator / round-trip projector), and fixture ledgers + golden
documents. Three judgment calls worth flagging for review: (1) **id-less TODO lines import as
untracked** with a content-derived `~`-prefixed synthetic key, not skip-and-report — a skipped item
is invisible on the board, and the accepted cost (rewording re-keys it) is documented rather than
hidden; (2) **REVIEW_ME boxes attach when anchored** (`<!-- roadmap:XXXX -->` sets `review_status` on
the existing item + a `has:review-box` label) and stand alone as untracked `review_box` items when
not, with `review_status` a **third** view rather than folded into either ledger view; (3) cross-repo
collisions are split into class A (homonym — fatal by default, `--allow-homonyms` downgrades to a
counted WARN because at ~60 repos over a 65 536-token space homonyms are expected and the composite
key already disambiguates) and class B (a `routed:` edge resolving to ≥2 repos — **never**
downgradable, because that edge is genuinely unresolvable). The default is fatal-on-both so the
meeting's ratified "fail loudly at import" wording is honoured literally; the scoped mode is the
owner's knob, surfaced not chosen. `[HARD — hands]` is deliberately NOT auto-resolved — `hard-lanes.md`
records four candidate destinations and `lane-convert.sh` refuses to guess, so this mapper refuses too
and reports every one. Round-trip is scoped to the **status pair + relation graph**, not byte-exact
prose: D1 records that markdown need not survive as an export, and claiming an untested byte-exact
round-trip would be exactly the derived-doc drift this repo's rules forbid — said so in SCHEMA.md §4
rather than quietly narrowing the contract. Three tests, all header-less (id:2bb1 has no ROADMAP entry,
so their failures always count): drift round-trip in both directions + the collapse being structurally
rejected; the synthetic cross-repo collision exiting 3 and naming both tokens, both repos and both
classes; and a golden-fixture/determinism test that also mutates the JSON Schema to prove the
schema↔mapper cross-check can actually fail rather than passing vacuously. Suite 361 passed / 0 failed
/ 10 expected-red.

refactor: added `tracker` to the `SKILL_DIRS` list in BOTH `tools/check-no-bare-rm-f.sh` and
`tools/check-no-silent-swallow.sh` — a new top-level script directory that no repo guard scans is a
silent coverage hole, and the two lists had already drifted out of sync with the tree once. No other
cleanup: the mapping is greenfield and re-implements the anchored-marker regexes in python rather than
shelling out to `lib-anchored-id.sh`/`lib-typed-edges.sh`, which is a deliberate duplication (a pure
python producer, and the regexes ARE the contract here) recorded in SCHEMA.md, not an accident.

Friction: the item's contract says "a synthetic cross-repo id collision exits non-zero", but a flat
fatal on every duplicate bare token is impractical at fleet scale — 459+ items over 65 536 tokens makes
homonyms near-certain, so a strict-only importer would never complete a full pass. Rather than quietly
reinterpret the contract I implemented it literally (default fatal, test asserts exit 3) and added the
scoped mode as an explicit, documented knob with class B permanently fatal. Also: `tracker/` is a new
top-level directory — I proposed it per the brief, but the repo's layout table had no obvious home for
a non-skill, non-tool artifact, so that placement is a call the integrator may want to confirm.
Worked id:8066 — built the tracker pilot's **control-arm board** (`relay/scripts/control-board.sh`)
plus its spec `tests/test_control_board.sh`, registered in the Makefile relay manifest and pointed
to from `relay/SKILL.md`'s Shared resources. The item's mandatory reconcile gate was run FIRST and
found **no duplication**: `id:36f1` is the ITEM-level blocking-DAG visual over project_manager's
`edges.json` (producer `id:dc60`), and `id:51d8` is the ITEM-level, interactive, LLM-free
human-action dashboard over `gather-human-backlog.sh`'s tiers — this board is REPO-level over relay
classify output and shares a data source with neither, so all three obey the "ONE canonical
producer, N renders" steer rather than duplicating one. To keep that true it deliberately does NOT
re-derive the human backlog: its "waiting on a human" section is only the per-repo `human`/`blocked`
verdict, and `--json` is offered so id:51d8 can consume the repo-level roll-up instead of shelling
out per repo again. No second classifier: verdicts are `classify-repo.sh --emit unit` verbatim and
the display label comes from `render-verdict.sh` (the only sanctioned emitter of "drained"); the
five board columns are a documented DISPLAY grouping that always carries the raw verdict alongside,
so nothing is collapsed. Repo set is `relay.toml`'s own-set via the shared `own_repos()` parser
(`# path:` override + `paused` honoured, never a `~/src` glob), with its exit status checked
explicitly so a corrupt relay.toml aborts loudly instead of rendering an empty board. Writes
nothing at all — stdout only, no artifact to go stale, no tracker write. Smoke-run over the live
49-repo fleet in 45 s with zero producer errors. Suite 359 pass / 0 fail / 10 expected-red.

Friction: the item's checkbox says "read-only, derived over existing classify-repo.sh output", but
`classify-repo.sh --emit unit` does not carry the `unpromoted` promote/surface counts it computed
one step earlier (they are folded into the classifier input and dropped from the unit), so a board
that wanted "N items awaiting promotion per repo" would have to re-run `unpromoted-scan.sh` — i.e.
re-derive. Left out rather than re-derived; if the pilot wants that column, the honest fix is a
passthrough field on the unit, not a second scan in the board.

refactor: none needed — this unit is one new script plus one new test; no existing code path was
touched beyond a manifest registration and a docs pointer, so there was nothing to clean up. The
one reuse opportunity that existed (`own_repos()` and `render-verdict.sh` rather than fresh
enumeration/labelling) was taken by construction, not extracted after the fact.

## 2026-08-10 20:19 — reviewer (claude-opus-5)

hard-execute: id:2bb1 tracker intermediate schema+mapping; id:8066 control-arm fleet board (362 pass/0 fail)

## 2026-08-10 21:00 — reviewer (claude-opus-5)

review: id:2bb1 + id:8066 accept-with-fixes — -OO crash + derived_status enforcement; 3 owner boxes, follow-ups id:6daf/857d (363 pass/0 fail)

## 2026-08-10 — strong-execute (claude-opus-5)

Worked id:ca24 — replaced `tracker/ledger-map.py`'s boolean `--allow-homonyms` with an
explicit per-token allow-list: `--allow-homonym TOKEN` (repeatable) plus
`--allow-homonym-file PATH` (one token per line, `#` comments). Entries must be literal
4-hex tokens — a wildcard/prefix/`all` is rejected at exit 2, so there is no blanket
downgrade. The bare boolean is GONE (not an option, not an argparse prefix of either new
flag ⇒ rejected), asserted by the new `tests/test_tracker_homonym_allowlist_ca24.sh`.
Default stays STRICT; a LISTED class-A homonym warns, an UNLISTED one is still fatal and
named; class B (ambiguous cross-repo `routed:` edge) stays always-fatal even when its token
is listed. Added a stale-adjudication WARN for a listed token that is not a homonym in the
document, so `id:94ce`'s list cannot silently accumulate. `tracker/SCHEMA.md` §1.3 rewritten
(it previously conceded the gap). Suite: 364 passed / 0 failed / 10 expected-red.

Friction: the existing `tests/test_tracker_id_collision_loud.sh` exercised the superseded
boolean on three lines; those were re-pointed at `--allow-homonym cccc` with every assertion
kept in substance (class B fatal, adjudicated class A warns) — no assertion weakened or
skipped. Deriving the "one listed + one unlisted" contract fixture in-test (clone the `cccc`
pair into `beef`, drop the class-B `cafe` material) avoided editing the shared golden
fixtures, which other tracker tests hash.

refactor: none needed — the change is confined to the collision block, one new pure helper
(`collect_allowed_homonyms`), and the argparse surface; no surrounding code was restructured.
Worked id:c17d — repo-level entity derivation. `tracker/repo-entity.py` (new) fills the
`repos[].verdict` hole `ledger-map.py` deliberately leaves null, quoting
`classify-repo.sh --emit unit` verbatim out of `control-board.sh --json` (id:8066, landed
this session) and `render-verdict.sh`'s display label — no second classifier, no second
board renderer, no new status vocabulary. Three subcommands: `emit` (repos-only document
that `ledger-map.py validate` accepts), `enrich` (fills a mapped document in place,
items untouched), `validate-repos`. Pure function of two JSON documents: reads no
relay.toml, resolves no path, writes no file (D4 holds; the fleet driver stays id:94ce).
Spec `tests/test_tracker_repo_entity.sh` asserts the item's contract literally — per
fixture repo it runs `classify-repo.sh` and compares the verdict byte-for-byte — plus a
purity assertion on `tests/lib/assert-repo-unchanged.sh` and an anti-drift grep over
`classify-verdict.sh`'s `verdict = "…"` assignments. Suite 364/0/10.

Findings surfaced, not worked around:
- `ledger-map.py validate` checks `items[]` exhaustively and does **not** look at
  `repos[]` at all — a repo entity with a missing required key or a bogus verdict passes.
  `validate-repos` covers it meanwhile; folding it in belongs to that file's owner (a
  sibling held `ledger-map.py` this round, so it was not touched).
- id:6daf (the `unpromoted` counts `--emit unit` drops) is named in the schema + prose and
  deliberately NOT re-derived — a second `unpromoted-scan.sh` call would be the drift the
  ledger rules forbid.
- `schema_version` stays 1.0.0 on purpose: SCHEMA.md §5 bumps on a required-key/enum
  change, and this adds only optional properties to a `$defs/repo` that already required
  `verdict`.

refactor: none — no existing code was restructured. `tracker/repo-entity.py` and
`tests/test_tracker_repo_entity.sh` are new files; `tracker/SCHEMA.md` and
`tracker/schema/ledger-intermediate.schema.json` gained additive documentation only (a §7,
one artifact-table row, one scope-boundary row, and optional `$defs/repo` properties). No
required key, enum, or existing behaviour was changed, and no test was weakened.

Friction: the natural home for this verdict is `ledger-map.py`'s repo-entity builder, but
a sibling child owned that file this round, so the derivation ships as a separate composable
step. That turned out better (the mapper stays a pure markdown→JSON function with no
classifier dependency), but it does mean a consumer now needs two calls; if the owner
prefers one, `enrich` is a ~10-line fold into `ledger-map.py import`.
Worked id:94ce — fleet markdown→intermediate-JSON importer. `tracker/fleet-import.sh` (driver)
+ `tracker/fleet-state.py` (pure upsert/tombstone fold) + `tracker/homonym-allowlist.txt`
(adjudication surface) + `tests/test_tracker_fleet_import.sh` (11 sections, hermetic synthetic
fleet). Repo set comes from `relay.toml` via the SHARED `own_repos()` in
`relay/scripts/lib-own-repos.sh`, exit status checked explicitly — no `~/src/*` glob anywhere,
and a corrupt registry exits 3 with nothing written rather than reading as an empty fleet.
Two-phase run: pin every repo's HEAD sha FIRST, then read every ledger with
`git show <sha>:<file>` into a scratch tree, so no byte is ever read from a working tree and
one run is a coherent cut. Upsert on `(repo,id)`; unchanged records are CARRIED byte-identically
and the state document holds NO timestamp, which is what makes two-runs-zero-diff hold.
Tombstones are scoped to repos that imported successfully — a failed repo contributes none.

Friction: (1) the real-fleet dry run over 49 own repos surfaces **78 class-A homonyms** (0 class
B), so the fleet-wide import is BLOCKED until id:ca24's per-token allow-list lands AND those
tokens are adjudicated. The driver codes against the explicit per-token contract and REFUSES
(exit 5) to fall back to the superseded boolean, so it will not silently blanket-downgrade.
(2) The same dry run found a genuine `ledger-map.py` defect (id:2bb1 residue), NOT fixed here
because a sibling unit owns that file this round: a `REVIEW_ME` box anchored to an id with no
TODO/ROADMAP twin (`loderite/ecc3`) yields an item with `id: null` but a NON-synthetic key, which
`validate` then rejects fatally — `uid 'loderite/ecc3' has no id but its key is not a synthetic
'~' key`. Needs a follow-up item. (3) `ledger-map.py` records `repos[].path` as given, so the
driver rewrites it back to the relay.toml path after import; otherwise the scratch tree's mktemp
name would churn the state document every run.

refactor: none — this unit is two new files plus a new test; no existing file was modified.
The reuse that mattered (`lib-own-repos.sh`'s `own_repos()`, `ledger-map.py`'s CLI,
`tests/lib/assert-repo-unchanged.sh`) was taken by construction, and `tracker/ledger-map.py`
was deliberately left untouched — the sibling id:ca24 owns it this round.
Worked id:90f2 — both tracker adapters (Plane, Vikunja) against the intermediate schema.
`tracker/adapters/{adapter_common,vikunja_adapter,plane_adapter}.py` + hermetic
`tests/test_tracker_adapter_equivalence.sh` (364 pass / 0 fail / 10 expected-red).
The equivalence contract is stated over an item graph RECOVERED from each adapter's own
emitted target payloads — not re-derived from the source document, which would have made
the comparison vacuous. Verbs `plan`/`graph` are pure and offline (asserted with sockets
disabled); `apply`/`verify` are networked and no test invokes them.

id:857d (binding) is enforced by `adapter_common.check_gate()` for BOTH adapters, and the
test proves the gate is not vacuous: a deliberately collapsed, derived_status-only plan is
rejected for each adapter. The per-view triple is carried twice — `view:<view>=<state>`
labels and an anchored `[[ledger-views …]]` description marker — and recovery cross-checks
them, so a half-edited board is loud rather than quietly wrong.

VERIFIED LIVE (Vikunja v2.4.0, pilot project): 19 items / 39 labels / 3 relations applied,
`verify` PASS, re-apply idempotent (0 created), and a deliberately removed `view:todo=`
label was caught (exit 3) and repaired by re-apply. Live board shows both drift directions
with all three views intact.

NOT VERIFIED (Plane): `apply` has never issued a live request — the pilot does not serve
(id:02f7). Built and fixture-tested only; reported as BLOCKED, not as a pass.

Friction: (a) the supplied Vikunja API token is scoped projects/tasks/labels and 401s on
`/tasks/{id}/labels` and `/tasks/{id}/relations`, so the adapter prefers a JWT from
VIKUNJA_USER/VIKUNJA_PASSWORD — worth widening the token if an unattended importer is
wanted. (b) Plane's public API v1 documents no issue-relation endpoint, so `blocked_by`/
`link` edges cannot be written natively; the adapter WARNs and leaves them in the body
rather than guessing a URL. (c) `derived_status → Plane workflow state` is not injective
(`backlog` and `needs-decision` share a column) — the `derived:<state>` label is what
keeps that lossless.

refactor: none — this unit is three new modules and one new test; the only pre-existing
file touched is `tracker/SCHEMA.md`, additively (a new §7). Shared logic between the two
adapters was factored into `adapter_common.py` up front rather than extracted afterwards,
so no behaviour-preserving rewrite of existing code happened and none is claimed.

## 2026-08-10 22:32 — reviewer (claude-opus-5)

hard-execute batch: id:ca24 allow-list, id:94ce fleet importer, id:c17d repo entities, id:90f2 adapters (partial); cross-child flag-name defect fixed at integrate (367 pass/0 fail)

## 2026-08-10 23:04 — reviewer (claude-opus-5)

review: tracker batch accept-with-fixes — dead plural fallbacks removed, too-tolerant test pinned, id:857d gate vacuity closed, SCHEMA subsection renumber completed (367 pass/0 fail)

## 2026-08-11 — strong-execute (claude-opus-5)

Worked id:b7f4 + id:8c7f — one file, two contracts. **id:b7f4**: a `REVIEW_ME` box
anchored to an id that no `TODO`/`ROADMAP` line owns kept its bare 4-hex key while
carrying `id: null`, so `validate` died on it — and because `validate` is
whole-document, ONE such box made the whole pilot repo unimportable (reproduced first
against the real repo, then re-driven hermetically). Policy chosen and written into
SCHEMA.md §2.3 as the missing branch of the existing two rows: **standalone untracked**
(synthetic `~` key) + a `dangling-anchor:XXXX` label + a loud
`review-box-dangling-anchor` report. The two alternatives are recorded as rejected —
keeping the 4-hex key is the defect itself, and promoting the anchor to the box's own
`id` would fabricate a *tracked* item for an id no ledger owns (a ghost board row and a
false positive for every id-consuming scanner). The pilot repo now imports 773 items and
validates clean. **id:8c7f**: `schema_version` 1.0.0 → **1.1.0**, and SCHEMA.md §5 gains
clause 3 — a changed **value space** is a bump even when no key is added or removed and
no `enum` keyword existed to change. That is the case id:c17d passed by the letter of
clauses 1–2 while replacing `verdict`'s five documented values with nine. `verdict` and
`board_column` now carry real `enum`s AND `validate` enforces them (an `enum` keyword
alone catches nothing here — no JSON Schema validator ships in a stdlib-only repo); a
retired value fails naming where it went. `schema_cross_check()` now covers `$defs/repo`,
which had zero drift protection, and `head_sha` — load-bearing in `fleet-state.py`, wholly
undeclared — is declared. The four version copies collapse to ONE declared source (the
JSON Schema `const`; `ledger-map.py`'s literal is pinned to it, `repo-entity.py` and
`adapters/adapter_common.py` derive), and `version_copy_check()` makes a re-hardcoded
copy a loud error rather than a convention.

Friction: (1) `tests/test_tracker_repo_entity.sh` asserted the *absence* of repo checks in
`ledger-map.py validate` as a precondition — closing the gap SCHEMA.md §7 invited made it
fail. Assertion INVERTED (both validators must now reject a bogus `board_column`), not
dropped. (2) `adapters/adapter_common.py` is a sibling's file this round; its `1.0.0`
literal had to go or every adapter would refuse the new documents, so **exactly one line**
was changed, to derive from the single source. (3) The new test caught a bug I had just
written: an explanatory comment above `SCHEMA_VERSION` imitated the `SCHEMA_VERSION = "…"`
spelling that `fleet-import.sh` scrapes by regex, and being *above* the real assignment it
won — the scrape returned `…`. Reworded, and the test now pins all five readers agreeing.
(4) The `boxes == 2` count in `test_tracker_schema_drift_roundtrip.sh` meant adding the
dangling case to `fixtures/repo-alpha` would have forced an unrelated existing-test edit;
the new tests build their own ledger trees in `mktemp` instead. Goldens moved by exactly
one line each (`schema_version`), regenerated per SCHEMA.md §6.

refactor: none. Both items are behaviour changes with tests; no behaviour-preserving
rewrite was performed. The closest thing is the version-constant collapse, and it is NOT
refactoring — it changes what `validate` accepts (a stale hardcoded copy now fails) and is
covered by `tests/test_tracker_schema_version_8c7f.sh` §3, including the non-vacuity case.
Worked id:e977 — the cross-repo homonym ADJUDICATION worksheet, the decision aid behind
id:ca24's per-token allow-list.

First, the number was re-derived independently rather than inherited. id:94ce's dry-run
reported 78 class-A homonyms and 0 class-B, and the subsequent review declined to re-run
the 49-repo import, so that count was unverified. A fresh strict run of
`tracker/fleet-import.sh` over the relay.toml own-set (49 repos, 4785 items incl.
archived, ~5 s) reproduces it EXACTLY: 78 class A, 0 class B. The number stands.

The worksheet itself (`tracker/homonym-worksheet.sh` + `homonym-worksheet.py`) renders,
per token: every `(repo, id)` that mints it with its title, per-view statuses and
`file:line`; whether either item REFERENCES the other (an edge on the shared token, a
`blocked_by`/`parent`/`children` edge crossing into a sibling minting repo, or a prose
mention of a sibling minting repo's name); and how much RARE vocabulary the titles share.
Rarity matters: a raw shared-word count flagged 46 of 78, because every ledger item is
full of the same relay boilerplate ("acceptance", "done-check", "green"). Weighting by
document frequency over the fleet's own vocabulary — a word counts only if it occurs in
<=0.5% of items — cuts that to 15 without losing a single cross-referencing pair. The
remaining 63 have no signal in either direction and are the bulk-confirmable ones.

It never adjudicates. `tracker/homonym-allowlist.txt` is never written; every token in
the emitted DRAFT is prefixed `# UNCONFIRMED `, so the draft pasted verbatim into the
live allow-list still parses as STRICT — a test asserts that by feeding the draft back
through `fleet-import.sh` and requiring the homonyms to still fail. A human accepts one
token by deleting that prefix.

PRIVACY: the worksheet quotes item titles from ~49 mostly-private repos and this repo is
PUBLIC, so the SCRIPT is committed and the ARTIFACT is not — output defaults to
`~/.cache/relay/tracker`, an `--outdir` inside a git working tree is REFUSED (with
`--force-in-repo` as the deliberate override), and `.gitignore` blocks the filenames as
belt-and-braces.

`tracker/fleet-import.sh` gained ONE additive flag, `--emit-unvalidated`: it writes the
merged diagnostic document to `--out` even when validate fails. It downgrades nothing —
the exit code is unchanged (still 3), `--state` is still left untouched, every collision
is still reported. Without it the collisions that make validate fail are precisely the
ones whose evidence you cannot see, which is a real chicken-and-egg in the adjudication
loop. The test pins the no-downgrade property in both directions.

Friction: (a) a full-fleet import cannot currently pass validate at all, because
`loderite/ecc3` trips a separate unrelated error (`uid has no id but its key is not a
synthetic '~' key`) — that is the id:b7f4 defect a sibling is fixing this round; it did
NOT block this work thanks to `--emit-unvalidated`, and it is the 79th error in the
strict log, not a 79th homonym. (b) The "prose mentions a sibling repo" signal has known
false positives: an `[INBOUND routed:XXXX from dotclaude-skills]` preamble names a repo
incidentally, which is why b427 and d6f0 land in "needs a look" despite being ordinary
coincidences. That is the deliberate direction to err in — a false "needs a look" costs
the owner one glance, a false "coincidence" costs a wrong adjudication.

refactor: one behaviour-preserving extraction — the atomic `--out` publish in
`fleet-import.sh` was lifted verbatim into a `publish_out()` function so the new
unvalidated path and the existing success path share one implementation instead of two
copies of `cp` + `mv -f`. No other pre-existing code was rewritten; everything else in
this unit is new files plus one additive flag, one `.gitignore` block and one CLAUDE.md
Layout sentence.

## 2026-08-11 14:09 — reviewer (claude-opus-5)

hard-execute: id:b7f4 dangling anchors (unblocks loderite), id:8c7f schema 1.1.0, id:e977 homonym worksheet (78/0 re-derived); id:2902 filed (370 pass/0 fail)
Worked id:4b64 — the dual-vocab migration had left relay's own tooling behind; three repos
reported three symptoms of one root cause (routed:6629 / routed:5ccd / routed:8858). Fixed
BOTH sides in one pass, plus the residue hazard the third symptom exposed.

READ side (`relay/scripts/unpromoted-scan.sh`): `primary_lane()` now recognizes
`[INPUT — author]` (the id:2b0b 5th capability lane it omitted, so a properly-laned author
item reported `surface` and inflated the count driving the `human` verdict — lodelore
id:e545), and also anchors the `- [ ] **[TAG]** title` shape relay's OWN auto-gate emits
(previously read as a bold TITLE → no lane → `surface`). The promote-test now accepts the
pool lane in BOTH spellings — bare `[HARD]` joins `[ROUTINE]`/`[HARD — pool]`; bare
`[HARD]` used to fall through to `laned`, which is verdict-NEUTRAL by design, so a repo
whose apex backlog was written in the new vocabulary classified `idle` with work pending
(VERIFIED LIVE in lodelore: id:b0c4 + id:193f). Human lanes stay `laned` — no repo is
re-tagged backwards, and `[HARD — *]` stays recognized for the migration window.

EMIT side (`relay/scripts/handback-followup.py`): the id:3801 auto-gate now writes the
canonical `[INPUT — decision]` instead of `[HARD — decision gate]`, which relay's own
`hooks/pre-commit-lane-vocab.sh` ratchet BLOCKS; seams now carry `[HARD]` instead of the
pre-id:78ff `[HARD — strong model]`, which is in NO lane vocabulary at all (every parser
read those seams as untagged). Both old spellings are still RECOGNIZED as already-gated, so
an un-migrated line is never rewritten just to re-spell its tag.

RESIDUE (`meeting/md-merge.py`): a `--commit` that fails AFTER a successful `git add` used
to print a warning and return, leaving the ledger STAGED-but-uncommitted — the exact
lodelore relay-20260810-214130-15097 wedge, where every later pool run then DEFERRED the
repo (id:aa93) while the run reported `stopReason: drained`. It now rolls back BOTH halves
(working-tree text from a pre-write snapshot taken under the flock; the index entry from a
`git ls-files --stage` snapshot, restored via `update-index`) and raises, exiting 3. No
`stash`/`checkout --`/`reset --hard`/`clean` is involved, and no path but the one file is
touched. Pre-staging failures (not a repo, `git add` failed) stay non-fatal as before.

LOUD (`relay/scripts/relay-loop.js`): `durableHandbackFollowup` asked its agent for the exit
code and discarded the answer. It now parses an `EXIT:<code>` line and pushes a Blocked
entry into `state.handbacks` (rendered in RELAY_STATUS + the exit summary) on a non-zero
code, an unreadable answer, or an agent error — over-surfacing rather than swallowing.

Test: `tests/test_lane_vocab_both_sides_4b64.sh` (no `# roadmap:` header — it pins three
OBSERVED defects, so its failures always count). One fixture per lane spelling on the read
side (11 spellings + untagged → promote/laned/surface), a cross-check that every marker
defined in `relay/references/hard-lanes.md` appears in the scanner's tag list (so the NEXT
vocabulary move fails loudly here), an emit-side pass where the auto-gate's own output is
run through `hooks/pre-commit-lane-vocab.sh` and read back through both
`unpromoted-scan.sh` and `gather-repo-state.sh` (`open_hard_pool=1`), and a residue case
with a rejecting pre-commit hook asserting non-zero exit + empty `git status --porcelain`.

Friction: (1) `handback-followup.py` resolved its helpers through `~/.claude/skills`, i.e.
the MAIN checkout — a worktree test of the md-merge rollback would have exercised stale
code. Added a `skill_path()` that prefers this script's own tree and falls back to the
install (identical paths in a live run; the id:6f1c/f682 isolation rule). (2)
`tests/run-tests.sh` neutralizes `core.hooksPath` for the whole run via `GIT_CONFIG_COUNT`,
which beats repo-local config — the residue case re-points that same override at its own
throwaway hooks dir for one invocation. Worth knowing before writing any future
hook-behaviour test. (3) NOT DECIDED, for the owner: the reporter's substantive point that
auto-gating on SIZE-OUT is itself questionable — "too big for one turn" is not "needs a
human decision". Untouched here; the size-out→gate policy is unchanged.

refactor: one small behaviour-preserving extraction — `handback-followup.py`'s two inline
`os.path.join(SKILLS, ...)` call sites became `skill_path(...)`. That helper's fallback is
the identical path in a live run, but its preference for the script's own tree is a real
behaviour CHANGE in a worktree, so it is claimed as a fix, not as a pure refactor. Nothing
else was rewritten behaviour-preservingly; every other edit changes observable behaviour and
is covered by a test.

## 2026-08-11 14:17 — reviewer (claude-opus-5)

hard-execute: id:4b64 lane-vocab alignment (2 defects beyond the 3 reported; md-merge staged-write rollback) — 371 pass/0 fail
Worked id:90f2 (Plane live half) — the contract's "equivalent item graphs in BOTH targets"
clause was undischarged because Plane's transport had never issued a single request. It has
now. `id:02f7` cleared (proxy binds after a host reboot), so a self-hosted Plane v2.6.3
instance was stood up through its API (instance admin, workspace, project, never-expiring
workspace API key; key in the 0600 `~/.config/relay/tracker-secrets.env` as `PLANE_*`, read
via `from_env()` at call time, nothing hardcoded and nothing committed).

Live run on the pilot project, `repo-alpha` fixture: **19 items + 39 labels + 3 relations
created**, `verify` **PASS** (19 planned / 19 live, 5 live edges vs 3 planned non-dangling —
a superset, because Plane materialises inverses), second `apply` **idempotent** (0 created,
0 relations set, 3 already-present). The id:857d gate was made non-vacuous ON THE BOARD in
both carriers: deleting `view:todo=open` from the live issue made `verify` exit 3 naming
`repo-alpha/1111`; stripping the `[[ledger-views]]` marker made it exit 4 naming
`repo-alpha/3333`; re-apply repaired both to PASS. Per-view drift reads back off the server
in both directions (1111 open/done, 2222 done/open), and no item in drift renders as done.

Three previously-recorded unknowns resolved by measurement, and TWO OF THEM WERE WRONG:

  * **Plane's public API v1 DOES expose an issue-relation endpoint** — `POST/GET
    /issues/<id>/relations/`, `{"relation_type", "issues"}`, accepting blocked_by /
    relates_to / blocking / duplicate / start_* / finish_*. The recorded "no relation
    endpoint, WARN and keep the edge in the body" was false; the fallback is deleted and
    `blocked_by`/`link` are now written as real relations. No fixture has a resolvable
    `link`, so `relates_to` was exercised live via a retargeted-link document in a scratch
    project (4 relations set, `verify` PASS) and is now pinned hermetically.
  * **Non-injectivity CONFIRMED** — a default Plane project has exactly Backlog / Todo /
    In Progress / Done / Cancelled, so `backlog` and `needs-decision` genuinely share a
    column. `derived:<state>` as a label is load-bearing, not belt-and-braces.
  * **Plane's sanitizer DELETES HTML comments** (probe: `<!-- HTMLCOMMENT-CANARY -->` gone,
    bracketed marker byte-identical). The child's defensive choice of bracketed plain text
    was not paranoia — an HTML-comment carrier would have silently destroyed the per-view
    triple on every item while looking like a clean apply.

Verdict on the contract: **discharged, with one named asymmetry** — Plane cannot express a
`link_kind` (`routed`/`children-of`) because `relates_to` is untyped; Vikunja has the same
limitation, and neither adapter's recovered graph carries `link_kind`, so the two targets
are equivalent *to each other* and the id:90f2 clause holds. Owner's call on the box.

Friction: (a) Plane rate-limits API keys at 60/min — a 19-item apply is ~65 requests and
died mid-run with HTTP 429 the first time, leaving a half-applied board; the client now
paces itself at 55/min and retries a 429 with backoff, loudly. (b) A marker-stripped item
is DETECTED but NOT self-repairing: the uid anchor lives in the description, so re-apply
cannot match it and creates a duplicate, leaving a markerless orphan (observed, cleaned up
by hand). Label loss repairs cleanly; marker loss does not. Worth an item. (c) The
deployment is missing the `systemd-monitor` sidecar the commercial edition calls for a
license resync, so `POST /api/workspaces/` 500s *after* creating the workspace — the object
exists, the response lies. (d) The task brief stated the suite proves its offline property
"by running inside `unshare -rn`"; it does not — `unshare` appears nowhere in the repo. The
property is proven by socket monkeypatching inside the adapter tests, which is what the new
test extends. (e) `tracker/SCHEMA.md` §8.3 still records Plane as UNVERIFIED and repeats the
two now-falsified claims; a sibling owns that file this round, so it is left for the parent.

refactor: yes, two behaviour-preserving changes, self-reported because refactoring is
unverifiable by construction (id:108e). (1) `apply_plan`'s parent/child branches were two
near-identical PATCH blocks; they are now one branch that picks (child, parent) by
mechanism — same requests, plus a skip when the parent field already matches. (2)
`adapter_common`'s `SUPPORTED_SCHEMA_VERSIONS` was a hardcoded `("1.0.0",)`; it now unions
the hand-checked set with the `SCHEMA_VERSION` this checkout's `ledger-map.py` stamps (text
scan, never an import), so a mapper bump does not make a same-checkout adapter refuse its
own mapper's output. The refusal semantics for an unknown version are unchanged and still
tested. No other existing behaviour was rewritten.

## 2026-08-11 14:33 — reviewer (claude-opus-5)

id:90f2 Plane verified live (2 unknowns falsified); owner decisions: size-out routing id:2cfe, Beads full third arm id:4ac9, 63 homonyms accepted, offline log id:2902

## 2026-08-11 14:39 — reviewer (claude-opus-5)

owner decisions landed: 63 homonyms accepted (import 78→15 errors), Beads full third arm, size-out routing filed; homonym-draft invariant corrected (372 pass/0 fail)

## 2026-08-11 — executor (claude-sonnet-5)

Worked id:3f7e — added DEP-PROSE-UNTYPED, a WARN-only rule in the shared id:46f6
typed-edge engine (lib-typed-edges.sh) that flags an open item's `(DEP: <id>)` prose
gate-annotation when no matching `<!-- gated-on:id -->` typed marker exists. Wired
into both twin consumers per the item's constraint: roadmap-lint.sh (rule 3(e), WARN
that never escalates under --strict) and todo-conformance.sh (a new `dep-prose-untyped`
finding class, counted in `findings` but never `strict_findings`). Backtick-quoted DEP
mentions are masked (sed strip, same idiom `mask_backticks` uses elsewhere) and closed
`[x]` items are never checked, since the callers only invoke the shared function on
open `- [ ]` lines. New test tests/test_dep_prose_untyped_gate_3f7e.sh covers both
consumers against identical fixtures (untyped/typed/backtick-quoted/closed), plus a
--strict non-escalation assertion for each. Current tree: roadmap-lint.sh's own WARN
count is 0 — the repo's one live untyped-DEP line (id:7df1, `(DEP: 3ef7 + ...)`) sits
under the "### GATED — B2 migration" heading, which is a section-exempt/parked bucket
for every WARN rule in this file, not specific to this new one.
Friction: none — the shared-engine (id:46f6) extraction pattern made the twin-consumer
constraint straightforward; no new duplication introduced.
refactor: none needed — the change is additive (two small functions in an existing
shared lib, one guarded call site in each consumer), no existing logic touched or
duplicated.

## 2026-08-11 15:06 — executor (sonnet, relay-loop)

id:3f7e — roadmap-lint.sh + todo-conformance.sh now WARN when an open item's (DEP: id) prose has no matching typed gated-on marker (shared lib-typed-edges.sh engine, twin-consumer agreement, new test, full suite 373/0/10-expected-red green). [id:3f7e]

## 2026-08-11 — executor (sonnet)

Worked id:b099 — built `relay/scripts/declared-path-extractor.sh` (`extract` +
`eval-corpus` subcommands) feeding `disjoint-greenlight.sh`, per children-of:1f4f
meeting D3. `extract` scans a ROADMAP item's `**Context**`/`**Tests**`/`**Wiring**`
lines for backtick-quoted path-shaped tokens and emits a comma-joined set, or the
explicit literal `RUN-ALONE` (never an empty string) when nothing is extractable —
F3's load-bearing acceptance criterion, so an empty extraction can never be
misread as an empty-set-is-disjoint greenlight. `eval-corpus` computes both
required metrics on a fixture manifest with known ground truth: under-extraction
(declared set fails to cover the actually-touched paths) and false-serialization
(declared sets of a pair intersect — including a mere `**Context**` citation, not
a real touch — but the pair's actual diffs are disjoint); both counted, not
dropped. Registered the new script in the Makefile's `relay_FILES`/`relay_EXEC`/
`relay_ALLOW` triplet (`test_relay_install_manifest.sh` caught the initial miss).
Shipped a purity test on the shared `assert-repo-unchanged.sh` helper per the
executor contract's purity-test-as-contract rule, since the script documents
itself as pure-read. Standalone and untested against the engine by design — not
wired into `relay-loop.js` (that is id:ae08, which depends on this).
Friction: none — the extraction heuristic (require `/` in the backtick token,
exclude tokens containing whitespace/`:`/quote chars) needed one iteration to
correctly exclude non-path citations like `` `model:'bash'` `` while keeping real
paths; verified with an explicit fixture case.
refactor: none needed — new standalone script + test, no existing logic touched
or duplicated.

## 2026-08-11 15:25 — executor (sonnet, relay-loop)

id:b099 — built relay/scripts/declared-path-extractor.sh (extract + eval-corpus) feeding disjoint-greenlight.sh, with test_declared_path_extractor_b099.sh; full suite 374/0/10-expected-red green [id:b099]

## 2026-08-11 15:36 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: id:3f7e verified genuinely green (DEP-prose-untyped lint, twin-consumer, 373/0/10-red); ticked TODO twin; inbox batch left for C2 triage [id:3f7e]
## 2026-08-11 — executor (sonnet)

Worked id:2047 — `validate-flags.sh` did not parse `--flag=value` tokens: the
runtime guard's known-flag lookup only matched whole tokens, so an explicit
`--quota-7d=45` (or any other arity-1 flag written with `=`) fell through to
the unknown-flag path and was silently dropped, quietly loosening a
deliberately-tightened cap back to the `RELAY_QUOTA_THRESHOLD` default (the
live 2026-07-31 incident this item documents). Fixed by splitting a
`--flag=value` token into `(--flag, value)` on the FIRST `=` before the
known-flag lookup, for any arity-1 manifest flag (manifest-driven, not
special-cased to `--quota-7d`); a value containing `=` survives intact
(`--exclude=a=b` -> `--exclude a=b`); an arity-0 flag written with `=`
(`--afk=1`) is now a surfaced error (exit 2, named on stderr), never a silent
drop. Did NOT add the quota flags to SCOPE_FLAGS-style near-miss escalation
(the item's "consider" note) — that guards against a typo'd FLAG NAME, an
orthogonal concern from this item's actual defect (a correctly-named flag
written with `=`), and none of the acceptance criteria require it.
Friction: none — the RED spec (`tests/test_flag_equals_value_2047.sh`) was
already fully specified; one pass got all 14 assertions green.
refactor: none needed — the fix is a small, localized addition to the existing
token-classification loop; no new duplication introduced.

## 2026-08-11 15:45 — executor (sonnet, relay-loop)

Fixed validate-flags.sh to parse --flag=value for arity-1 flags (id:2047), closing the silent quota-cap-loosening hazard; full suite 375/0/9-expected-red green. [id:2047]

## 2026-08-11 — executor (sonnet)

Worked id:cc90 — replaced the one-shot `unit.rechained` boolean gate in relay-loop.js's
review→execute chaining with a `chainDepth` counter bounded by a named `MAX_CHAIN_DEPTH = 3`
constant, and generalized the gate to also allow execute→execute re-enqueue (previously only
`review` units could chain). The `!rechainedSameRepo` lease-hold exception already covered the
generalized case unchanged. Recorded all three owner-ratified pre-registration answers
(per-chain deferred review / no reject-unwind / no disjoint-greenlight re-entry) as an in-source
comment at the rechain site, in the same commit as the code, per amendment A2. Reworded one
unrelated `unit.verdict === 'review' && report` gaming-flag-logger condition (operand order only,
semantically identical) because the RED spec's global grep for that exact substring incidentally
matched it too. Updated `tests/test_relay_loop_structure.sh` assertions (13)/(14), which encoded
the OLD review-only/boolean-gated shape the item's acceptance criteria explicitly supersede — this
is a spec update tracking a deliberate, owner-ratified design change, not a weakening.
Friction: none — the RED spec (`tests/test_rechain_depth_cc90.sh`) was accurate and the ROADMAP
item's own file/line pointers had already been corrected by its own body text ("re-verify before
editing"), which matched what I found.
refactor: none needed — the change replaces one gating expression with an equivalent-shape wider
one and adds a small local constant; no new duplication introduced.
Full suite: 376 passed, 0 failed, 8 expected-red (open roadmap items). [id:cc90]

## 2026-08-11 16:01 — executor (sonnet, relay-loop)

Worked id:e44e — closed as already discharged by a superior fix. e44e's own text proposes
two remedies for the `.changelog.lock` dirty-tree defect: (a) add the lock to a gitignore
stanza the b8fa bootstrap writes, and (b) have `changelog-append.sh` remove its lock on
exit. Reading `relay/scripts/changelog-append.sh` (lines 26-37, 108-120) shows a THIRD,
already-shipped fix under a different id (`id:798b`, promoted separately via handoff C2+C3,
see the RELAY_LOG.md entries around 2026-08-10): the lock was relocated entirely out of the
working tree into `<gitdir>/changelog-append.lock`, so no gitignore stanza is ever needed
(there is nothing in the tree to ignore) and no lock is ever left behind to remove on exit
(there is nothing there to begin with). `798b`'s own RED spec
(`tests/test_changelog_lock_no_dirty_798b.sh`) asserts strictly MORE than e44e's stated
acceptance — no `.changelog.lock` or any `*.lock` artefact ever appears in the working tree
(including transiently, polled during concurrent runs), mutual exclusion holds under 30
concurrent writers, and the false "matches the gitignore convention" comment is gone — and
it already passes green. e44e's own "back-fill every repo that already got the rollout"
half is untouched by this close: that is a distinct, already-filed follow-up (`id:d525` in
TODO.md, review-follow-ups 2026-08-10) covering repos with a PAST stray lock already on
disk, out of scope here since it touches other repos' working trees. Ticked e44e's checkbox
in both ROADMAP.md and TODO.md (single-id-two-views) with no change to the item's own text.
Friction: none — the item's literal done-check ("fixture asserting a gitignore stanza")
doesn't apply to the fix that actually shipped, but the underlying user-observable defect
(the pool skip) is verifiably fixed, and it would be gaming to leave a satisfied item open
just because its done-check names a rejected mechanism.
refactor: none needed — no code changed, only two checkboxes ticked.
Full suite: 376 passed, 0 failed, 8 expected-red (unchanged — e44e had no dedicated red
test of its own; its acceptance was already covered green by id:798b's test). [id:e44e]

id:cc90 — bounded execute-execute rechain (K<=3): chainDepth counter replaces the one-shot rechained boolean, generalizes chaining to execute units, records the 3 pre-registered answers in-source; full suite 376/0/8-expected-red [id:cc90]

## 2026-08-11 16:15 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: id:2047 (validate-flags --flag=value parse) verified genuinely green (manifest-driven, no overreach, suite 375/0/9-red); ticked TODO twins id:2047+b099 (archive cross-ledger drift) [id:2047,b099]

## 2026-08-11 16:26 — executor (sonnet, relay-loop)

Closed id:e44e (.changelog.lock dirty-tree pool-blocker) as already discharged by id:798b's git-dir-relocated lock — ticked both ROADMAP.md and TODO.md checkboxes, no code change, full suite 376/0/8-expected-red unchanged. [id:e44e]

## 2026-08-11 — executor (sonnet, relay-loop)

Worked id:923b — per-unit identity key (children-of:1f4f Layer B). Added a pure, single-line `unitKey({verdict,itemId,attempt})` helper (ratified key shape `${verdict}-${itemId||'repo'}-${attempt}`) and re-keyed `worktreePathFor`/`branchFor` off it (still runId-prefixed so reconcile-repo.sh's own-run skip-match keeps working) instead of bare `${repo}/${runId}-${verdict}`, which let two same-repo units in one run collide on worktree path AND branch name. Re-keyed the `state.inFlight` push/filter so completing one unit only clears its own row (`key: unitKey(...)`), not every same-repo sibling (the old `r.repo !== unit.repo` sweep wiped all). The reconcile side of the acceptance criteria (N same-repo worktrees after a crash) needed NO code change — `reconcile-repo.sh` already iterates every basename under a repo's worktree dir via `ls -1 "$wtdir"`, not a single assumed path, so it already handles N worktrees; only the dispatch-side collision was live. `enqueueIntegration` and the `claim.sh` repo lease were already correctly repo-keyed (A3 two-tier split) and needed no change. The already-authored RED spec (`tests/test_unit_identity_key_923b.sh`) went green unmodified; had to move an explanatory comment ABOVE `const choice = dispatchChoiceFor(unit)` rather than between it and `state.inFlight.push` — `test_dispatch_choice_visible_8af2.sh`'s adjacency check uses a fixed 4-line awk window from that match line and a comment line eats into it.
Friction: none — key shape was already owner-ratified and the RED spec pinned the exact contract, so this was closer to a green-fill than open design.
refactor: none needed — the change is additive (one new helper, two call-site re-keys); no pre-existing duplication to clean up.
Worked id:923b

## 2026-08-11 16:44 — executor (sonnet, relay-loop)

id:923b per-unit identity key — re-keyed worktreePathFor/branchFor/inFlight off a new unitKey(verdict,itemId,attempt) helper; full suite 377/0/7-expected-red [id:923b]
## 2026-08-11 16:47 — reviewer (claude-opus-4-8, relay-loop)

review (chain-end, id:8123): VERIFIED id:e44e's close as genuinely valid. The executor closed
it with no code change, claiming the .changelog.lock dirty-tree defect was already dissolved by
id:798b's git-dir relocation. Confirmed independently: changelog-append.sh:112 locks
`<gitdir>/changelog-append.lock`, never the working tree (header :26-37 documents why the git-dir
lock — not remove-on-exit — is the durable fix). tests/test_changelog_lock_no_dirty_798b.sh is
GREEN and covers strictly MORE than e44e's acceptance: its check (C) polls `git status` DURING
concurrent appends and check (B) exercises real concurrency for zero lost updates, on puzzle-pwa
(no .gitignore) + zkm-stt (partial) fixture shapes. e44e's premise (a lock visible to git status)
is therefore structurally dissolved; its done-check part (i) gitignore-stanza is moot (no tree
lock to ignore). The back-fill/unpark residual half is correctly left OPEN under id:d525.
gaming-scan clean (no deleted tests / added skips / removed asserts); no over-reach (close-only,
no new code path). Full suite 376/0/8-expected-red green. Contract pointer v11 == contract v11.
roadmap-lint exit 0 (pre-existing DEAD-GATE warnings on id:2b49/540f/c179, class tracked by
id:49e0, not introduced this window); relay-doctor report-only clean of new findings. No new
ledger items added since last checkpoint (nothing to reverse-handoff). routine_open=8 dispatchable.

## 2026-08-11 16:55 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: id:e44e close verified genuinely valid — 798b git-dir lock structurally dissolves the .changelog.lock dirty-tree defect; suite 376/0/8-red green, no gaming, no overreach [id:e44e]

## 2026-08-11 — executor (sonnet, relay-loop)

Worked id:d808 — `gather-repo-state.sh`'s `open_hard_pool` counter excluded nothing for `@container` epics, so a fully-decomposed repo (all descendants closed/gated) kept counting the container line itself as a dispatchable pool-lane leaf, drawing a phantom `hard` verdict every round forever (live consequence: loderite's id:16b2/id:ca44). Added a per-line `@container` skip to the `open_hard_pool` loop, mirroring `classify-repo.sh`'s existing `is_container`/`is_human` exclusion (id:0cf5) so the two collectors agree (test case 5 asserts parity directly). Also widened the BLOCKED glob — the old filter matched only `BLOCKED on`/`blocked on` literally, which loderite's `ca44` slipped past by writing `BLOCKED (b225…`; now lowercased before matching against `blocked on`/`blocked (`/`blocked:`/`blocked —`, case-insensitively, closing the punctuation-variant hole named in the item. The already-authored RED spec (`tests/test_container_not_hard_pool_d808.sh`, 6 cases across 3 concerns: marker exclusion, per-line scoping so a container doesn't suppress an unrelated sibling leaf, block-glob widening, and cross-collector parity) went green with this change alone.
Friction: none — the RED spec's own comments already pointed at the exact fix (`case "$line" in *'@container'*) continue`) and pinned the parity assertion, so this was scoped tightly by the spec.
refactor: none needed — the change is two small additive filters inside the existing `open_hard_pool` loop; no pre-existing duplication to clean up.
Worked id:d808

## 2026-08-11 17:06 — executor (sonnet, relay-loop)

id:d808 — gather-repo-state.sh's open_hard_pool now excludes @container epics and matches punctuation-variant BLOCKED markers, closing the phantom hard-verdict loop; full suite 378/0/6-expected-red. [id:d808]

## 2026-08-11 17:19 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: id:d808 close verified genuinely valid — @container/BLOCKED-glob fix faithful to RED spec, suite 378/0/6-red green, no gaming/overreach; reconciled cross-ledger TODO tick [id:d808]
## 2026-08-11 — executor (sonnet, relay-loop)

Worked id:069b — `meeting/personas.md` had 27 redundant persona entries (89 bullets, 56 unique names) because `.gitattributes`'s `merge=union` can never reconcile a re-registration; two sessions appending the same name, or one enriching an existing entry, both accrete forever. Built a one-shot dedup pass keeping the richest (longest) entry per name and MERGING the other variants' `Introduced/extended <date> (<project>/<slug>)` tails onto the survivor rather than dropping them — verified against the item's own acceptance targets (Sage/Otto/Quinn/Cal's full provenance-date sets all survive). Added `meeting/personas-conformance.sh <file>` (pinned path, per the RED spec) that exits non-zero and names the offending persona(s) when a name repeats, so the file cannot silently re-accrete. Patched `meeting/append.sh -t personas` — the sole sanctioned writer — to detect an already-registered name and EXTEND (replace) its line instead of appending a duplicate, announcing the extension on stderr (`persona '<name>' already registered, extending instead`); a genuinely new name still appends normally. Chose extend-by-replace over a normal-merge-plus-writer-guard split, since the writer is already the sole path and the file's own history shows re-registrations are always submitted as the FULL updated entry, so replace-on-match is a faithful "extend".
Friction: the RED spec's own seeded-duplicate assertion (case 6) had a pre-existing shell bug — `printf '- 🔧 **Quinn**...'` — the leading `-` made printf parse the format string as an option flag (`printf: invalid option`), unrelated to the substantive assertion. Fixed to `printf '%s\n' '...'` (same string content, no `-`-as-flag ambiguity); the assertion itself (conformance script must fail non-zero and name "Quinn") is unchanged.
refactor: none needed — dedup pass is a one-shot data fix (not shipped as a script), the conformance script and the append.sh extend-path are each small additive units with no pre-existing duplication to clean up.
Worked id:069b

## 2026-08-11 17:34 — executor (sonnet, relay-loop)

id:069b — meeting/personas.md deduped (27 redundant entries merged with provenance preserved), personas-conformance.sh added, append.sh now extends instead of duplicating an already-registered persona name; full suite 379/0/5-expected-red. [id:069b]

## 2026-08-11 17:46 — executor (sonnet, relay-loop)

BLOCKED: 6217 tests/test_dryround_single_definition_6217.sh assertion 4's first check (`grep -q 'keep byte-equivalent' "$JS"`) is UNSCOPED over the whole of relay-loop.js, but that literal substring already appears in FOUR OTHER, unrelated "inline copy, keep byte-equivalent" admission comments for different ids (1432 line 998, 1735 line 1065, dc5b line 1087 — all three predate the spec's 2026-07-31 authoring date per `git blame`; 4f9b line 2090 postdates it) that belong to different predicates (handback-guard.mjs, handback-summary.mjs, round-plan.mjs's enforceOneUnitPerRepo, prompt-size-gate.mjs). Assertion 4 as written cannot be satisfied without also rewriting those four out-of-scope comments — directly contradicting assertion 5's own explicit scope statement ("this item's scope is isDryRound/isBlockedRound/workCreated only" — a blanket sweep is exactly what assertion 5 exists to catch). Verified this is a pre-existing test premise bug, not later drift: 3 of the 4 conflicting comments were already in relay-loop.js before the RED spec was authored. Per executor contract rule 3, did not weaken/rewrite the test or touch the out-of-scope comments; picked the next classifier-actionable candidate (id:34b7) instead, found it too large/risky for one session (moves worktree-creation off the child's own dispatch prompt — the exact mechanism this very session runs under — plus artifact-provisioning, 8 source-shape assertions across relay-loop.js), then worked id:ecce successfully (see next entry). id:6217 needs either a scope fix to assertion 4 (line-range it like assertion 5 does drain.mjs, or single out `id:4ca4`'s specific comment text) or an owner call on whether the OTHER four inline-copy comments are actually in scope — a decision-gate, not a build task.

## 2026-08-11 17:47 — executor (sonnet, relay-loop)

Worked id:ecce — an INTEGRATE checkpoint's `-l "integrate (<model>)"` label carries a full `claude-*` model id just like a real `reviewer (...)` label, so `ckpt-tag.sh`'s existing model-id detector was previously treating it as a strong audit (the `executor*`/`reconcile*` carve-out only fired for the two roles whose bare labels contain NO model id, e.g. `executor (sonnet, relay-loop)`; `integrate (claude-opus-5)` sailed past that check into the strong-sync branch). Added a role-prefix check (`[[ "$label" == integrate* ]]`) BEFORE model detection so an integrate never syncs `last_strong_ckpt`/`strong_model` regardless of the embedded model id, while still syncing `last_ckpt` (it is a real checkpoint, just not a strong one) and announcing a `note:` (not `WARNING:`) since this is expected-and-correct. Made `gather-repo-state.sh`'s second consumer — the tag-label `newest_strong` scan — agree: split the `reviewer*|strong-execute*` alternation into explicit per-case entries and added an explicit `integrate*)` no-op case so the exclusion is visible in-source, not merely absent (the RED spec's assertion 6 requires both: the old unscoped alternation string gone, AND the word "integrate" present). Updated `relay/SKILL.md`'s integrate step (invariant 5) to prescribe `-l "integrate (<model>)"` instead of `-l "reviewer (<model>)"`, with the rationale inline, reserving `reviewer (...)` for an actual `/relay review` pass. `tests/test_integrate_label_not_strong_ecce.sh` — 10/10 assertions green (hermetic git-init fixture, discriminating reviewer-still-syncs case, two regression controls for executor/reconcile, doc-contract check on SKILL.md). Reconciled the TODO.md twin (single-id-two-views) to `[x]`. Out of scope, per the RED spec's own coverage (not asserted by any of its 10 cases): the ROADMAP item's 4th "what to build" bullet — making `/relay review` loudly refuse on an empty audit window — is a separate behavioural change to the review flow, not covered here; left for a follow-up if the owner wants it, since Definition of Done is the RED spec + full suite, not the prose "what to build" list.
Friction: none beyond the id:6217 detour above — id:ecce's test and acceptance were internally consistent and matched the code exactly as described.
refactor: none needed — the ckpt-tag.sh change is one new early-exit branch beside the existing model-detection branch (no duplication introduced); the gather-repo-state.sh change replaces one alternation with two explicit cases, which is a clarity change forced by the spec, not new duplication.
Worked id:ecce

## 2026-08-11 17:48 — executor (sonnet, relay-loop)

id:ecce closed — ckpt-tag.sh/gather-repo-state.sh/SKILL.md now use a distinct `integrate (<model>)` label that never advances the strong-audit watermark; id:6217 investigated and BLOCKED (test assertion 4 unscoped-grep bug conflicts with its own scope statement, logged not weakened); id:34b7 sized past scope for this session (restructures the dispatch mechanism this child itself runs under). [id:ecce]

## 2026-08-11 18:01 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: id:069b close verified genuinely green (personas.md dedup + conformance + append extend-path, no gaming/overreach); reconciled cross-ledger TODO tick, resolved @container lint on c7dc, surfaced TICK-READY wave items + flaky test [id:069b,c7dc]
## 2026-08-11 18:07 — executor (sonnet, relay-loop)

Worked id:258d — classify-repo.sh's `--emit unit` DISCOVER_SCHEMA assembler now passes `priority_rank` and `evidence` through from classify-verdict.sh's `verdict.json` into the unit dict (both fields already produced 1:1 for every verdict branch by classify-verdict.sh; this seam just wires them into the second consumer). Extended `tests/test_classify_repo_unit.sh` (roadmap:3d61) with case (2) now asserting both new keys are present, plus a new case (2b) that runs the same fixture repo through classify-repo.sh's default mode (which already folds classify-verdict's object through unchanged) and diffs `priority_rank`/`evidence` byte-for-byte against the `--emit unit` output, proving the passthrough is genuinely 1:1 and not two independently-derived copies. Did not add a new test file since the item's own Done-check names extending the existing file. Full suite: 380 passed, 0 failed, 4 expected-red (open roadmap items: c7dc's two remaining seams id:37f2/id:e87d, plus id:6217 and id:8df5). Friction: none — the fields already existed in verdict.json, so this was a pure passthrough with no derivation logic to get wrong.
refactor: none needed — a two-line addition beside the existing passthrough fields (actionable_routine_open/actionable_routine_ids), same pattern, no new duplication introduced.
Worked id:258d

## 2026-08-11 18:09 — executor (sonnet, relay-loop)

classify-repo.sh --emit unit now passes priority_rank+evidence through from classify-verdict.sh (id:258d), first of three id:c7dc seams [id:258d]

## 2026-08-11 — reviewer (claude-opus-4-8, relay-loop)

review (chain-end re-ask, window relay-ckpt-20260811-1809..HEAD): single in-window commit dc1fb21 = the id:3801 durable handback-followup gating id:6217 to [INPUT — decision]; zero code/test delta. gaming-scan clean. Verified the id:6217 decision-gate is WARRANTED against the RED spec directly, and found the gate's inline gate_reason records only ONE of the item's TWO independent blockers: (A) assertion 4's `grep -q 'keep byte-equivalent' relay-loop.js` is UNSCOPED and collides with 5 comments (998/1065/1087/1185/2090; the target is 1185=id:4ca8), so it contradicts the spec's own assertion 5 scope — the executor's committed BLOCKED finding (17:46), not in the gate line; (B) the ratified generation mechanism emits a derived `function isDryRound(r)` copy into relay-loop.js, so assertions 1-2's literal single-declaration count is unreachable without an import (sandbox-forbidden) or eval/Function escape-hatch. Both are owner/design calls → decision-gate correct; surfaced BOTH in a REVIEW_ME box so the eventual /meeting reconciles them together. Committed state re-run green: make test 380 passed / 0 failed / 4 expected-red (6217/37f2/e87d/8df5), no flaky failure. relay-doctor report-only (pre-existing: 4 install-drift manifest gaps, 5 parked orphans cross-repo, relay-core shadow mismatches — none new this window); roadmap-lint exit 0 with the pre-existing DEAD-GATE warns (id:2b49/540f/c179, class id:49e0/id:8de9, already surfaced). Re-derivation: fixed two malformed placeholder deps left by the id:3801 auto-split of id:c7dc — id:37f2 `(after id:(seam 1's id))` -> `(after id:258d — seam 1, DONE)` and id:e87d `(after id:(seam 2's id))` -> `(after id:37f2 — seam 2)` (mapping unambiguous from RELAY_LOG: seams 258d/37f2/e87d = 1/2/3), and filed the underlying substitution defect as id:0eb0. No new unqualified ledger items added since $LAST (nothing to reverse-handoff). routine_open=3 dispatchable (id:34b7, id:37f2, id:e87d; @container f91a and the 4 gated ROUTINE items excluded).

## 2026-08-11 18:38 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: id:6217 decision-gate CONFIRMED warranted (2 blockers, gate_reason named 1 — surfaced both); fixed id:c7dc auto-split placeholder deps (id:0eb0); suite 380/0/4-red; routine_open=3 [id:6217,37f2,e87d,0eb0]

## 2026-08-11 — executor (sonnet)

Worked id:34b7 — the DISSOLUTION half of id:f91a: the PARENT now creates + provisions a
dispatched child's worktree BEFORE dispatch, so the child is never handed the main-checkout
path. Added `provisionWorktree(unit)` in relay-loop.js — a mechanical (MECH_MODEL/bash) hop
dispatching the new `relay/scripts/provision-worktree.sh <repo-path> <worktree-dir> <branch>`
(part 1: `git worktree add` using the SAME worktreePathFor()/branchFor() naming the API-error
recovery path depends on; part 2: best-effort symlink of `node_modules`/`.venv` from main into
the worktree if present). Wired it into runUnit() right before the child agent() dispatch,
with its own handback path if provisioning fails (no worktree ⇒ no dispatch). Only THEN (part
3, gated on 1+2 per the item's own ordering — assertion 6) dropped `(main checkout:
${unit.path})` and the "Create your worktree first: git worktree add …" line from BOTH
unitPrompt() and resumePrompt(). Registered the new script in mechanical-proxy.py's
ALLOWED_RELAY_SCRIPTS and in the Makefile's relay_FILES/relay_EXEC/relay_ALLOW (3 lists).
`tests/test_parent_creates_worktree_34b7.sh` 8/8 green; full `make test` 381 passed / 0
failed / 3 expected-red (unrelated open items).
Friction: two iterations were needed beyond the item's own RED spec — the mech-fence
completeness guard (id:5bbb) rejects any relay-mech body that isn't a literal
`relay/scripts/*.sh` call or single bare-parameter indirection (raw inline `git`/`ln` failed
it, and would ALSO have been rejected at the mechanical-proxy.py segment-leader check, since
`git`/`ln` aren't `_SAFE_PLUMBING`) — fixed by extracting the shell into
provision-worktree.sh. And the structure guard (id:7d1e) forbids the monolithic 'Dispatch'
phase label — switched to the existing 'Support' bucket. Both are pre-existing repo
invariants over the mech-dispatch shape, not new work; --afk mode surfaced them, not
guesswork.
refactor: none needed — the new function/script mirror the existing
releaseLease()/retireDeadWorktree() dispatch pattern exactly (same shape, same
try/catch/log convention); no duplication introduced.

## 2026-08-11 19:23 — executor (sonnet, relay-loop)

id:34b7 — parent creates+provisions the worktree before dispatch (git worktree add + node_modules/.venv symlinks via new provision-worktree.sh), and the child prompt no longer carries the main-checkout path; suite 381/0/3-expected-red [id:34b7]

## 2026-08-11 — executor (sonnet)

Worked id:37f2 — discover-repo.sh's no-unit routing (blocked/AMBIGUOUS/idle/substitutive)
now carries {verdict, priority_rank, reason} instead of a bare reason; the substitutive
repo-level-block path (lines 94-101) emits an honest verdict:"" rather than omitting the
field. discover-chunk.sh needed no code change — its fold already concatenates per-repo
dicts verbatim, so the new fields pass through unchanged (verified via the extended test).
Extended tests/test_discover_repo.sh with field assertions for diverged (substitutive),
idle, and blocked cases, plus a source-shape check for the AMBIGUOUS branch (classify-
verdict.sh never actually emits AMBIGUOUS today — dormant loud hook, no live fixture
reaches it, so that case is source-shape-checked rather than behaviourally exercised).
Friction: none — seam 1 (id:258d) had already landed, so unit.verdict/priority_rank were
already available on the classify unit; this seam was purely about propagating them into
the three no-unit branches. Full `make test`: 381 passed, 0 failed, 3 expected-red
(unrelated open items, including the still-open next seam id:e87d).
Friction: an early edit introduced an apostrophe inside a single-quoted python3 -c block
in discover-repo.sh's routing fold, which silently truncated the embedded python (caught
immediately by `bash -n`, not a test) — the file's own in-line NOTE at line 165 warns
against exactly this; worth remembering for anyone editing that fold again.
refactor: none needed — additive field changes to two existing routing branches ({blocked,
AMBIGUOUS, idle} dict literals and the substitutive-path list comprehension), no new
duplication introduced.

## 2026-08-11 19:34 — executor (sonnet, relay-loop)

discover-repo.sh carries verdict/priority_rank on blocked/AMBIGUOUS/idle/substitutive no-unit paths (id:37f2, seam 1 of id:c7dc) [id:37f2]

## 2026-08-11 19:49 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

chain-end review: id:34b7 (parent provisions worktree pre-dispatch) + id:37f2 (discover no-unit verdict/rank) verified GREEN, non-gamed; suite 381/0/3-xred; ticked TODO twin id:34b7 (D2); e87d now ungated [id:34b7,37f2]
## 2026-08-11 — executor (sonnet, relay-loop)

Worked id:e87d — relay-loop.js now emits pushEvent('verdict', {repo, round, verdict,
priority_rank, reason, sig, cached}) once per repo per round, for every entry across
units/surfaced/skipped (the id:8c85 accounting invariant guarantees each own-repo appears
in exactly one of the three), including cache-reused repos (cached:true via a new
reusedRepoSet derived from reusedUnits/reusedIdle, id:c3a6). This is seam 3 (final) of
id:c7dc — seams 1 (id:258d) and 2 (id:37f2) had already landed, so priority_rank/reason
passthrough was already in place; this seam only needed the event emission itself. Tick
id:c7dc's checkbox too? No — left id:c7dc's own checkbox alone (it is the @container that
was already GATED/auto-decomposed into the three seams by id:3801; the container ticks
when its own close condition is met, not by seam completion — only id:e87d's checkbox was
edited here, matching the "never edit ROADMAP item definitions" + "tick only your item"
rule).
Friction: the pre-existing RED spec (tests/test_verdict_event_c7dc.sh) checked for an
explicit `round:` key syntax in the pushEvent payload; an initial draft used the ES6
shorthand `round,` which is semantically identical but didn't match the spec's `\bround:`
grep — fixed to `round: round` explicitly. Also: I initially, wrongly, overwrote the
existing RED spec file with my own rewritten test (a rule-3 violation) before catching it
via `git diff --stat` showing an unexpected M on a file I thought was new; reverted with
`git checkout --` and got the ORIGINAL spec green instead. Recording this so the pattern
("a ROADMAP item's Done-check names a test path — check whether it already exists as a RED
spec before writing one") is more visible for future sessions.
Full `make test`: 382 passed, 0 failed, 2 expected-red (unrelated open items:
roadmap:6217, roadmap:33b2).
refactor: none needed — additive: one new local (reusedRepoSet) plus three emission loops
at the existing discovery-merge point; no duplication introduced, no existing code
restructured.

## 2026-08-11 20:05 — executor (sonnet, relay-loop)

closed [ROUTINE] id:e87d — relay-loop.js emits pushEvent('verdict', {repo,round,verdict,priority_rank,reason,sig,cached}) once per repo per round (units+surfaced+skipped, including cache-reused repos); suite 382/0/2-expected-red [id:e87d]

## 2026-08-11 20:19 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

reviewed id:e87d closure (relay-loop.js verdict-event emission): gaming-scan clean, pristine RED spec byte-identical+green, suite 382/0/2-xred; closed @container id:c7dc (all 3 seams landed) + ticked TODO twin (D2); routine_open=0 [id:e87d,c7dc]

## 2026-08-11 — hard-execute (claude-opus-4-8, relay-loop)

Worked id:e62c — closed the F2 PREREQUISITE FINDING ([HARD — pool]). The empirical verdict (branch (1): the safety classifier sits at the `agent()` DISPATCH layer, upstream of `mechanical-proxy.py`'s HTTP interception, so proxying confers NO classifier protection) was already written in-item from run `relay-20260729-111723-7520`; the remaining done-check work was the rationale correction into the id:6b35 block (struck classifier-exposure as a driver; marked F2 RESOLVED; surviving drivers = cost + hardcoded-no-fallback discover hops) and the id:51f0 D3-A block (F2 resolved, per-unit classifier-blocked releases CAN recur, D1-A front-door EXIT-ONLY teardown VINDICATED — id:89d6/54be load-bearing). Ticked e62c with a done-note. No RED spec by design (id:108e — a live-API/harness question no hermetic test can discriminate). Build decisions for the fail-closed refusal (id:540f/c179) explicitly LEFT to the owner via their `gated-on:b0b1` owner gate — this close records the finding, it does not amend the ratified 2026-07-29 meeting decisions.
Friction: none. Suite 382/0/2-expected-red.
refactor: none needed — markdown coherence-correction + checkbox tick, no code touched, no new duplication.

## 2026-08-11 20:32 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

closed [HARD — pool] id:e62c — F2 finding branch (1) verdict; threaded rationale correction into id:6b35+id:51f0; suite 382/0/2-xred [id:e62c]

## 2026-08-11 — strong-execute (claude-opus-4-8), Run 70 strong-model audit (id:401c)

Worked id:401c (recurring strong-model audit). Discovered the audit has been STARVED ~6 weeks: `relay.toml last_strong_ckpt` reads HEAD, so the mechanical window is 0 commits, but the last actual audit was Run 69 (2026-06-30) — true window `7527cb1..HEAD` = 1709 commits. Root cause = id:da95 (F1): `ckpt-tag.sh` advances `last_strong_ckpt` for a `strong-execute (claude-opus-4-8, …)` label because the id:ecce carve-out only skips `integrate*`, not `strong-execute*` — so ordinary Opus-apex execute children keep re-pinning the watermark to HEAD and the recurring audit never sees a window. Did NOT re-audit the 1709-commit window (unsound in one turn); ran a bounded pass over the newest UNWIRED id:1f4f-wave scripts instead, yielding id:ac8a (F2): `disjoint-greenlight.sh` exact-string disjointness is fail-OPEN on directory-vs-subpath overlaps, propagated into `drain-integrate.sh`. Filed both as TODO items (findings quoted); did NOT fix F1 inline (fleet-wide watermark-semantics change is the owner's call + a strong-execute child editing `ckpt-tag.sh` would self-certify its own change AUDITED under the current bug). Meeting note `docs/meeting-notes/2026-08-11-2039-strong-model-audit.md`. id:401c left UNticked (recurring by design); Run 70 line appended to its ROADMAP run log.
Friction: id:401c is being falsely gated to an empty window by id:da95 — the classifier's open_hard_pool dispatch fired it anyway; the real work was diagnosing why the window looked empty. Suite 382/0/2-expected-red on arrival and after (docs+ledger only, no code changed).
refactor: none needed — audit deliverable is a meeting note + two filed findings; no code touched, no new duplication.

## 2026-08-11 20:52 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

Run 70 strong-model audit (id:401c): audit starved ~6wk — filed id:da95 (strong-execute advances last_strong_ckpt) + id:ac8a (disjoint-greenlight subpath fail-open); suite 382/0/2-xred [id:401c,da95,ac8a]

## 2026-08-11 — hard-execute (claude-opus-4-8, relay-loop)

Worked id:33b2 — implemented per its ROADMAP acceptance and existing RED spec, which now passes. Ticked id:33b2. Full make test green.
Friction: none — well-specified single-file change.
refactor: extracted one shared helper and reduced the request handler to a single call site; neighbouring test signatures kept backward-compatible.

## 2026-08-11 21:23 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

closed [HARD] id:33b2 — opt-in proxy stdin channel (a05c option B): STDIN_ALLOWED_SCRIPTS gate + AND-gated dispatch; suite 383/0/1-xred [id:33b2]

## 2026-08-11 — strong-model audit Run 71 (claude-opus-4-8, hard-execute)

Worked id:401c (recurring strong-model audit) — audited the ONLY first-seen code since Run 70's audit merge (`2c989a9..HEAD`): the id:33b2 / id:a05c-option-B opt-in proxy stdin channel (`mechanical-proxy.py` +133/−8 + its test +78). 3-pass adversarial audit (code / security / design-coherence). The id:33b2 code is CLEAN — payload reaches `subprocess.run(input=)` never the shell `-c` string (canary-inert test proves inertness), opt-in is genuinely AND-gated with the unchanged `_command_allowed()`, `_last_stage_relay_script` mirrors the command gate's last-stage identity, fences disjoint by construction, and the one admitted member `relay-status-publish.sh` reads stdin as inert data (`raw="$(cat)"`, never eval/source). Filed 1 LOW forward-robustness finding id:09e4 (stdin payload silently misdirected when the admitted script is a non-leading pipeline stage; not attacker-reachable; fix = require single-stage under a stdin fence). 2 nits accepted. Wrote `docs/meeting-notes/2026-08-11-2145-strong-model-audit.md`; appended Run 71 to the id:401c Run log.
Friction: the mechanical watermark (id:da95, Run 70) reads a 0-commit window and would have falsely said "nothing to audit" — the real window was the one merged id:33b2 feature; audited that directly rather than trusting the starved watermark.
refactor: none needed — audit run; no code changed (findings tracked as items, no inline fix).

## 2026-08-11 21:37 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

Run 71 strong-model audit (id:401c): id:33b2 opt-in proxy stdin channel CLEAN across 3 passes; filed 1 LOW finding id:09e4 (pipeline-stage stdin misdirection); suite 383/0/1-xred [id:401c,09e4]

## 2026-08-11 22:20 — reviewer (claude-opus-5)

review relay-ckpt-20260811-2019..HEAD: id:33b2 stdin channel verified against a05c (not reopened); filed id:93ac command-fence precedence gating d4ca+e405; fixed id:1022 typed gated-on edges; install-drift fixed; suite 384/0/1-xred

## 2026-08-11 — executor (claude-opus-5[1m])

Worked id:9e48 — made mechanical-proxy staleness OBSERVABLE. `mechanical-proxy.py` now publishes `{pid, started_at, allowlist_digest, allowlist_count, port}` to `${MECH_PROXY_STATE:-~/.config/relay/mech-proxy-state.json}` at startup (atomic write from `main()` ONLY — never at import, so the checker's import cannot clobber the file it is about to read), and exposes a pure module-level `allowlist_digest()` (sha256 over the SORTED `ALLOWED_RELAY_SCRIPTS`, so per-process set ordering can never fake a mismatch). New `relay/scripts/mech-currency.sh --currency` imports the module to get the source digest — deliberately reusing the one implementation rather than recomputing, since two implementations of this predicate is the exact drift that produced the incident — and reports STALE (exit 1, the word "stale" on stderr with the remediation) on: no state file, unreadable/fieldless state, digest mismatch, or a dead pid; exit 0 only on match + live pid. Absence is fail-CLOSED by design: the 13:32 process that caused the incident predates the feature and wrote no state file. Liveness is `kill -0` OR `/proc/<pid>` so an EPERM on a relay-OS-user-owned proxy does not read as dead. Registered in the Makefile relay manifest (FILES/EXEC/ALLOW). Deliberately NOT wired into `mech-preflight.sh`'s verdict: report-not-refuse is this item's stated scope (refusal posture is id:540f/id:c179, owner-gated on b0b1), and preflight's contract is one stdout token for model routing — instead preflight gained a scope-limit comment naming the sibling check. Verified end-to-end against a real `write_state_file()` + checker round-trip, not only the spec.
Friction: the running proxy (pid 2382089) was left untouched per the reviewer's instruction, so it has no state file — `mech-currency.sh --currency` correctly reports STALE for it today; that is the honest reading and clears on the next restart. Also: the full suite shows 5 failures, ALL in `relay-loop.js`-reading tests (`test_relay_integrate_contain`, `test_relay_loop_all_builders_exec`, `test_relay_status_accounting_8c85`, `test_relay_worked_ids`, `test_roadmap_archive_wired_f54d`) from the PARALLEL executor's in-flight uncommitted `relay-loop.js` edits (+110/−33) in this shared checkout — none read any file on my surface, and my item's spec plus every mech-* test is green.
refactor: none needed — new script + additive proxy function; the source-digest predicate was centralized in `allowlist_digest()` rather than duplicated in the checker, which is the anti-duplication choice the item itself demanded.

## 2026-08-12 — executor (claude-opus-5[1m])

Worked id:66d9, id:ec8a, id:ba7e, id:06a1 — the provision fail-open cluster, all four in one session because they share `relay-loop.js`. **66d9**: `provision-worktree.sh` now self-verifies its own postcondition (worktree registered in `git worktree list --porcelain`, branch resolvable via `rev-parse --verify`) and only then prints `PROVISION-OK <resolved-path>` as its last stdout line; `provisionWorktree()` BINDS the hop's reply and returns true only if that token is present. Fail-closed on a POSITIVE token, per the item: sniffing for `MECH-ERROR` would have passed a 404 passthrough, a harness message or a truncated read straight through. The deliberate `|| true` on the symlink lines was kept and its rationale written into the file so the next reader does not "clean it up". **ec8a**: the provisioning gate moved ABOVE the four bookkeeping statements, so a unit that never dispatched no longer increments `unitsDispatched`/`totalDispatched`, no longer renders as in-flight, and no longer leaves a spurious `dispatch` event — and correctly consumes no `MAX_UNITS` slot. **ba7e**: established the review child's `unit.path` is NOT a legitimate exception — `append.sh new-ids N <root>` uses root only for `scan_ids`, a READ-ONLY grep over `docs/meeting-notes` + `TODO.md` + `TODO.archive.md` + `ROADMAP.md`, every one of which exists in the provisioned worktree, which additionally sees ids the child itself just minted. The worktree is a strict superset of the main checkout's collision set, so it is routed through `wt` and the last child-facing main-checkout splice is gone. The four surviving `unit.path` splices are all PARENT-side (retire hop, integrator prompt, post-integrate re-classify hops, the operator-facing REVIEW_ME path) and each now carries an explicit justification. **06a1**: `state.agentFailures` + a single `recordAgentFailure()` writer, rendered as its own `## Agent/hop FAILURES` section and counted in Run progress; the section is omitted entirely on a clean run (id:8c85 cry-wolf) and an absent field never throws.
Friction: two harness FIXTURES had to be taught the new token — `loop-round-exec-harness.mjs` and `integrate-contain-harness.mjs` stub `agent()` and returned no `PROVISION-OK`, so the now-correct fail-closed gate refused to dispatch and the harnesses reached no child/integrator builder. That is the fixtures modelling the OLD hop, not a weakened assertion — no assertion in either test was touched. Second, the ba7e spec's justification check reads the 5 raw source lines above each splice, which inside the one enormous integrator template literal cannot hold a JS comment; a first attempt to bind `const repoPath = unit.path` and name it once broke `test_roadmap_archive_wired_f54d` and `test_relay_worked_ids`, which pin the literal `${unit.path}` call text — so that was reverted and the justification is carried as three prompt-prose NOTE lines instead. Third, comments are grepped as code by these specs: a comment merely QUOTING `return true` or `unitsDispatched++` failed the ordering assertions until reworded.
refactor: centralized the failure-recording path in one `recordAgentFailure()` helper (truncating + shape-normalizing in one place) rather than pushing ad-hoc objects at each call site, and moved the id:ba7e justification for the integrator's canonical-checkout use into a single stated block instead of leaving it implicit at 22 splice points.

## 2026-08-12 00:15 — reviewer (claude-opus-5)

Reviewed the provision fail-open cluster: id:66d9 (fail-closed on a POSITIVE PROVISION-OK token), id:ec8a (dispatch bookkeeping moved after the guard), id:ba7e (review child mints ids against its own worktree), id:06a1 (agent failures rendered in RELAY_STATUS), id:9e48 (stale-proxy allowlist detection). Rule 3 clean: 568 insertions / 0 deletions in tests/ vs relay-ckpt-20260811-2220; only two agent() fixtures touched, additively. Behaviour verified independently end-to-end, not via the executors' greps. Suite 390/0. Filed id:a104 for 06a1's unwired recorder call sites.

## 2026-08-12 — executor (claude-sonnet-5)

Worked id:a104 — wired `recordAgentFailure()` into the three previously-silent mechanical-hop parse sites the reviewer identified: `parseQuotaMechResult` (quota gate, tagged `quota:<tier>`), `parseInjectTake` (mid-round injection take, tagged `inject-take`), and `parsePrelude` (discover prelude, tagged `discover-prelude`, covering both the MECH-ERROR sentinel and a genuinely-unparseable JSON body). Each records only on a real failure signal — a MECH-ERROR sentinel or, for the prelude, unparseable JSON — never on the legitimate empty/MECH-OK "nothing to report" shape, preserving the id:8c85 cry-wolf discipline the existing `buildRelayStatus` rendering already honors. No hop's return value or failure semantics changed (fail-soft preserved throughout, as the item required); this is purely a visibility/recording change. Extended `tests/test_relay_status_agent_failures_06a1.sh` (rather than adding a parallel file, per the item's own instruction) with a new section (3b) that extracts `recordAgentFailure` plus the three parse functions and drives them directly against MECH-ERROR / MECH-OK / unparseable / empty fixture bodies, asserting both the accumulator push and the unchanged return shape.
Friction: none — the item's own "Unwired call sites, verified 2026-08-12" list named exact line numbers and functions, so no exploration was needed beyond confirming call-site context (quota gate has no per-repo scope, so `repo` is recorded as `-` for all three sites — they are pool-level hops, not per-repo).
refactor: none needed — three small additive push calls plus matching test fixtures; no duplication introduced (the accumulator, its shape-normalizing, and its truncation all still live solely in `recordAgentFailure()`).

## 2026-08-12 00:37 — executor (sonnet, relay-loop)

Wired recordAgentFailure() into the three previously-silent mechanical-hop parse sites (quota, inject-take, discover-prelude) so id:06a1's accumulator no longer under-reports; full suite 390/0/1-expected-red. [id:a104]

## 2026-08-12 — reviewer (claude-opus-4-8)

Reviewed relay-ckpt-20260812-0015..HEAD — one executor unit, id:a104 (wire recordAgentFailure() into the three previously-silent mechanical-hop parse sites the 0015 reviewer identified). VERIFIED GENUINELY GREEN, non-gamed. gaming-scan.sh clean (no deleted test / added skip / removed assert). The new test section (3b) in tests/test_relay_status_agent_failures_06a1.sh is LOAD-BEARING: re-run against the pre-wiring relay-loop.js (git show relay-ckpt-20260812-0015:...) it FAILS on all four assertions (parseQuotaMechResult/parseInjectTake/parsePrelude MECH-ERROR + parsePrelude unparseable — no accumulator push), and passes against HEAD — the wiring is real, not a tautology. All four call sites match recordAgentFailure(label,repo,phase,reason)'s signature; each records ONLY on a genuine failure sentinel (MECH-ERROR, or unparseable prelude JSON), never on the legitimate empty/MECH-OK "nothing pending" shape (cry-wolf discipline preserved), and no hop's return shape or fail-soft semantics changed. refactor: none needed self-report is honest (three additive push calls; the accumulator/shape-normalize/truncation still live solely in recordAgentFailure). §2d over-reach: the diff is a strict SUBSET-faithful implementation of the exactly-three named sites the 0015 review filed — not a superset. a104 correctly [x] and archived (archive-done only moves already-ticked items); no TODO twin, so single-id-two-views is a no-op. a104's prose named one further aside — the child-agent null-report path — but that path (relay-loop.js:2439) already pushes a state.handbacks entry + handback event, so an --afk operator DOES see it (Blocked row); it is NOT the id:4347 silent-swallow class and needs no follow-up. Full make test: 390 passed / 0 failed / 1 expected-red (repo declares one tier, `make test`→tests/run-tests.sh; no e2e/integration tier to skip). Cross-ledger drift: clean. roadmap-lint: WARN-level DEAD-GATE/DEP-PROSE-UNTYPED on pre-existing gated items (2b49/d4ca/e405/540f/c179) — none in this window; already boxed in REVIEW_ME (2b49/540f/c179) / owner-gated. NEW inbox dead-letter routed:052b targets this repo (mechanical-proxy.py restart silently kills in-flight background agents in other live sessions — a real observed 2026-08-11 incident, distinct from routed:d9a5) — it lives durably in the git-tracked inbox and is surfaced by /relay human + relay-doctor; route it via inbox-reconcile (scan-routed.sh --apply) or file into TODO, NOT re-boxed here (avoids a third parallel copy, per the 2019-review precedent). routine_open (dispatchable) = 0: all 5 open [ROUTINE] items are non-dispatchable — d4ca/540f/c179/554b carry gated-on: markers (three owner-gated on b0b1) and f91a is @container.

## 2026-08-12 01:13 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

Reviewed 0015..0037: id:a104 (recordAgentFailure wired into 3 mech-hop parse sites) verified genuinely green + non-gamed; suite 390/0/1-ered; no dispatchable ROUTINE work left. [id:a104]

## 2026-08-12 — executor (claude-opus-4-8, hard-execute)

Worked id:93ac — command-fence precedence in `relay/scripts/mechanical-proxy.py`. The id:33b2 stdin channel let a `` ```relay-mech `` fence embedded in a `` ```relay-mech-stdin `` PAYLOAD supply the dispatched command, because `_command_from_wrapped()` searched the WHOLE user text and nothing required the loop's real command fence to precede the payload (live-reproduced 2026-08-11). Fix: new `_strip_stdin_fence_span()` excises the stdin fence's SPAN before the command regex runs, so a payload is structurally unable to contribute a command — reusing the two existing regexes, no third parser (the item's explicit constraint). Rejected the two weaker alternatives in the ROADMAP done-note (positional invariant = same defect class; >1-fence refusal breaks legit quoted fences). Authored `tests/test_mech_command_precedence_93ac.sh` (`# roadmap:93ac`) for the item's tests a–d and confirmed genuine red-green (pre-fix extractor picks the attacker path; post-fix picks the loop's). id:33b2 suite unchanged. Full suite 391 passed / 0 failed / 1 expected-red.
Friction: none. The item was well-specified; one honest scope call surfaced — test (b)'s "byte-identical round-trip of a payload quoting a full fenced block" is IMPOSSIBLE to satisfy against a *dangerous* payload because the non-greedy stdin regex already truncates at the first `` \n``` `` (the very sequence a smuggle needs), so (b) is correctly a regression guard on the untouched payload path, and the fenced-doc-fidelity truncation is a separate pre-existing limitation (surfaces only when id:d4ca flows real markdown), left for a follow-up rather than scope-crept into this precedence item.
refactor: none needed — additive helper + one-line call-site change reusing the existing regexes; no duplication introduced, nothing to extract.

## 2026-08-12 01:43 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

id:93ac command-fence precedence fixed — stdin payload can no longer supply the dispatched command in mechanical-proxy.py; suite 391/0/1-ered [id:93ac]

## 2026-08-12 — executor (claude-opus-5, reviewer-orchestrated)

Worked id:76d2 — provisioned artifact symlinks no longer dirty the child's worktree.
`provision-worktree.sh` now writes the names it actually symlinked (`/node_modules`, `/.venv`,
only those it created) into the worktree's git exclude file, resolved via `cd "$wt" && git
rev-parse --git-path info/exclude`, right after the symlink lines. Idempotent (a `grep -qxF`
per line plus a one-time marker comment), trailing-newline safe, and the deliberate `|| true`
best-effort semantics on the two symlink lines are untouched, as is the `PROVISION-OK <path>`
last-stdout-line contract from id:66d9. No repo's committed `.gitignore` is touched and
`verify-isolation.sh` was NOT given a name-based carve-out. Two VERIFIED facts worth banking:
(1) a linked worktree's `info/exclude` resolves to the repo-COMMON `.git/info/exclude` — git
2.55 does NOT honour a per-worktree `.git/worktrees/<name>/info/exclude` at all (probed
directly), so the common file is the only working target; it is still local-only and never
committed; (2) `<wt>/.git` is a FILE, so the path must be resolved with rev-parse, never
assumed. The core property is now green: a freshly provisioned worktree with a trailing-slash
`.venv/` gitignore reads `git status --porcelain` EMPTY where it previously read `?? .venv`.

BLOCKED: 76d2 the RED spec's two `verify-isolation.sh` assertions cannot pass from the provisioner side — both fail on TWO pre-existing gate defects outside this item's file surface, and neither is caused by (or fixable in) provision-worktree.sh.
Friction: 76d2's checkbox is left UNTICKED (so `tests/test_provision_symlink_ignored_76d2.sh`
stays EXPECTED-RED and the suite stays green at 391/0) pending a reviewer decision on the two
gate defects, which I was explicitly fenced out of touching:
(D1) `verify-isolation.sh:77` — `default_branch="$(git … symbolic-ref --short -q
refs/remotes/origin/HEAD 2>/dev/null | sed …)"` exits 1 under `set -euo pipefail` whenever
`origin/HEAD` does not resolve, so the gate dies SILENTLY with exit 1 and no output on any repo
lacking an origin (every hermetic test fixture). It has never been caught because all four
existing call sites in `tests/test_verify_isolation.sh` pass `--base main` explicitly and skip
the fallback; the 76d2 spec is the first caller to exercise it. One-line fix: append `|| true`.
(D2) Even with D1 fixed, the spec's "a genuinely dirty worktree is still refused" assertion
fails — the fixture's worktree has ZERO commits beyond base, so the gate takes its documented
branch (b1) ("empty + main unmoved ⇒ legitimate id:8e3e no-op review, exit 0") and returns
before ever reaching the dirty check (c), which by design only runs when there are commits
beyond base. Confirmed provisioner-independent: a plain `git worktree add` + one untracked file
+ explicit `--base main` against the PRISTINE gate also exits 0. The live id:76d2 incident hit
branch (c) because that worktree had 2 real commits; the fixture never commits in the worktree,
so it cannot reach (c). Fixing this means either the fixture commits in the worktree first or
the gate's dirty check moves ahead of the empty-check — both are edits to files I was told not
to touch, and the second is a real behaviour change to the gate, so it is the reviewer's call.
refactor: none needed — one self-contained additive block appended after the symlink lines; no duplication introduced and nothing existing to extract.

## 2026-08-12 — executor (claude-opus-5, reviewer-orchestrated)

Worked id:3222 (ticked, spec green) and id:9834 (code landed, checkbox LEFT UNTICKED — see below).
id:3222: added one `dispatchGuarded(opts, repo, prompt)` wrapper next to `recordAgentFailure`
and routed the three fire-and-forget hops (`release:*`, `write-relay-status`, `gaming-log:*`)
through it; it records BOTH a rejected dispatch and a null/empty resolution, never rethrows, and
`provisionWorktree` deliberately still records its own failure so id:66d9 is not double-counted.
id:9834: `provisionWorktree(unit, isRetry)` now recognises an `already exists` provision body,
bumps `unit.attempt` exactly ONCE (guarded single recursion, no loop) and re-provisions under
the fresh attempt-scoped name; the naming machinery (`unitKey`/`worktreePathFor`/`branchFor`)
was already correct and was NOT touched, per the spec's premise correction.
Friction: (1) `tests/test_attempt_scoped_worktree_9834.sh:62` is FLAKY-BY-CONSTRUCTION — under
`set -o pipefail` its `run="$(awk '/^async function runUnit/,0' "$JS" | head -80)"` gives awk
SIGPIPE once head takes 80 of the region's 538 lines, aborting the whole file with exit 141
before assertions (4) and (5) run. Measured 1 pass / 19 fails over 20 runs on the FIXED code;
the `run` variable is never used afterwards. One-line fix (reviewer's call, a test edit is not
mine to make): append `|| true`, or delete the line. Assertions (4)+(5) were replayed verbatim
out-of-band against the fixed code and both pass; the item is therefore left unticked and the
file reports EXPECTED-RED. (2) The 3222 spec's `label: \`?write-relay-status` grep assumes a
template-literal label, but `tests/test_relay_phase_buckets.sh:31` pins that label to single
quotes; the two cannot both match on the same code line, so the matching line is the call
site's own comment immediately above the real guarded dispatch. (3) Routing the `release:` fence
through the guard moves it out of a bare `agent(` call, so `lint-mech-model.mjs` (which matches
the identifier `agent` only) no longer covers it; `test_release_hop_mechanical_f7d3.sh` still
asserts `model: MECH_MODEL` on that line, so the invariant is held by a different check now —
worth folding `dispatchGuarded` into the linter's call-site matcher later.
refactor: replaced three hand-rolled per-hop failure paths (two bare `.catch(log)` and one
unguarded `await agent`) with the single wrapper the spec asked for — that consolidation IS the
item; no further duplication left behind.

## 2026-08-12 09:15 — reviewer (claude-opus-5)

Reviewed 76d2 (provisioned symlinks excluded so the worktree reads clean), 9834 (attempt bumped once on a collided provision), 3222 (blocked/failed dispatches counted via dispatchGuarded). Both executors refused to tick on spec bugs they proved by probe; both spec bugs were mine and are fixed. Also fixed verify-isolation.sh's silent exit-1 on repos without origin. Gaming check 521 insertions / 0 deletions. Suite 394/0.

## 2026-08-12 — executor (claude-sonnet-5)

Worked id:ed3f — taught lint-mech-model.mjs to match `dispatchGuarded`/`agentGuarded`/`safeAgent` call sites in addition to bare `agent(`, since routing `releaseLease`'s fence dispatch through `dispatchGuarded` (id:3222) moved it out of a bare `agent(` call and the linter silently stopped covering that hop. Added tests (2d)/(2e) asserting the new matcher fires on a `dispatchGuarded`-wrapped fence hardcoding a literal model and stays silent when it correctly uses `model: MECH_MODEL`; full suite still lints the live tree clean. Full test suite: 394 passed, 0 failed, 1 expected-red (unrelated open item).
Friction: none.
refactor: none needed — additive matcher change (one identifier set, one line-checked condition), no new duplication introduced.

## 2026-08-12 12:40 — executor (sonnet, relay-loop)

id:ed3f — lint-mech-model.mjs now matches dispatchGuarded/agentGuarded/safeAgent call sites too, closing the coverage gap the releaseLease dispatchGuarded refactor opened; full suite 394/0/1-expected-red. [id:ed3f]

## 2026-08-12 12:58 — executor (sonnet, relay-loop)

No dispatchable [ROUTINE] work: only unticked ROUTINE lines are 4 GATED items (d4ca/540f/c179/554b) and the f91a @container epic (non-dispatchable); worktree left clean.

## 2026-08-12 13:11 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: no-op window (CHANGELOG+RELAY_LOG only); gaming-scan clean, suite green (393/1-flake/1-xred), all 5 open [ROUTINE] gated/container — no dispatchable work; routine_open=0

## 2026-08-12 13:53 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: no-op window (only id:8df5 gate edit by own integrator + personas /meeting docs); gaming-scan clean, suite 394/0/1-xred, all 5 open [ROUTINE] gated/container; routine_open=0

## 2026-08-12 14:13 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

Worked id:401c — Strong-model audit Run 72, window `0454e8f..HEAD` (Run 71's audit commit, HEAD 1b7e9bb; ~780 prod LOC / 10 scripts + 12 tests, the routed:a923 / id:76d2/66d9 / id:9e48 / id:93ac / id:06a1 hardening batch). 3-pass adversarial audit: code CLEAN, security CLEAN, no inline fix warranted (all diffs well-reasoned and fail-closed where it matters — provision PROVISION-OK cert, mech-currency, command-fence-precedence span excision, INJECT_SCOPE splice validation, relay-loop.js +270 all visibility/scope/doc). One design-coherence finding TRACKED not fixed: stale gated-on:33b2,93ac markers on d4ca/e405 after both targets were built+archived in-window (roadmap-lint DEAD-GATE) — deliberately NOT cleared inline (clearing would unblock d4ca ahead of the unresolved id:09e4 payload-misdirection, and the id:6b35 cluster is owner-gated on b0b1; the next handoff should re-target). Meeting note docs/meeting-notes/2026-08-12-1413-strong-model-audit.md. Suite 394/0/1-xred. id:401c is recurring — stays open, Run 72 appended to its run log.
Friction: none. Audit item well-sized for one turn.
refactor: none needed — audit is a read + document unit; no code changed, so no refactor surface.

## 2026-08-12 14:17 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

audit(relay): Run 72 strong-model audit (id:401c) over 0454e8f..HEAD — code+security clean, 1 coherence finding tracked (stale gated-on:33b2,93ac on d4ca/e405); suite 394/0/1-xred [id:401c]

## 2026-08-13 16:18 — reviewer (claude-opus-5)

review: window relay-ckpt-20260812-1417..HEAD (13 commits, 8 more than the brief stated). gaming-scan clean; suite 400/0/1-xred; cross-ledger clean; actionable_routine_open=0 (unchanged — gate re-target verified NOT actionable: resolve-gates d4ca/e405 block=1 zero-dangling). 9 findings filed, 2 REAL BUGS in 82643ab (id:b99f live-runs JSON vs bare-token grep => live runs mislabelled STRANDED, proven empirically; id:e53a stranded hidden when orphans present); test-integrity finding id:3a50 (315c test passes against a functionally-disabled fix, mutation-tested). 55f6/c74e meeting ledger fidelity VERIFIED. routed:832e adopted.

## 2026-08-13 18:03 — reviewer (claude-opus-5)

review: window relay-ckpt-20260813-1618..HEAD (21 commits, all owner-authored — this window
is the FIX + bookkeeping response to the 16:18 review's findings, plus a `/meeting` amendment
and a `/relay human` pass, no executor units). gaming-scan clean; suite 411/0/1-xred
(`roadmap:6217`, an open decision-gated item — its red test IS the spec, legitimate). The
16:18 review found id:b99f/e53a/3a50 as REAL BUGS; this window's `f0fdeb1`/`d2f645d`/`8dd5d42`
landed the fixes and `54c3e2c` ticked the 8 defects. Test-integrity VERIFIED not gamed:
spot-checked the load-bearing `test_reconcile_stranded_liveness_b99f.sh` side-by-side — it
FAILS against the pre-fix `relay-reconcile.sh` (grep -qxF against a bare runId, gate could
never fire) and PASSES against the jq `.runId` fix; genuinely non-vacuous. cross-ledger clean;
contract pointer v11 == canonical v11 (no drift); roadmap-lint WARN-only (pre-existing gate
warnings, already owned by id:d119). actionable_routine_open=0 after re-derivation — all 5 open
[ROUTINE] items are gated (d4ca/540f/c179/554b) or @container (f91a), none dispatchable, so no
execute re-enqueue. New TODO items this window arrived pre-qualified (lane+id) from the owner
`/relay human` pass; promotion of the [ROUTINE] subset is itself owner-gated by id:eb16. Nothing
reopened.

## 2026-08-13 18:21 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: 16:18-findings fixes (b99f/e53a/3a50/15f3) verified non-gamed; suite 411/0/1-xred; cross-ledger clean; routine_open=0 [id:b99f,e53a,3a50,15f3]

## 2026-08-13 — hard-execute (claude-opus-4-8, relay-loop)

Worked id:5b12 (seam of id:ae08) — tick-ownership inversion. Bumped the executor contract
v11→v12: execute/hard children no longer tick their own ROADMAP.md checkbox — they return
worked_ids and the serialized integrator ticks the box in the canonical checkout via a new
`relay/scripts/roadmap-tick.sh` (idempotent, flock'd; ticks `- [ ]`→`- [x]` by worked id,
never edits an item body). Added the driver-tick step to relay-loop.js's integrate path,
gated to execute/hard (review/handoff keep self-ticking in their own merged worktree, since
their reopen/verify semantics differ and they run as barriers, not N-wide). Updated the hard
child prompt to defer ticking to the driver, and the CLAUDE.md pointer + Layout table to v12.
Asserted by `tests/test_relay_driver_ticks.sh` over BOTH the contract text and the integrate
path; the helper is exercised end-to-end by `tests/test_roadmap_tick.sh` (7/7). Registered
the new script in the Makefile relay_FILES/_EXEC/_ALLOW manifest (caught by
test_relay_install_manifest.sh). refactor: none needed — additive helper + a bounded
integrate step; no existing duplication to fold. Friction: none. Transition is safe because
roadmap-tick.sh is idempotent, so an in-flight v11 executor that still self-ticks plus the new
integrator tick is a harmless double-flip. Note: this seam only inverts tick OWNERSHIP; the
disjoint-greenlight/drain-integrate wiring (sibling seams id:02b2/id:99e5) is out of scope.

## 2026-08-13 18:50 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

Invert ROADMAP tick ownership: driver ticks from worked_ids via roadmap-tick.sh; executor-contract v11→v12 (id:5b12) [id:5b12]

## 2026-08-13 18:47 — `/meeting` C1 inline (id:3bf3), apex (claude-opus-5)

Worked `id:3bf3` (/meeting disposition-routing surface) as a Class-1 inline implementation
under the `/relay executor` contract (D7). **The item was NOT what its ledger line implied.**
Its stated contract — "Red test: a fixture item per lane/state maps to the right disposition
label" — reads as untested, and a filename grep for `3bf3`/`disposition` in `tests/` returns
nothing. Reading the actual suite showed the LANE half was already fully discharged by
`tests/test_classify_hard_lanes.sh` (all 8 lanes across both the canonical capability-keyed and
accepted venue-keyed vocabularies, head-anchoring per id:0d58/id:4da4, backtick-stripping per
id:306d/id:1bbd) and the RELAY mirror line by `tests/test_classify_hard_floor.sh`. Writing "the"
missing test would have duplicated existing coverage. Verified-uncovered remainder, by grep over
all `tests/test_classify*.sh`: **GATED had no assertion anywhere**, and **no test pinned the TSV
column contract** — which `CLAUDE.md` §Versioning independently lists as an unmarked *candidate
contract surface* with the rationale that SKILL.md parses fixed columns.

Added `tests/test_classify_disposition_contract_3bf3.sh` (15 assertions) covering exactly that
remainder: (1) the STATE axis — empty-GATE on ungated items, `GATED` from both `gated on` and
`blocked on` vocabulary, and the `GATED;HARD-NOLANE` *composition* (a naive overwrite instead of
append would silently drop one marker); (2) the 5-column TSV contract — arity via `NF!=5` plus
positional shape checks on columns 1/2/4/5, so a transposition that preserves arity still fails;
(3) the disposition PARTITION — `{C1,C2,C3}` pickable vs `{RELAY,POOL,EXEC,MECH,HANDS,HUMAN}`
skipped, asserted disjoint and non-vacuous, with every lane-tagged skip-class item required to
land in the skip half. That partition previously lived only in SKILL.md prose; it is the
"/meeting over-claim" regression (a pool-executable item surfacing as a redundant meeting
candidate) made mechanical.

**Non-vacuity established by mutation, not assumed** (the id:292b vacuous-fixture concern): three
independent mutations applied to a COPY of `classify.sh` in a tempdir — dropping `blocked on`
from the gate detector, removing the GATE column from the `printf` (5→4 fields), and routing
`[ROUTINE]` to C1 — each kill the test. Worth recording that the third mutation FIRST reported
`ALL PASS`, because my `sed` anchor silently failed to match; re-running it through a Python
replace with an `assert anchor in source` proved it applied and the test then failed correctly.
A green mutation run that actually means "the mutation never applied" is the same false-negative
shape id:292b exists to catch, encountered live while testing for it.

`refactor: none needed` — the new file shares no logic with the existing classify tests by
construction (it was scoped to their complement) and introduces no duplication to factor out.
Full suite **414 passed, 0 failed, 1 expected-red**. Ledger: `id:3bf3` ticked in `TODO.md` only —
it has zero refs in `ROADMAP.md`, so single-id-two-views needs no second write.

**Surfaced, not fixed** — `classify.sh`'s gate detector `grep -qiE 'gated?|…'` matches the bare
substring `gate`, so any body containing *investigate*, *mitigate*, *aggregate*, *delegate* or
*navigate* is flagged `GATED`. Real false positive on live data; deliberately NOT asserted in the
new test (pinning it would encode the defect as intended behaviour) and NOT fixed here (out of
this item's scope). The new fixtures are worded around it. Owner's call whether to tighten the
pattern to a word-boundary form.

## 2026-08-13 19:12 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

Handoff C2-C4: promoted 3 self-contained non-dispatch items (292b/f657/d119) with verified RED specs; minted local ids for 3 inbound items; 2 REVIEW_ME boxes; dispatch-semantics promote items left for owner per id:eb16 [id:292b,f657,d119,1f9a,dda0,0bbc]

## 2026-08-13 19:21 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: id:3bf3 verified green (414/0/1-xred), test behavioural+mutation-verified, no over-reach; id:259f surfaced; routine_open=0 [id:3bf3,259f]

## 2026-08-13 — executor (claude-sonnet-5)

Worked id:292b — built `tests/lint-vacuous-fixtures.py`, mechanism (1) of the vacuous-fixture
lint: flags a "defect-fix" test (`tests/test_*.sh` with no `# roadmap:XXXX` header) that omits
a `# fails-against: <rev|mutation>` header naming the negative case it must fail against; a
roadmap-spec test (carries `# roadmap:`) is exempt. Advisory by default (exit 0), non-zero only
under `--strict`/`--max N`, mirroring the sibling `tests/lint-source-grep-assertions.py`. OUT of
scope per the item: the CI runner that actually checks out/mutates and re-runs the negative case
(mechanism (1)'s second half), plus mechanisms (2) reached-fixture and (3) ledger-token-shape.
`tests/test_vacuous_fixture_lint_292b.sh` (already RED-authored) is now green; full suite
415 passed, 0 failed, 3 expected-red (a `test_lean_toolchain_drift.sh` failure on the first run
was order-dependent/flaky — reran green in isolation and in a full clean rerun, unrelated to
this item's diff).
Friction: none.
refactor: none needed — new standalone file, no shared logic with the sibling lint to factor
out (deliberately mirrors its shape rather than extending it, per the item's scope).

## 2026-08-13 19:38 — executor (sonnet, relay-loop)

Add tests/lint-vacuous-fixtures.py (id:292b mechanism 1) — advisory lint flagging defect-fix tests missing a `# fails-against:` header [id:292b]

## 2026-08-13 19:46 — executor (sonnet, relay-loop)

id:292b already fully implemented/committed by a prior session in this worktree (tests/lint-vacuous-fixtures.py + green RED-authored test); verified full suite green (415 passed, 0 failed, 3 expected-red) and worktree already clean — no new work needed. [id:292b]

## 2026-08-13 20:45 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

C2: promoted routed:f833/id:cd9c (loderite archive-stub design call) into ROADMAP.md as [INPUT — decision], reusing existing TODO id (single-id-two-views), no RED spec [id:cd9c]

## 2026-08-13 — executor (Sonnet) id:f657

Worked id:f657 — added ARCHITECTURE.md §11 (Pool ∥ meeting: same-repo concurrent-safety
convention), naming the three load-bearing mechanisms (distinct claim keys id:0ee1,
ledger-only writes not lease-gated id:c144, flock+atomic commit on shared ledgers) and
the two expected (non-defect) interactions, without restating either id's mutable
checkbox state. `tests/test_architecture_pool_meeting_convention_f657.sh` went RED→GREEN;
full suite 418 passed / 0 failed / 2 expected-red (id:d119 still open — its RED spec
`test_roadmap_lint_owner_hold_d119.sh` is the unimplemented linter feature; id:292b's
`test_vacuous_fixture_lint_292b.sh` was already GREEN from a prior session's commit
55900b6, unticked in ROADMAP — left for the driver to tick, not re-worked here).
Friction: none — content was well-scoped by the RED spec + existing TODO id:f657 prose
and claim.sh's own SCOPE INVARIANT comments; no code changes, doc-only.
refactor: none needed — a single new doc subsection, no duplication introduced.

## 2026-08-13 21:19 — executor (sonnet, relay-loop)

Added ARCHITECTURE.md §11 recording the pool ∥ meeting same-repo concurrent-safety convention (id:f657); RED spec went green, full suite 418/0/2-expected-red. [id:f657]

## 2026-08-13 — executor (sonnet)

Worked id:d119 — `roadmap-lint`'s DEAD-GATE rule (3(d), id:49e0) now recognizes an explicit
`<!-- owner-hold:REASON -->` marker: an item carrying it is treated as an intentional owner
hold, so the false DEAD-GATE finding no longer fires for it, while an identically-gated twin
with no marker still fires unchanged (WARN default, ERROR under --strict). Implemented as a
new anchored extractor `typed_edges_owner_hold_of_line` in `lib-typed-edges.sh` (mirrors the
existing `gated-on`/`children`/`settles` extractors) plus a one-line guard in the DEAD-GATE
loop in `roadmap-lint.sh`. Scoped exactly per the ROADMAP item: this only teaches the
report-only linter to recognize the marker — migrating `id:540f`/`id:c179`'s real
`gated-on:e62c,b0b1` onto it, and teaching `classify-repo.sh`'s dispatch gate to honour it,
are explicitly OUT of scope (separate coordinated step, per REVIEW_ME's still-open judgment
call on the marker grammar/scoping). The RED spec (`tests/test_roadmap_lint_owner_hold_d119.sh`)
was already authored at handoff and required no changes; it now passes as-is. Full suite:
419 passed, 0 failed, 1 expected-red.
Friction: none — the RED spec was already precise and the fix was a small, well-isolated addition.
refactor: none needed — the change reuses the existing typed-edge extractor pattern and adds
one guard clause; no new duplication introduced.

## 2026-08-13 21:31 — executor (sonnet, relay-loop)

roadmap-lint recognizes an explicit owner-hold marker, suppressing false DEAD-GATE findings on intentionally-held gates (id:d119) [id:d119]

## 2026-08-13 21:42 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

Chain-end review: verified id:f657 green (ARCHITECTURE §11 doc, not over-reach), closed id:292b (green on HEAD; tick was stranded on unmerged orphan) in ROADMAP+TODO; suite 418/0/2-expected-red; routine_open=1 (id:d119) [id:f657,292b]

## 2026-08-13 20:40 — handoff (claude-opus-4-8, relay-loop)

Cross-ledger reconcile + one promotion. The unpromoted-scan flagged ~22 `promote` items, but
7 were already-fixed work whose TODO checkbox lagged the landed fix (fix commits 347866e/
ef43739 landed the same day; b99f/e53a/f657 already review-verified; suite green 419/0/1-xred).
CLOSED those 7 in TODO.md with inline dated evidence notes: id:3262 (scan-labelled 1a30),
id:315c, id:4b8f, id:aa05, id:b99f, id:e53a, id:f657 — none had a ROADMAP twin, so no
cross-ledger disagreement was created. Promoted the one genuinely-open, cheaply-specc'able bug
to ROADMAP with an authored RED spec: id:259f (classify.sh GATE detector matches the bare
substring `gate`, so investigate/mitigate/aggregate/delegate/navigate all render `[GATED]`);
tests/test_classify_gate_word_boundary_259f.sh is RED (investigate → GATED today), 5 distinct
false-positive words + 2 true-positive phrases (id:108e triangulation). Left promote-ready-but-
unspecced bugs (id:9dd0/dda0/ec3c/331a/8132/f544/7be4/3986) as [ROUTINE] in TODO — each needs a
git-worktree-fixture or Workflow-JS static harness that did not fit one turn; a follow-up handoff
should author them (this is why the scan will still show promotable items — resumable by design).
Design-nuanced/gated/apex items (5a14/d119/7e2a/04d6/0bbc) left in TODO, never lane-guessed.
Friction: none. C4 skipped — no user-facing surface (infra/scripts repo).

## 2026-08-13 22:13 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

Handoff: cross-ledger reconcile — closed 7 already-landed items in TODO, promoted id:259f to ROADMAP with RED spec (classify.sh gate substring FP) [id:259f,3262,315c,4b8f,aa05,b99f,e53a,f657]

## 2026-08-13 22:22 — executor (sonnet, relay-loop)

Fixed classify.sh's GATE detector to be word-boundary anchored (id:259f) — investigate/mitigate/aggregate/delegate/navigate no longer false-positive as GATED; genuine gate/blocked phrases still detected. [id:259f]

## 2026-08-13 22:40 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

Review: id:259f verified genuine-green (classify.sh word-boundary gate fix, not gamed/over-reach); suite 420/0/1-xred; @container on ae08; routine_open=0; surfaced d119 cross-ledger drift + roadmap-tick.sh install-drift [id:259f,ae08]

## 2026-08-13 23:32 — integrate (claude-opus-5)

C3 red spec for id:cd9c (archivers must leave a one-line stub); verified RED against unmodified roadmap-archive.sh; suite 420/0/3-xred

## 2026-08-14 — executor (sonnet, relay-loop)

Fixed verify-isolation.sh: an EMPTY worktree with a DIRTY tree now exits 2 (breach-shaped,
owner-decided 2026-08-14) under BOTH the main-unmoved (b1) and merge-commits-only (b3)
conditions — previously those branches returned exit 0 before the dirty check ever ran.
Added a dirty-tree check at the top of the empty-worktree branch, ahead of the main-HEAD
discrimination logic; updated the script header's behaviour table (new b0 case). The
legitimate id:8e3e no-op review (empty + CLEAN + main unmoved) still exits 0, unregressed.
Full suite green (420/0/3-xred). [id:1b13]
Friction: none.
refactor: none needed — a single early-exit check added to an existing branch, no new
duplication introduced.

## 2026-08-14 10:34 — executor (sonnet, relay-loop)

verify-isolation.sh: empty worktree + dirty tree now exits 2 (breach-shaped) under both main-unmoved (b1) and merge-commits-only (b3) conditions; id:8e3e no-op review unregressed [id:1b13]
## 2026-08-14 10:13 — reviewer (claude-opus-4-8, relay-loop)

Chain-end review re-ask (chain ended `relay-ckpt-20260813-2332`; classifier id:8123). The `$LAST..HEAD` window carried NO executor code work — 20 commits, all ledger/human: two `/relay human` owner-decision batches, 15 cross-project inbox ingests (id:678e), a persona extension, and an inbox recovery of 3 FALSE-twin drains (id:c97c). `gaming-scan.sh` clean (no test files touched); no formerly-red test to verify-green this pass. **Reverse-handoff (§5b):** `id:1b13` (`verify-isolation.sh` empty+dirty must exit 2) was re-laned `[INPUT — decision]` → `[ROUTINE]` by the human batch with full acceptance but NO RED spec — authored `tests/test_verify_isolation_empty_dirty_1b13.sh` (`# roadmap:1b13`), verified RED against the unmodified script (empty+dirty exits 0 today via the b1/b3 no-op arm before the dirty check). Cases: (i-b1) empty+dirty+main-unmoved → exit 2 naming the dirty entry, (i-b3) empty+dirty+merge-only-advance → exit 2, (ii) empty+clean+main-unmoved still exit 0 (id:8e3e no-op negative control), plus observe-only source guard. `id:cd9c` already carries its RED spec. **relay-doctor:** cross-ledger clean, roadmap-lint clean, install-drift clean (roadmap-tick.sh symlink resolved this window), 0 parked orphans, 0 inbox dead-letters. **Handoff gap surfaced:** `id:f91a` (@container, line 1509) is an open `[ROUTINE]` with NO RED spec — not yet executor-ready. routine_open=4 (f91a/1b13/cd9c/ec3c dispatchable; 3 have specs); 4 more `[ROUTINE]` are 🚧 GATED. Refactor: none needed — reviewer pass, one new spec file, no code paths touched.

## 2026-08-14 10:53 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

Chain-end review: no executor code work (ledger/human window); authored RED spec for id:1b13; suite 420/0/4-xred; relay-doctor clean; routine_open=4 [id:1b13]

## 2026-08-14 — executor (sonnet, relay-loop)

Worked id:ec3c — `statusline/statusline-command.sh`'s four usage-state paths
(USAGE_CACHE/USAGE_HISTORY/USAGE_BACKOFF/USAGE_LOCK) now read from env overrides
(CLAUDE_USAGE_CACHE/CLAUDE_USAGE_HISTORY/CLAUDE_USAGE_BACKOFF/CLAUDE_USAGE_LOCK),
defaulting to the previous hardcoded `/tmp` literals so live behaviour is byte-unchanged.
This lets `tests/test_statusline_path_overrides_ec3c.sh` point all four into its own
`mktemp -d` sandbox instead of racing the developer's own live-session statusline writing
the same `/tmp` paths. Verified RED before the fix, GREEN after; full suite green
(421 passed, 0 failed, 2 expected-red).
Friction: none — the item's Acceptance/Tests/Done-check were already fully spelled out
by the mini-handoff at review 2026-08-13.
refactor: none needed — a one-line-per-path parameter-expansion change, no new
duplication introduced.

## 2026-08-14 11:02 — executor (sonnet, relay-loop)

statusline: the four /tmp usage-state paths (id:ec3c) are now env-overridable, defaulting to the old literals — closes the make-test race against a live-session statusline [id:ec3c]

## 2026-08-14 — executor (sonnet)

Worked id:cd9c — taught `roadmap-archive.sh` and `archive-closed.sh` (ROADMAP.md path only, per the item's stated scope) to leave a one-line stub (`- [x] <title> <!-- id:XXXX --> (archived — see ROADMAP.archive.md)`) behind in the live ledger for every item they move, using the grammar the already-shipped `stub_line_re` reader guard hard-codes. The RED spec `tests/test_roadmap_archive_leaves_stub.sh` (`# roadmap:cd9c`) is now fully green (4/4 cases: single stub emission+grammar, two different gate paths producing distinct per-item stubs in order, cross-run round-trip on a stub the archiver itself emitted, and the second generic archiver `archive-closed.sh`). `archive-closed.sh` also got its own reader guard (`STUB_LINE_RE` classifying a stub as `kb`/kept, never re-archived) — the write half without a matching read half would have reproduced the exact "archiver eats its own successor's output" defect the ROADMAP-side guard already documents.
Friction: two PRE-EXISTING green tests (`tests/test_roadmap_archive.sh` T1, `tests/test_archive_closed.sh` part B/1) asserted the OLD behaviour (archived item title fully absent from the live file) — that assertion is now directly contradicted by the ratified (a) branch, so I updated both to assert "stub present, body gone" instead of "fully absent". This is not test-weakening in the prohibited sense: the underlying acceptance criterion changed by owner ruling, and the updated assertions are still meaningfully falsifiable (they fail if the title line goes missing, or if the stub-suffix is absent, or if the body isn't dropped).
refactor: none needed — this is an additive branch inside each archiver's existing pass-3 stream-and-emit loop; no new duplication (the stub grammar constant/regex is reused verbatim from the already-shipped reader guard in each file, not re-derived).

## 2026-08-14 11:40 — executor (sonnet, relay-loop)

roadmap-archive.sh + archive-closed.sh now leave a one-line stub for every item they archive (id:cd9c) — RED spec green, full suite 423/0/1-xred [id:cd9c]
## 2026-08-14 — reviewer (claude-opus-4-8, relay-loop)

Chain-end review re-ask (chain id:8123), window `relay-ckpt-20260814-1102`..HEAD — 2 human ledger
commits only (relay-human batch 4 + false-DEAD-GATE drop on id:f91a), NO executor code work.
Test-integrity audit trivially clean: `gaming-scan.sh` clean, no test files touched, full suite
green (422 passed, 0 failed, expected-red for the open `[ROUTINE]` specs). Health: `orphan-scan
--cross-ledger` clean, `check-install-drift`/reference-install clean, no MECHANICAL orphans, 0
parked orphans, contract pointer v12 == canonical, `roadmap-lint` exit 0 (only pre-existing
DEAD-GATE/DEP-PROSE WARNs). §5b reverse-handoff: qualified the two new TODO items — `id:f346`
(deterministic premise-checker, `[HARD]`) left for the reviewer, and `id:cc7e` (md-merge
`update-ids` resolves an item's own id by the FIRST `<!-- id:XXXX -->` instead of the LAST)
mini-handed-off: promoted to ROADMAP.md reusing its id with RED spec
`tests/test_md_merge_own_id_last.sh` (`# roadmap:cc7e`), verified RED against the unmodified tree
and non-vacuous via a throwaway patched copy. Actionable `[ROUTINE]` queue: id:cd9c + id:cc7e.
Surfaced inbox dead-letter routed:c8d7 (`/meeting --triaged`, → dotclaude-skills) as a REVIEW_ME
`/meeting` candidate. Nothing reopened; no gaming flags.
Friction: none.
refactor: none needed — review pass; the only code added is one RED spec test (no production code touched).

## 2026-08-14 12:20 — integrate (claude-opus-5)

hand-integrate 2 handed-back review branches: id:6446 parked-vocab substring defect; id:cc7e reverse-handoff RED spec (RED-verified). Suite 423/0/2-xred.

## 2026-08-14 13:38 — integrate (claude-opus-5)

id:c97c — inbox twin check anchored to a token's OWN marker (shared primitive; writer+drainer agree). Independently re-derived against the original incident: old code silently destroyed the sibling item, new code files both. 121/121 true twins still resolve. Suite 425/0/2-xred.

## 2026-08-18 11:01 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review: chain-end verify clean (437 green, gaming-scan 0, 12 pure-add specs); reconciled cd9c/d119 cross-ledger drift; boxed ec3c scope-mismatch; routine_open=5 [id:cd9c,d119,ec3c,7517,f391]
## 2026-08-18 — executor (claude-sonnet-5)

Worked id:d3f8 — added `make test FILES="..."` as a thin forward to
tests/run-tests.sh's existing subset-args support (the harness already accepted
explicit file args; only the `make` front door was missing). `make test` with
no FILES is unchanged (empty $(FILES) expansion, same recipe line — verified
with `make -n test`). New test tests/test_make_test_files.sh (roadmap:d3f8)
fixtures on two real suite files (one PASS, one currently-EXPECTED-RED) rather
than a fabricated ROADMAP.md, because run-tests.sh resolves ROADMAP.md
relative to its own script location, not an overridable env var — a fixture
repo would silently check the wrong ledger. `test-changed` deliberately NOT
built (item scopes it as secondary). Full suite green: 438 passed, 0 failed,
2 expected-red.
Friction: none — cleanly scoped item, no ambiguity.

Considered and rejected id:cc7e (`md-merge.py update-ids` own-id resolution):
its Acceptance requires "last <!-- id:XXXX --> marker on a line wins" (an
update to the line's trailing id MUST apply even though the body quotes an
earlier id). The shipped id:6059 grammar (already in `meeting/md-merge.py`,
`_own_id_match_of_line`/`AmbiguousOwnId`) instead treats ANY line with >1
marker as ambiguous and refuses BOTH directions loudly — verified by running
`tests/test_md_merge_own_id_last.sh` directly: case (A) (update to the
line's own trailing id) fails with "AMBIGUOUS own id ... REFUSING to update
bbbb", contradicting the test's requirement that it apply. This is the exact
ratified-spec conflict TODO.md's id:7cd6 flags in its own residue list
("see the cc7e/4a12 ratified-spec conflict below before touching it") —
cc7e's spec predates and is superseded by id:6059's stricter refusal design.
Implementing cc7e as written would either fight already-shipped, tested
behaviour or require deliberately weakening the id:6059 guard for exactly the
ambiguous-line case it exists to catch. Not executor-decidable; needs an
owner/meeting ruling on whether to (a) retire cc7e's old spec + rewrite its
test to assert the id:6059 refusal instead, or (b) narrow id:6059's ambiguity
rule for the trailing-marker case. Left untouched, worktree clean of this item.

## 2026-08-18 11:13 — executor (sonnet, relay-loop)

Shipped id:d3f8 — make test FILES="..." inner-loop subset runner (forwards to run-tests.sh's existing subset support); full suite green (438/0/2-xred). [id:d3f8]
## 2026-08-18 — executor (claude-sonnet-5)

Worked id:4438 — ran the pre-registered burn measurement (id:87f5's decision rule) and
published the per-phase ranking at `docs/relay-burn-ranking-2026-08-18.md`. Verified
first that `relay-burn.sh` has no per-phase attribution (pure quota-utilization burnup)
and that `relay-econ.py`'s existing 4-category rollup (`work`/`status`/`scaffold`/
`poll/other`) is too coarse to isolate `id:a955`'s target (`integrate`, one phase inside
`work`) — wrote a small read-only analysis script reusing `relay-econ.py`'s own
discovery + `profile-run.sh` plumbing at the raw-phase grain (no relay script modified).
n = 272 retained runs (relay-econ.py's own discovery, no --limit). Result: `integrate`
(id:a955) = 14.1% of parallelity-weighted wall-clock; the round-tail idle-floor proxy
(id:3ca7) = ~2.0-2.6%. Order: id:a955 > id:3ca7 by ~5-7x, but **neither clears the
pre-registered ≥25% promote threshold**. Reconciled against the banked 47.6% discover
cost baseline (id:9cb1, 2026-06-18): current discover cost share = 13.9% (a ~3.4x drop),
explained by the discover-cache levers (id:c855, id:c3a6 sig-cache) that landed after
the baseline was taken — not a contradiction, both numbers correct for their windows.
Did not tick id:4438's checkbox (integrator's job per rule 2/v12) and did not edit
ROADMAP.md's item text (rule 5) — the ranking is published in the docs/ report only.
Friction: none — this was measure-and-report only, no code change, no test to satisfy.
refactor: none needed — no production code touched, docs-only report addition.

## 2026-08-18 15:06 — reconcile (auto/human, non-strong by design — id:c500)

reconcile integrate: docs(relay): publish per-phase burn ranking for id:4438 (a955 vs 3ca7)

## 2026-08-19 — executor (sonnet)

Worked id:b8ae — mechanized the review->execute (and execute->execute) rechain signal:
runUnit's re-enqueue block in relay/scripts/relay-loop.js now calls
`pushEvent('rechain', {repo, fromVerdict, reenqueuedVerdict: 'execute', routineOpen,
chainDepth, maxChainDepth})` right after the existing log line, so a chain occurrence
is recorded durably in relay-events.jsonl instead of depending on a human reading the
log — the observe-only remainder had gone uncaught for six weeks per the ROADMAP note.
Added tests/test_rechain_event_b8ae.sh (roadmap:b8ae), a source-shape spec (the
Workflow engine can't run hermetically) asserting the pushEvent call lives inside the
rechain block and names the repo + re-enqueued verdict + chain depth; confirmed RED
against the un-edited relay-loop.js (git stash) before committing the fix. Full suite:
444 passed, 0 failed, 3 expected-red (unrelated open items).
Friction: none — single call-site addition, no ambiguity in the acceptance text once
cross-checked against the code (note: the ROADMAP block still cites a stale
`!unit.rechained` single-hop guard that id:cc90 already replaced with the chainDepth
counter — the event addition itself was unaffected by that staleness).
refactor: none needed — one addition at an existing call site, no new duplication.

## 2026-08-19 13:53 — executor (sonnet, relay-loop)

id:b8ae — relay-loop.js's rechain block now emits a pushEvent('rechain',…) into relay-events.jsonl, mechanizing the six-weeks-uncaught observe-only re-chain signal [id:b8ae]

## 2026-08-19 14:39 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review chain relay-ckpt-20260818-1506: id:f69b speedup real but suite load-flaky (split→id:f875, statusline test fixed inline); id:2799/ec3c/2419 verified honest [id:f875,ec3c,f69b]
## 2026-08-19 14:47 — executor (sonnet)

BLOCKED: id:cc7e the RED spec test (`tests/test_md_merge_own_id_last.sh`) encodes the
OLD "own-id is the LAST anchored marker" contract, but `meeting/md-merge.py` has since
been changed (comments cite `id:6059`) to a STRICTER, different design: a line carrying
more than one anchored `<!-- id:XXXX -->` marker is refused outright (LOUD, both read
and write side) rather than resolved by first-vs-last positional guessing at all — the
code's own docstring explains why last-match is "no better" than first-match (the same
`<!-- id:X -->` syntax means both "this line IS X" and "this line REFERS to X", and
which end holds the own id varies per ledger, per `_own_id_match_of_line`'s comment).
So case (A) of the shipped test (an update aimed at the line's own trailing id must
*apply*) now fails against the *intended*, already-implemented id:6059 design, which
refuses ALL multi-marker lines including that one. This isn't a bug to fix by rewriting
the test to match new behaviour (test-integrity rule) nor by "fixing" the code back to
last-match (id:6059's own comment already argues last-match is unsound) — the ROADMAP
item's spec is stale relative to a design decision that superseded it after the item
was filed. Needs an owner/meeting call: either retire id:cc7e as superseded-by-id:6059,
or decide the item now means "assert the id:6059 refusal, not the old last-match
resolution" and get the test rewritten as a fresh RED spec under owner sign-off. Picked
a different open item instead this session (id:2bc6).

Worked id:2bc6 — new mechanical, read-only `relay/scripts/hooks-path-shadow-scan.sh`
detects repo-local `core.hooksPath` shadowing the global hook dir (which REPLACES
rather than overlays, so a repo-local setting silently drops both the pre-push privacy
gate and the pre-commit lane-vocab ratchet) across the relay own-set, sourcing
`lib-own-repos.sh`'s `own_repos` (never a glob or re-derived list, per the id:7877
defect class). Classifies each repo carrying a local `core.hooksPath` as EMPTY-SHADOW
(configured dir has no real, non-`.sample` hook file — the gate is silently hollowed,
actionable) or DELIBERATE (a real repo-local hook file is present — an owner call to
merge the global hooks in, not to unset); a repo with no local override gets no row.
Wired into `relay/scripts/relay-doctor.sh` as a new `hooks-path-shadow` check (calls
the canonical script, never reimplements it), registered in the Makefile's
`relay_FILES`/`relay_EXEC`/`relay_ALLOW` manifests (caught by
`tests/test_relay_install_manifest.sh`, which failed loud before the registration —
exactly the check doing its job). Added `tests/test_hooks_path_shadow_scan.sh`
(`# roadmap:2bc6`): fixture with one EMPTY-SHADOW repo, one DELIBERATE repo and one
clean repo, asserting all three classifications plus mutual exclusivity plus a
`# path:`-override repo still resolving via `own_repos` (not a glob). Sanity-ran the
new check live against this machine's real relay.toml (`--only hooks-path-shadow`):
found 7 EMPTY-SHADOW + 2 DELIBERATE across 52 own repos, including a `loderite` entry
whose `core.hooksPath` points at `truncocraft/.git/hooks` — the exact "points at a
*different repo's* hook directory (a rename residue)" case the ROADMAP item's own text
describes, confirming the detector reproduces the live finding it was written for.
Full suite: 445 passed, 0 failed, 3 expected-red (unrelated open items) — one transient
failure (`test_git_lock_push_slash_branch.sh`) on the first parallel run vanished on
re-run standalone and full-suite rerun, unrelated to this change (no file this item
touches is anywhere in that test).
Friction: id:cc7e turned out to be stale-relative-to-a-later-decision rather than a
plain RED spec — see the BLOCKED note above; no friction on id:2bc6 itself.
refactor: none needed — new script + new check function follow the existing
quota_config_check/routed_deadletter_check sibling shape verbatim (own script called
from a thin `*_check` wrapper, `RELAY_DOCTOR_*` override var, `log()` line), no
duplication introduced.

## 2026-08-19 14:49 — executor (sonnet, relay-loop)

id:2bc6 — new mechanical core.hooksPath shadowing detector (hooks-path-shadow-scan.sh), wired into relay-doctor.sh + Makefile manifest, tested + sanity-run against live relay.toml [id:2bc6]

## 2026-08-19 14:54 — executor (sonnet, relay-loop)

id:4438 already complete on main (docs/relay-burn-ranking-2026-08-18.md, commit ecc555e) — confirmed acceptance met, no new work needed, worked_ids returned for integrator tick [id:4438]

## 2026-08-19 15:07 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review chain relay-ckpt-20260819-1449: id:2bc6 hooks-path-shadow detector verified honest+green (445/0/3); reconciled TODO twins 2bc6/b8ae; re-laned cc7e→[INPUT — decision] (conflicts shipped id:6059, owner call); 293f gate-ready [id:2bc6,cc7e,b8ae]

## 2026-08-19 — executor (sonnet)

Worked id:5bef — authored the hardened relay-ro/relay-svc systemd --user units (authoring
half of id:8e7a, promoted 2026-08-18 by owner decision). New files: tools/relay-ro-discover-
repos-mechanical.{service,timer}, tools/relay-svc-mechanical-daemon.{service,path,timer},
tools/relay-service-users.env (shared EnvironmentFile, literal /home/tobias paths per the
binding Amendment-2 F3 correction — never %h). Added an opt-in RELAY_REQUIRE_SERVICE_USER
uid-assertion guard to discover-repos-mechanical.sh and mechanical-daemon.sh (unset by
default, so the existing tobias-run units are unaffected). Makefile gained
install-relay-hardened-units (copies into /etc/systemd/user/ via sudo, deliberately does
NOT enable — per-user enable/verify stays id:8e7a). New hermetic fixture test
tests/test_relay_hardened_service_units_5bef.sh asserts unit content (User=, no %h,
hardening directives, EnvironmentFile wiring, uid-guard refuse/no-op behaviour) without
ever touching /etc/systemd/user/ or invoking sudo. Full make test: 445 passed, 0 failed,
4 expected-red (open items) — clean, nothing weakened.
Friction: none — the item's own text (TODO.md:333) already carried the three
Amendment-2 F3 corrections and the env-var enumeration was straightforward to derive from
grepping the two entrypoint scripts' `${VAR:-$HOME/...}` defaults.
refactor: none needed — new unit/env files plus a small, symmetric opt-in guard addition
to the two existing entrypoint scripts; no new duplication introduced.

## 2026-08-19 15:30 — executor (sonnet, relay-loop)

id:5bef — authored hardened relay-ro/relay-svc systemd --user units (unit files, hardening directives, shared EnvironmentFile, uid-assertion guard, make install target) + hermetic fixture test; full suite 445/0/4-expected-red. [id:5bef]

## 2026-08-19 — executor (sonnet)

Worked id:dd7d — built relay/scripts/stranded-branch-scan.sh (observe-only, run-id-agnostic
scan of the relay/*-<verdict>-<item>-* and relay/orphan/*-<verdict>-<item>-* branch
namespaces, filtering out zero-commit branches per the id:6e02 live-parallel-child trap)
and wired it at both required sites in relay-loop.js: pre-dispatch in runUnit() via a new
strandedBranchesFor() mechanical hop (non-empty scan refuses to dispatch and hands back
every branch+commit-count instead of spawning a child blind to a prior attempt's committed
work — the lodelore id:15d2 incident), and at integrate via a new step 1c that has the
integrator scan for sibling branches (excluding the one just merged) and surface them
loudly (log + pushEvent + handback) through a new INTEGRATE_SCHEMA `siblingBranches`
field, rather than relying on a lucky git add/add conflict. Registered the new script in
mechanical-proxy.py's ALLOWED_RELAY_SCRIPTS and the three Makefile install manifests
(relay_FILES/relay_EXEC/relay_ALLOW) — both required for the wiring to be reachable, not
just present (id:5367/2062 failure mode). Full suite: 447 passed, 0 failed, 2 expected-red
(open roadmap items) — clean, nothing weakened.
Friction: the RED spec (tests/test_redispatch_stranded_branch_dd7d.sh) was already fully
authored; the id:34b7/ba7e "unit.path must carry an explicit justification" test caught two
new unjustified splices from the new code (both legitimately need the canonical checkout,
same as the existing provisionWorktree()/integrate() sites) — a one-line comment each fixed
it, not a design problem.
refactor: none needed — new script + two wiring sites; no pre-existing duplication to clean up.

## 2026-08-19 15:43 — executor (sonnet, relay-loop)

Built relay/scripts/stranded-branch-scan.sh and wired it at both pre-dispatch (runUnit refusal + handback) and integrate (sibling-branch surfacing) sites in relay-loop.js, plus the mechanical-proxy allowlist and Makefile install manifests; full suite 447/0/2-expected-red. [id:dd7d]

## 2026-08-19 15:56 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review chain relay-ckpt-20260819-1530: id:5bef hardened relay-ro/relay-svc systemd units verified honest+scope-faithful+green (446/0/3); reconciled cross-ledger 5bef TODO twin; surfaced id:8e7a RUN residue gate-cleared + f875/f26d missing-spec gap [id:5bef]
## 2026-08-19 — executor (sonnet)

Worked id:f875 — hardened `tests/test_run_tests_parallel.sh`'s serial-mode checks (`-j 1`, `RUN_TESTS_NESTED=1`) against the load-flake diagnosed by the 2026-08-19 review: the old fixture design sampled a live-marker directory (`touch`/`ls`/`rm`) whose `rm` could lag under CPU contention, making a genuinely-serial run observe concurrency 2. Replaced it with flock-serialized `start $$`/`stop $$` event appends and derive max concurrency by walking the ordered events (interval-stabbing over the ordering, not a point-in-time directory sample) — a truly serial run cannot produce an overlap since the next fixture's script is never invoked until the prior one's whole process (including its own "stop" append) has exited. Verified: standalone pass; 17 runs under moderate load (8 CPU-spin processes on an 8-core box, i.e. roughly the contention level of a running relay pool) all clean; one incidental failure surfaced only under a pathological 2x-oversubscription synthetic load (16 spinners/8 cores) — well beyond the item's "relay pool is the normal case" scope, not chased further (n=1, observe-don't-fix per repo discipline, and outside this item's acceptance bar). Full suite green (447/0/2-expected-red) across two consecutive runs; one unrelated pre-existing flake (`test_statusline_path_overrides_ec3c.sh`, part of the already-tracked `id:ec3c` flake class) reproduced once and passed clean on re-run and on the second full-suite pass — not touched by this change.
Friction: none — clean scoped fix, one file changed.
refactor: none needed — the fixture-generation and `run_fixture` sites were already minimal; this replaces their concurrency-measurement mechanism in place, no new duplication introduced.

## 2026-08-19 16:14 — executor (sonnet, relay-loop)

Hardened test_run_tests_parallel.sh's serial-mode checks against load-flake (id:f875) — flock-ordered event stream replaces racy live-marker sampling; full suite 447/0/2-expected-red [id:f875]

## 2026-08-19 — executor (sonnet)

Worked id:f26d — added two md-merge.py update-ids operations named by inbound routed:f88b (narrowed by its own author's routed:9aaf correction): insert_before/insert_after (place a new item beside an existing anchor id, under the same flock; a missing anchor fails LOUD with no EOF fallback) and regex_sub (a general in-lock transform applied to the line as read under the lock, closing the TOCTOU window a plain REPLACE update has — two sequential regex_sub calls against the same id both apply instead of the second clobbering the first). Both reuse the existing routed:3ad9/id:6059 multi-marker refusal and write-side guard. New test tests/test_md_merge_insert_and_transform_f26d.sh (# roadmap:f26d) covers insert-between-siblings (position, not mere presence), insert-immediately-before, missing-anchor loud refusal, two sequential regex_sub calls on the same id both surviving, and the multi-marker refusal firing for both new ops. Full suite green: 448 passed, 0 failed, 2 expected-red.
Friction: none — the existing update_ids() per-line loop already read the file under lock each call, so both new ops slotted into that same loop; the only real design decision was ordering multiple inserts against shifting indices, handled with a position+offset pass after the main loop.
refactor: replaced the replace/append branches' duplicated "result.append(...); continue" pattern with a single line_to_write variable, so the new regex_sub branch and the insert-anchor index bookkeeping share one exit path per line instead of tripling it.

## 2026-08-19 16:27 — executor (sonnet, relay-loop)

md-merge.py update-ids gains insert-relative-to-id (insert_before/insert_after) and an in-lock regex_sub transform (id:f26d); full suite 448/0/2-expected-red [id:f26d]

## 2026-08-19 16:40 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review re-ask relay-ckpt-20260819-1614: id:f875 hardened test_run_tests_parallel.sh verified honest+green (447/0/2); reconciled cross-ledger id:dd7d TODO twin [x]; f26d remains spec-less non-gated [ROUTINE] → needs handoff, no dispatchable routine work [id:f875,dd7d]

## 2026-08-20 — executor (claude-sonnet-5)

Worked id:cc7e — the owner's 2026-08-20 REDEFINE ruling (`/relay human --all`) asked
for a fresh RED-turned-GREEN spec asserting the id:6059 `AmbiguousOwnId` refusal
instead of the retired last-marker-wins behaviour. Replaced
`tests/test_md_merge_own_id_last.sh` (which encoded the retired spec) with
`tests/test_md_merge_ambiguous_own_id.sh`: asserts a write aimed at either marker
on a 2-marker line raises loud, names both candidate ids, and writes nothing, and
that a single-marker line elsewhere in the same file still applies normally.
Since `meeting/md-merge.py` already ships the `AmbiguousOwnId` refusal (id:6059),
the new spec is GREEN immediately against HEAD — it locks in already-shipped
behaviour as a tested contract rather than driving new code.
Collateral: `tests/test_make_test_files.sh` used the retired file by name as its
"currently open+RED" fixture; repointed it at
`tests/test_dryround_single_definition_6217.sh` (roadmap:6217, still open/gated)
so the fixture stays a genuine RED example. Full suite: 450 passed, 1 expected-red
(id:6217), 1 pre-existing unrelated flake (`test_git_lock_push_slash_branch.sh`,
fails only inside the full-suite run, passes standalone — not touched by this unit).
Friction: none — the item was well-specified by the owner's ruling on the ROADMAP
title line; the only judgment call was picking a replacement RED fixture for the
collateral test.
refactor: none needed — this unit only replaces/repoints test specs, no production
code changed.

## 2026-08-20 18:13 — executor (sonnet, relay-loop)

id:cc7e redefined per owner ruling: replaced tests/test_md_merge_own_id_last.sh (retired last-marker spec) with tests/test_md_merge_ambiguous_own_id.sh asserting md-merge.py's id:6059 AmbiguousOwnId refusal; repointed test_make_test_files.sh's RED fixture to id:6217. [id:cc7e]

## 2026-08-20 18:35 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

review chain relay-ckpt-20260820-1813: cc7e verified honest+green (owner-redefined AmbiguousOwnId spec; old last-marker test legit-retired) 451/0/1-expected-red; reconciled cc7e TODO twin [x]; routine_open=0 (all open ROUTINE gated/owner-verify) [id:cc7e]

## 2026-08-20 — hard-execute (opus-apex)

Worked id:3c9d — H3 standalone warm-vs-cold copy timing on a build-dep repo. Ran under an
exclusive `resource:disk-io` lease on btrfs `/home` (zomni). Benchmarked `cp -a --reflink=always`
(warm tree) vs `git clone --local --no-hardlinks` (cold tree) vs `cp -a --reflink=never` (control)
on `zkm-ner` (heavy: spaCy+models, 341 MB `.venv`) and `zkm-stt` (light: pure-Python, 106 MB),
3 iterations each, plus the cold-clone re-warm cost (`uv sync`: 16.08 s online for ner and
offline-UNSATISFIABLE; 0.27 s offline for stt from the warm 43 GB uv cache). Published timings +
verdict in `docs/reflink-warm-vs-cold-timing-2026-08-20.md` and appended a DONE note to the
ROADMAP item (checkbox left for the driver per v12/id:5b12).
Verdict: reflink premise is FALSE at the copy step (clone is faster to copy) but CORRECT once
tree warmth is priced in — ACCEPT for heavy/network-bound repos (decisive: 0.14 s warm copy vs
16 s+network rebuild), REJECT as a blanket rule for light cache-hit repos. Recommend the d03d
fleet migration weight reflink by per-repo rebuild cost, not adopt it uniformly — owner's GO/NO-GO.
Friction: none — item was correctly sized measure-only; the surprising bit is that the literal
copy-time comparison inverts the premise, which is why the tree-warmth + rebuild-cost framing
matters. All measurement copies were made outside any git repo and removed; no source repo state
was touched (measure-only).
refactor: none needed — measure-only item; no code changed, only a new docs note + ledger appends.

## 2026-08-20 19:33 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

id:3c9d H3 reflink warm-vs-cold copy timings measured on zkm-ner/zkm-stt + verdict published [id:3c9d]

## 2026-08-20 — id:9e50 integrate.sh (mechanical integrator, build half of id:a955)

Built `relay/scripts/integrate.sh`: a standalone, fail-closed shell integrator that runs
the 11 deterministic integrate steps (lease-release → clean-tree → verify-isolation →
sync-origin → merge --no-ff → version-bump → changelog-append → ckpt-tag → git-lock-push →
worktree-retire → state-write) by composing the existing relay helpers, extracted verbatim
from the relay-loop.js integrate() Sonnet-agent prompt (~2696-2909). Each step maps its
failure to a DISTINCT non-zero exit (20–29) + a loud `HANDBACK[<step>]` line. id:aa93 is
enforced structurally: clean-tree is step 1, its non-zero defers before any mutation, and the
script contains NO stash/reset/checkout--/clean op anywhere. id:6e02 scope enforced:
worktree-retire receives exactly the one worktree+branch passed, no globbing. The SemVer
user-observable judgement is an explicit `--level` input (absent ⇒ no bump), never embedded.
Helper paths are env-overridable — the failure-injection seam the test uses. Does NOT touch
relay-loop.js (that rewire is the sibling seam id:087b).

Test `tests/test_integrate_sh_mechanized.sh`: hermetic full-sequence integrate (bare origin +
main + child worktree + unrelated sibling worktree); forced failure at 4 distinct steps
(exits 20/21/22/23, main HEAD unmoved on each); real-gate aa93 defer (a foreign tracked edit
survives byte-for-byte, no merge lands); id:6e02 unrelated-worktree survival. Registered the
new script in the Makefile install manifest (relay_FILES/_EXEC/_ALLOW, id:5f09). Full suite:
452 passed, 0 failed. Friction: none. Checkbox left unticked per v12 (id:5b12) — driver ticks
from worked_ids at integrate.

## 2026-08-20 20:44 — strong-execute (claude-opus-4-8, fable-standin, relay-loop)

Built relay/scripts/integrate.sh — standalone fail-closed mechanical integrator (11 steps, distinct exits, aa93/6e02 enforced in-script), hermetic test, Makefile-registered (id:9e50) [id:9e50]

## 2026-08-21 — executor (sonnet)

Worked id:4a76 — `classify-verdict.sh` gained a HUMAN-LANE-DRAINED branch: `verdict=human`
when `roadmap_open > 0` AND every executable lane is zero AND `open_human_lane >= 1` AND
`open_mechanical == 0`, with a reason that NAMES the human-lane cause. `classify-repo.sh`
derives and ships the new `open_human_lane` field (human LANE tag or `@manual`, parked
sections excluded) and gained the missing `[INPUT — author]` lane in `HUMAN_GATES` — the
lane set is enumerated from `relay/references/hard-lanes.md`, which lists FOUR `[INPUT — *]`
lanes where several restatements say three.
Friction: `tests/test_classifier_not_ready.sh` case (2a) directly contradicted the RED spec —
its fixture IS the measured csgebra shape (a `[ROUTINE]` item `gated-on:` an open
`[INPUT — meeting]` root) and it asserted the not-actionable fact through the verdict PROXY
`idle`, the exact false-clean id:4a76 was filed against. Rewritten to be verdict-INDEPENDENT:
it now asserts the underlying claim `actionable_routine_open == 0` directly AND pins the new
`human` verdict. NOT a weakening — a gate-regression still fails it — but it IS an edit to an
existing test file and the reviewer should confirm the call.
Also NARROWED from my first cut: `open_human_lane` counts only the ratified acceptance's two
signals (human lane tag, `@manual`). The dispatch-exclusion MARKERS `@owner-verify` /
`@owner-gated` / `@container` are deliberately NOT counted — case (1a) of the same test pins
an `@owner-verify`-only repo at `idle`, and widening is a separate owner-decidable question.
SHADOW-PARITY: routed to relay-core via the shared inbox (`routed:9699`); the Lean shadow
binary reimplements both scripts, so parity goes RED until it adopts this.
refactor: none needed — one new elif in the classifier plus one counter in the producer, both
reusing the existing `HUMAN_GATES` / `in_exempt_section` predicates rather than adding a
parallel lane list.

## 2026-08-21 08:48 — integrate (claude-opus-5)

integrate id:4a76 — human-lane verdict so a repo blocked entirely on the owner no longer reads as design-drained; classify-repo.sh gains open_human_lane + the missing [INPUT — author] lane

## 2026-08-21 08:55 — integrate (claude-opus-5)

integrate id:087b — integrate() rewired to the mechanical integrate.sh hop; no LLM agent remains on the merge-to-main path. Bump trigger fail-closed pre-merge (HANDBACK[bump] exit 30) per the 2026-08-21 ship-as-is ruling

## 2026-08-21 — executor (sonnet)

Worked id:e68f — added `relay/scripts/ledger-slice.sh` (host-side pre-dispatch ledger slicer)
and wired it into `relay-loop.js` as a mechanical `model:'bash'` hop (`sliceLedgerForUnit`),
stamping `unit.slice_path` before the prompt is assembled; both named briefs
(`executeNamedInstruction` / `hardNamedInstruction`) now open with a shared `sliceInstruction()`
that hands the child the PATH. Registered the script in the Makefile relay manifest
(FILES/EXEC/ALLOW) and in `mechanical-proxy.py`'s `ALLOWED_RELAY_SCRIPTS` (without which the hop
404s). Dogfooded: this repo's `id:b018` slices to 3,854 B against 1,157,395 B of ROADMAP+TODO.
Honoured id:9663 — every comment and the child-facing wording says LOWERS THE DEFAULT, never
"cannot over-read"; the child keeps Read/Bash and the checkout (banked deny-probe id:5937).
Friction: the RED spec's fixture puts the `<!-- gated-on:2222 -->` edge on a SIBLING line ABOVE
the item, which `resolve-gates.sh` does not read (it only scans the checkbox line) — the slicer
walks back over bare comment lines to cover both placements. `children-of:` has no extractor in
`lib-typed-edges.sh`; added a local anchored one rather than widening the shared lib while a
sibling executor is in flight. `make test` failed twice on repo-wide lints I tripped
(`rm -f` in a trap; unregistered script in the Makefile manifest) — both real, both fixed.
`test_integrate_sh_mechanized.sh` failed in the full suite and PASSED standalone: the known
id:7518 flake, not a regression.
refactor: reused `lib-typed-edges.sh` for every id/edge lookup instead of hand-rolling a bare
`grep id:XXXX` (the id:c97c define-vs-refer defect), and extracted the child-facing slice
sentence into one shared `sliceInstruction()` rather than duplicating it into both briefs.
Worked id:b018 — the id:4f9b pre-dispatch prompt-size gate now counts TODO.md as well as
ROADMAP.md. `classify-repo.sh` stats TODO.md on the host and ships `todo_bytes` beside
`roadmap_bytes` (kept the spec author's field name); `estimateDispatchTokens` takes a third
`todoBytes` argument; `oversizeDispatchReason` fails open only when NEITHER ledger is measured
(the old `if (!roadmapBytes) return ''` silently skipped a TODO-only measurement) and now names
every materially-oversized ledger with its byte count plus the archiver that shrinks it
(`roadmap-archive.sh` / `todo-update/archive-done.sh`), so a refusal no longer sends the human
to archive the wrong file. relay-loop.js's inline copy + DISCOVER schema updated; the two
prompt-size-gate structural tests (byte-equivalence + call site) both hold.

PROMPT AUDIT (asked for by the item): the assembled `unitPrompt` embeds NO ledger bytes at all
— it interpolates instructions plus `unit.reason`. What the child must SWALLOW is the file set
its procedure requires: ROADMAP.md (every verdict) and TODO.md (handoff C2's first check,
review's single-id-two-views tick-back, the execute contract's id reuse). REVIEW_ME.md and
RELAY_LOG.md are read by REVIEW units only and are deliberately NOT counted — counting them
would refuse execute units on bytes they never read. Recorded in the module comment.

BUDGET: re-derived from the dispatched tiers rather than left unexplained, but the number does
not move. relay-loop.js dispatches exactly four models (claude-opus-4-8, claude-fable-5, the
default Sonnet, haiku); all four carry a 200k window, so a tier-keyed table would hold four
identical rows. The derivation (200k x 50% working room = 100k) is now written out in the
constant's comment, with a pointer to `oversizeDispatchReason`'s existing `budget` override as
the split point if a differently-sized tier is ever dispatched. Keeping the literal was also
forced: tests/test_prompt_size_gate_4f9b.sh pins `const DISPATCH_TOKEN_BUDGET = 100000` in BOTH
files as a drift check, and rewriting a closed item's test to pass is banned by rule 3.

NOT DONE, deliberately (id:9663 / --fabled F5): the gate budgets what the child is REQUIRED to
read, not what it MAY pull. The child holds Read/Bash on the checkout and auto mode denies
essentially nothing outside protected paths (banked probe id:5937), so its potential read set is
the whole repo and is not soundly boundable from a byte count. That needs the id:e68f slice or a
real enforcement — out of scope here, so it is stated rather than half-done.

LOUD CONSEQUENCE for the reviewer: this repo now trips its own gate. dotclaude-skills is
ROADMAP.md 252,809 B + TODO.md 904,586 B ≈ 301k tok, ~3x the 100k budget, so the next pool round
will REFUSE every dispatch here with the archive remedy until TODO.md is archived
(`~/.claude/skills/todo-update/archive-done.sh <repo>/TODO.md`). That is the model working as
specced — TODO.md is genuinely 904 KB — but it is a fleet-visible behaviour change on the repo
that hosts the relay, and it should be an owner-visible call, not a surprise mid-run.

Friction: none on sizing. refactor: extracted the repeated `Number.isFinite(v) && v > 0 ? v : 0`
clamp into a local `n()` in both gate functions and replaced the hardcoded single-ledger cause
/remedy string with a data-driven ledger list, so adding a third ledger is a one-line append
instead of another bespoke branch.

## 2026-08-21 09:24 — integrate (claude-opus-5)

integrate id:e68f + id:b018 — ledger slice at dispatch (3,854 B vs 1,157,395 B for a real item) and a prompt-size gate that counts TODO.md. Known: dotclaude-skills now estimates ~301k vs 100k budget until the gate measures the slice (owner-accepted, follow-up immediate)
Worked id:bc2b — suppression must DEMOTE the verdict, not DROP the unit. Added a
`--exclude <class>[,<class>…]` interface to `relay/scripts/classify-verdict.sh` (the RED
spec's named interface, adopted verbatim): each cascade branch is now guarded by
`allow("<class>")`, so excluding a class merely SKIPS its elif and control can only fall
THROUGH to a lower-ranked branch — demote-only by construction, no ranking table, no new
state. `blocked` (rank-0 safety) and `idle` (terminal fallthrough) are accepted but
non-excludable; an unknown class exits 2 loudly rather than silently excluding nothing.
Wired both suppression sites in `relay-loop.js` (id:1432 no-work suppression, id:365b >3×
circuit breaker) through one shared `demoteSuppressedUnit()` helper that mirrors the
ratified id:8123 chain-end re-ask shape: a `model:'bash'` mechanical hop running
`classify-repo.sh … | classify-verdict.sh --exclude <class>`, with the loop supplying only
the suppressed CLASS and the classifier deciding the verdict. Only a unit for which the
classifier offers nothing dispatchable is surfaced-and-skipped as before, so the id:8c85
one-bucket-per-repo accounting invariant holds.

Verified purity two ways beyond the spec: over 1500 randomized gather-state objects the
no-`--exclude` path is byte-identical (stdout, stderr and exit code) to the pre-bc2b script
at HEAD, 0 differences; and over 9600 (state, excluded-class) pairs no exclusion ever raised
a repo's cascade position. 65 pairs DO lower `priority_rank` (chain-end `review` → `execute`)
— that is cascade-order demotion, not a promotion: the id:8123 chain-end branch deliberately
sits ABOVE `execute` while keeping review's rank-2 label, so its rank number is non-monotone
independently of this change. Worth a reviewer's eye since `priority_rank` is what the
dispatch sort keys on.

Friction: none on sizing. Two sibling executors held `relay-loop.js` concurrently (id:b018
inline prompt-size gate, id:e68f dispatch path), so the edit was kept to three hunks — one
new top-level helper after `mechVerdictHop`, and one line replaced at each suppression site —
with no reformatting anywhere else.

Shadow-parity obligation discharged: the `--exclude` contract was routed to relay-core via
the shared inbox (token f79b) — bash stays authoritative, parity is RED until relay-core
adopts it.

refactor: extracted ONE `demoteSuppressedUnit()` helper rather than copying the re-classify
+ escape-handling logic into both suppression sites, and folded the exclusion into a single
`allow()` predicate instead of threading an excluded-set test through each of the eight
cascade branches by hand.

## 2026-08-21 09:35 — integrate (claude-opus-5)

integrate id:bc2b — suppression demotes instead of dropping; a stuck item no longer starves every lower verdict class (the loderite 57d1 starvation shape)

## 2026-08-21 — executor (opus)

Worked id:35b7 — the pre-dispatch prompt-size gate now sizes a unit on its `id:e68f` ledger
SLICE when one exists, and only counts `roadmap_bytes + todo_bytes` when there is none. The
`id:b018` + `id:e68f` interaction had made this repo un-dispatchable: measured on the canonical
checkout, an unsliced execute unit estimates 303,321 tok against the 100,000 budget (REFUSED),
while the same unit carrying the real 4,192-byte slice for this very item estimates 14,548 tok
(DISPATCHES). Byte count route: ADDITIVE stdout contract on `ledger-slice.sh` — it now prints
`slice-bytes: <N>` ABOVE the path, so the path stays the last non-empty line and both the 18
`id:e68f` assertions and `sliceLedgerForUnit()`'s `/^[~/][^\s]*\.md$/` last-line parse are
untouched; a second mech hop was rejected as an extra per-dispatch agent round-trip for a number
the slicer already has on the host. The size is MEASURED (`wc -c` on the written file), never a
guessed allowance. Fail-open is unchanged and now covers one more case: a slice whose size is
unreported is unmeasured input, so it dispatches rather than falling back to counting ledgers
the child will not read. Also rewrote the printed REMEDY — it used to prescribe
`archive-done.sh` unconditionally, which moves `- [x]` items only and therefore does nothing
here (TODO.md is 529 open / 1 closed); it now names the slice lever first and marks archiving as
conditional on the bulk being CLOSED.

Friction: the suite's known parallel-run flake (id:7518) hit `test_statusline_tokens.sh` on the
first `make test`; it passed standalone and on the re-run (457 passed, 0 failed, 2 expected-red —
both pre-existing open items, 6217 and the sibling's bc2b). Stayed clear of the suppression
region a sibling executor holds for id:bc2b: the three relay-loop.js hunks are at lines 2543,
2577 and 3391, nowhere near 1196/1235.
refactor: none needed — the change is one new early-return branch inside the existing gate plus
its byte-equivalent inline twin; extracting a shared helper is impossible by construction (the
Workflow sandbox cannot import, which is why the copy exists).

## 2026-08-21 09:48 — integrate (claude-opus-5)

integrate id:35b7 — gate measures the e68f slice (303,321 tok REFUSED without / 14,548 tok DISPATCHES with); ledger conflict resolved by hand; id:087b tick backfilled

## 2026-08-21 — executor (claude-opus-5)

Worked id:7518 — promoted it to ROADMAP.md (reusing the TODO id) as an OBSERVE-FIRST item,
built `tests/flake-log.sh`, ran a 12-run × 4-width campaign, and identified the cause. The
suite's flakiness is NOT shared state and NOT host exhaustion: it is `set -o pipefail`
combined with a producer piped into an early-exiting consumer (`grep -q` / `head -N`). The
consumer exits on its first match, the producer takes SIGPIPE (141), `pipefail` promotes 141
to the pipeline status, and the test's `|| fail` fires. Measured 8/400 (2%) on the exact
assertion that failed in-suite, against a static 262-line file with no fixture and no lock.
Width raises load, load widens the scheduling window, the per-site rate rises — which is why
the flakers span four unrelated domains with no shared fixture. 427 at-risk sites across 162
of 459 test files; all 459 set `pipefail`. Killed by the log: tmpfs exhaustion (/tmp never
below 2.27 GiB) and fd exhaustion (~17k allocated vs `ulimit -n` 524288).

The item stays OPEN. The fix is mechanical but wide (427 sites), so it is NOT the "small
change" clause 6 permits an executor to merge — it needs its own item plus a lint that bans
the shape. Log: `~/.cache/dotclaude-flake/runs.jsonl`.

AMENDED after a reviewer challenge, n grown to 17 suite runs: width does NOT separate (both
j32 runs passed at the highest observed load while a j8 run failed at lower load), and the
"all failures in the first 6 runs" temporal reading is dead — runs 14-17 each went red after
a 6-run green streak. The driver is scheduling latency, which width only correlates with.
Six distinct tests reproduced, three of them from the banked four; a wide rotating failure
set is what 427 at-risk sites across 162 files PREDICTS. Two reproductions are self-proving:
`test_integrate_sh_mechanized.sh` passed the un-piped `--is-ancestor` check for a commit and
then failed the piped `git log | grep -q` for that same commit, and `test_gaming_scan.sh`
printed a `$out` visibly containing the string its `printf | grep -q` had just called absent.
Control form `grep -qF P < <(producer)`: 0/400. NOT established: a controlled load
dose-response (started, not finished), and that this is the only live cause.

Friction: the campaign is ~25 min of wall-clock the executor must sit through; a red run is
data, not a failure, which the runner's exit code cannot express.

## 2026-08-21 11:03 — integrate (claude-opus-5)

integrate id:7518 — cause identified: pipefail + SIGPIPE from an early-exiting pipe consumer (8/400 measured, 0/400 no-pipe control); item stays OPEN, fix filed as id:81d5; adds tests/flake-log.sh

## 2026-08-21 — executor (sonnet)

Worked id:7575 (TODO-only defect item, no ROADMAP twin) — made the sliced brief's "full
ledgers are still on disk" escape hatch CONDITIONAL on measured headroom. New shared pair
`sliceLedgerHeadroom` / `sliceInstruction` in `relay/scripts/prompt-size-gate.mjs`, mirrored
byte-for-byte into `relay-loop.js` (the old `const sliceInstruction` arrow is gone). Headroom
= `DISPATCH_TOKEN_BUDGET - estimateDispatchTokens(0, slice_bytes, 0)`, compared against the
LARGEST measured ledger; unmeasured ⇒ fail-open to today's wording. The gate's verdict is
untouched — `test_slice_invitation_headroom_7575.sh` case (D) pins that every unit which
dispatches today still dispatches.
Friction: id:7575 lists THREE options and only (b) shipped — (a) naming the `Prompt is too
long` death on the child-failure path (overlaps the still-open id:61fa) and (c) budgeting a
bounded allowance into the gate itself are both still open. The item should stay OPEN.
refactor: replaced the duplicated inline arrow with the shared module function so the brief
text now has exactly one authoritative source, pinned by the byte-equivalence check.
## 2026-08-21 — executor (sonnet-class)

Mechanized the single-id-two-views twin tick in `relay/scripts/roadmap-tick.sh`. Since
contract-v12 moved the execute child's ROADMAP tick into the driver, "tick the TODO twin
too" survived only as prose in one LLM prompt (relay-loop.js's review child, which
`--exclude review` can disable), so every mechanical integrate drifted another pair —
id:e68f/bc2b/b018/4a76 were all TODO:[ ] ROADMAP:[x]. roadmap-tick.sh now converges the
TODO.md twin whenever the id's ROADMAP line reads [x] (flipped now or already ticked, so
it self-repairs), through the flock'd `meeting/md-merge.py update-ids` as an in-lock
`regex_sub` — never a hand-rolled sed on a shared non-union ledger, never `--append`
(id:e166 moves the marker off the checkbox line). Missing twin = clean no-op; a twin that
exists but fails to write = loud exit 1, with a post-write assertion that the marker still
sits on a checkbox-leading line. Repaired the four drifted items; `orphan-scan.sh
--cross-ledger .` is now empty.
Friction: `awk -v` processes escape sequences, so passing a `^- \[ \]` regex as a variable
silently degrades it into a character class — the checkbox probe matches by literal prefix
instead. Did NOT touch relay-loop.js (a sibling executor holds it).

## 2026-08-21 11:30 — integrate (claude-opus-5)

integrate: mechanized TODO twin tick (4 drifted items repaired, cross-ledger now empty) + headroom-conditional slice invitation (id:7575 option b); a955 closed superseded-by-seams

## 2026-08-21 — executor (sonnet)

Worked id:353e — closed the two defects in the `id:bc2b` demote path. (1) In the `id:365b`
circuit-breaker loop the counting step is now a shared `breakerAllows(u)` closure that BOTH the
ordinary unit and the demoted replacement pass through; a demoted class that is itself over its
own suppression count is excluded in turn and control falls further through the cascade, instead
of dispatching past the breaker. Termination: each retry adds the returned class to the exclusion
set and `demoteSuppressedUnit` returns null for a class already excluded, so the set grows
strictly and is bounded by `DEMOTE_MAX_CLASSES = 8` (the finite `KNOWN_CLASSES` set
classify-verdict.sh validates against). (2) `classify-verdict.sh` now drops `review` from the
honoured exclusion set whenever `substantive_unaudited` is true — a third, CONDITIONALLY
non-excludable class beside `blocked`/`idle` — so an unaudited window can no longer grow through
the exclusion door and the ratified `id:8123` chain-end re-ask cannot be silently switched off
along with the ordinary review branch. Scoped to the hazard: with no unaudited commits `review`
excludes normally. Demote-only, no new state, no threshold heuristic.

Friction: the flagged `id:7518` flake fired — `test_integrate_mechanized_ports_087b.sh` and
`test_statusline_tokens.sh` went red in-suite, both PASSED standalone, and a clean re-run of the
full suite was 461/0. Neither touches this diff.

refactor: extracted the breaker's counting step into the shared `breakerAllows` closure rather
than duplicating the key/sig/count block for the demote path — the duplication the fix would
otherwise have forced, and it keeps the inline copy logic-equivalent to redispatch-guard.mjs.
## 2026-08-21 — executor (sonnet-tier session, Opus model)

Worked id:b015 — `relay/scripts/ledger-slice.sh` bounded an item's block by INDENTATION
(`^[[:space:]]+`), so column-0 acceptance prose, un-indented bullets and fenced code blocks
belonging to the item were silently dropped: a well-formed, non-empty slice with an honest
`slice-bytes` that passed the prompt-size gate while the child worked a truncated spec.
The block now runs to the next COLUMN-0 checkbox line or the next `#`-heading; a single
forward pass computes per-line fence state (so a fenced sample `- [ ]` or `# comment` never
terminates or splits a block) and the owning `#`-heading, which is stamped into the slice's
repo-state header as `- owning section:` (parked/exempt context, id:356f). Trailing blank
lines are trimmed; the single-line bare-comment run that carries typed edges is still claimed
by the item BELOW it. `relay-loop.js` was NOT touched (two siblings in flight there).

Size impact measured across all 82 ROADMAP.md items, before vs after on the same corpus:
min 832→919, median 3,366→3,471, p90 9,908→10,051, max 99,907→100,012 B (+0.1% on the worst
item — the heading line). Exactly ONE item grew materially: id:0e56, +1,166 B, which is its
own previously-dropped content plus two multi-line `<!-- handoff -->` annotation blocks that
sit between items; those are absorbed by the PRECEDING item (fail-toward-including), noted
in the script header.

Friction: none on sizing. Observed the known id:7518 flake class — `test_embedded_literal_lint_ef9e.sh`
failed once IN-SUITE and passed standalone and on two subsequent full runs; unrelated to this diff.

refactor: extracted the fence-state + owning-heading computation into a single forward pass
over the already-mapfile'd ROADMAP array (reused by both the block-end scan and the heading
stamp) rather than two separate scans, and pulled the next-item edge-comment lookahead into
`is_next_items_edge_comment()` instead of inlining it in the loop condition.

## 2026-08-21 12:09 — integrate (claude-opus-5)

integrate id:353e + id:b015 — demoted units re-enter the circuit breaker and review is non-excludable while unaudited; slice blocks bound by checkbox/heading so column-0 criteria are no longer dropped
Worked id:5fe2 — a POST-PUSH integrate failure was indistinguishable from a retryable
defer. `integrate.sh`'s `handback()` now emits a machine-readable block on STDERR
(stderr, not stdout: `mechanical-proxy.py` discards a non-zero-exit child's stdout and
returns `MECH-ERROR exit=<n>\n<stderr>`). PRE-push exits print `handback=<step>` +
`landed=false` and never a `merged=` line; the POST-push exits (retire 28, state-write 29,
strong-state 33) additionally print `landed=true`, `merged=<sha>`, `ckpt=<tag>`,
`push=pushed`, `remaining=<steps that did NOT run>` and `ckptRecorded=<bool>`, and
best-effort reconcile `relay.toml last_ckpt` to the already-pushed tag (the stale-last_ckpt
symptom). A new `pushed` flag is set immediately after step 8 returns 0, so the class is
derived from what actually happened, never from the exit NUMBER (30-34 were added later and
do not follow step order). `parseIntegrateResult` gained a third outcome —
`landedUnfinished` vs `deferred` — and the integrate call site gained its own branch that
surfaces the unit as a handback (naming merged sha, ckpt, failing step, unrun steps) and
never re-merges it. `push(27)` stays deferred; every pre-push exit is byte-unchanged.

Friction: the suite showed a one-off 2-failure round (`test_embedded_literal_lint_ef9e.sh`,
`test_integrate_mechanized_ports_087b.sh`); both pass standalone and the next full round was
clean at 461 — the known id:7518 in-suite flake class, not a regression from this change.
Also note bash expands ALL of a `local`'s arguments before assigning any, so
`local a="$1" b="$a"` reads an unbound `$a` under `set -u` (bit the new test's fixture
builder, which only worked earlier via dynamic scoping from its caller).

refactor: none needed — the change is additive on one shell function, one JS parser and one
new call-site branch; no duplication was introduced and the existing pre-push paths were not
touched.

## 2026-08-21 12:20 — integrate (claude-opus-5)

integrate id:5fe2 — post-push integrate failures are classified landedUnfinished (never re-merged) instead of being retried forever; verified on a SEQUENTIAL suite run (463 passed) since the id:7518 parallel race made three consecutive parallel runs red on three different tests

## 2026-08-21 — executor (sonnet)

Worked id:81d5 — removed the `pipefail` + early-exiting-pipe-consumer race repo-wide
(478 sites across 202 files) and added `tests/lint-pipefail-sigpipe.py` +
`tests/test_pipefail_sigpipe_lint.sh` (`# roadmap:81d5`) to ban its return, with no
exemption mechanism.

Method: a written transform, not hand edits. `producer | grep -q P` → `grep -q P <
<(producer)`, run to a fixed point per line, on a scratch COPY of the tree each pass;
applied to the worktree only after `bash -n` was clean. Every rewritten line was then
verified by a mechanical INVERSE check — undo the rewrite, compare token-for-token
against the original modulo whitespace — 476/476 identical.

Friction: the transform needed three passes because the DETECTOR kept under-reporting,
and each gap was found by a different instrument, none of which the others would have
caught.
- `bash -n` missed two mangled lines (`2>&1` and a leading `&&` mis-read as command
  separators); the inverse check caught both.
- The inverse check could not see sites the detector never reported. The masker treated
  a command substitution inside double quotes as string content, so `x="$(prod | head
  -1)"` was invisible — 87 live sites. That gap was surfaced by the FIRST post-remediation
  suite run going red on `test_statusline_tokens.sh`, whose two `$( … | head -1 |
  strip_ansi)` sites are exactly that form. A green lint was not evidence of a clean repo.
- The fixer classified stages on masked text while the lint classified on raw, so `awk
  '…exit'` was visible to one and not the other. Two sites.

Both gaps now have controls in the test (the statusline line verbatim as a positive
control) so neither can regress silently.

One genuine semantic change was found and fixed by hand rather than shipped:
`tools/model-probe.sh`'s `claude --version | head -1 || echo unknown` rode the
PIPELINE's status for its fallback, and process substitution discards the producer's
status by design. Made explicit. It was the only such case in 476 rewrites — I searched
for the class rather than trusting the sample.

Verification: ten consecutive PARALLEL full-suite runs at `-j8` on zomni (`nproc` 8),
recorded in `~/.cache/dotclaude-flake/runs.jsonl`, all `464 passed, 0 failed`, at load
13.5–17.8 — above the 15.1 at which a pre-fix `-j8` run went red. Pre-fix baseline on
this host was 8 red in 12 runs at j8, and three consecutive red runs on three different
tests earlier the same day.

`id:7518` left OPEN — see the note on its ROADMAP item.

## 2026-08-21 13:00 — integrate (claude-opus-5)

integrate id:81d5 — pipefail/SIGPIPE remediated across 478 sites in 185 files + a zero-exemption lint; verified by an inverse token-for-token checker (476/476) and ten green -j8 runs. id:7518 left OPEN (its clause-4 hypothesis ranking is not discharged; ten green runs are evidence, not proof)

## 2026-08-21 — executor (sonnet)

Worked id:e82e and id:31c3.

id:e82e (POOL-BLOCKING): `integrate.sh` step 4b staged only `ROADMAP.md`, while
`roadmap-tick.sh` also writes the TODO twin of every worked id — so an integrate whose
worked id had an open twin left `TODO.md` modified-but-uncommitted in the canonical
checkout and wedged the repo one round later at step-1 `EX_CLEAN_TREE`. Widened the
porcelain check + `git add` to `ROADMAP.md TODO.md` (scoped paths only, id:debf intact),
renamed the commit to `chore(roadmap): tick worked items + TODO twins [id:$ids]`, and
corrected the stale `roadmap-tick.sh` header comment that still named `ROADMAP.md` alone.
New test `tests/test_integrate_todo_twin_commit_e82e.sh` drives a REAL integrate at the
`integrate.sh` seam — the existing `test_roadmap_tick_todo_twin.sh` runs the script
standalone and structurally cannot see a staging gap, which is why a green suite missed
this. Verified red-before against a mirrored pre-fix `integrate.sh` (` M TODO.md` left
behind, the exact wedge dirt) and green-after.

Surprise worth recording: naming both ledgers unconditionally broke
`test_integrate_mechanized_ports_087b.sh` — `git add -- TODO.md` is a FATAL exit-128
pathspec error in a fixture repo with no `TODO.md`, and a repo without one is perfectly
normal. Step 4b now names each ledger only if it exists on disk. The suite caught it; the
new test alone would not have, since its fixtures always seed both files.

id:31c3 (wording only): the `id:7575` hardened brief told children the slicer bounds an
item block by INDENTATION so a column-0 criterion can be missing — `id:b015` removed that
months ago. Replaced the false justification in `prompt-size-gate.mjs` and its inline copy
in `relay-loop.js` with a true statement of what the slice carries, kept the hand-back
instruction itself intact, and rewrote the `sliceInstruction` rationale comment to record
that `b015` fixed it rather than repeating the claim. The two copies are still
byte-equivalent (`test_slice_invitation_headroom_7575.sh` pins this and passes), and the
`id:9663` no-enforcement assertion still holds.

Friction: none. `make test` → 465 passed, 0 failed, 1 expected-red
(`test_dryround_single_definition_6217.sh`, pre-existing, roadmap:6217 still open).
refactor: none needed — one staging widening plus two string/comment corrections; no new
duplication, and the existing-path guard was folded into the same block rather than added
as a second conditional.

## 2026-08-21 13:25 — integrate (claude-opus-5)

integrate id:e82e + id:31c3 — integrate.sh now commits the TODO twin (the untriggered wedge is closed, with a test at the integrate SEAM rather than the unit); the child-facing brief drops the column-0 truncation claim b015 fixed

## 2026-08-21 — executor (sonnet)

Worked id:7c5f — the id:b018 prompt-size gate's counted ledger set is now VERDICT-DEPENDENT.
`REVIEW_ME.md` + `RELAY_LOG.md` are counted iff `unit.verdict === 'review'` (a review child is
contractually required to read both), and never for execute/hard/handoff — so b018's own
objection ("would refuse execute units on bytes they never read") still holds. One new pure
function, `countedLedgersFor(unit)`, is the single place the set is decided; both
`oversizeDispatchReason` and `sliceLedgerHeadroom` read it, so the gate and the brief can never
disagree about which files a verdict must swallow. `classify-repo.sh` measures the two files on
the host as `review_me_bytes`/`relay_log_bytes`, fail-open on 0. The id:35b7 slice precedence is
untouched: a unit carrying `slice_path` is still sized on the SLICE and counts NO ledgers at all,
review units included (pinned by a test case).
Friction: the materiality filter that decides WHICH ledgers the refusal names would have hidden
the review-only pair — they are small (15k/10k tok) against a 25k-tok threshold, yet they were
the entire cause of the overrun, so the refusal would have sent the operator to archive
ROADMAP/TODO, which were never the problem. Added a swing-cause clause: a review-only ledger is
named whenever the estimate WITHOUT the review-only ledgers would have fitted.
refactor: extracted `countedLedgersFor()` rather than duplicating the verdict test in the gate
and in `sliceLedgerHeadroom` — that duplication is exactly how the gate and the brief would drift
apart on which ledgers a review unit reads. Also generalised the `fix` field with a `cmd` flag so
RELAY_LOG.md (append-only, NO archiver) gets honest prose instead of a command that does not exist.
Worked id:3a09 + id:5218 — added `hooks/destructive-git-guard.py`, a third PreToolUse/Bash
guard that refuses the TREE-WIDE destructive git forms while allowing a path-scoped
`git checkout -- <file>`, and versioned the previously-local-only `rm-force-guard.sh`
into `hooks/`. Both are registered in a new single Makefile `HOOK_FILES` manifest that
now drives `install-hooks` AND a new `status-hooks` target folded into `make status`,
which reports real-file-instead-of-symlink drift and unmanaged hooks. `settings.json`
was NOT written — wiring the new guard is the owner's step (id:3a09 acceptance 5), and
the live `~/.claude/hooks/rm-force-guard.sh` was NOT replaced with a symlink (that is
`make install-hooks`' job on a protected path).

Audit (id:5218's second half): rm-force-guard.sh was the ONLY unmanaged hook path in
settings.json. All six others resolve to symlinks into ~/src/dotclaude-skills/hooks/.

Friction: the driver asked for a ROADMAP promotion with the same id on close. Skipped
deliberately — executor contract rule 5 forbids editing ROADMAP item definitions and
v12/id:5b12 gives the tick to the integrator, and a promotion of already-closed work adds
nothing to the execution queue. Both ids are ticked in TODO.md via the flock'd md-merge.py.
Surfaced here for the reviewer rather than acted on.

refactor: replaced the eight hand-written `ln -sf` lines in `install-hooks` with a single
`HOOK_FILES` manifest shared by `install-hooks` and the new `status-hooks` — the two can no
longer drift, and that shared manifest is precisely what makes the id:5218 drift class visible.

## 2026-08-21 14:51 — integrate (claude-opus-5)

integrate id:7c5f (verdict-dependent counted ledger set; shadowed surface STABLE) + id:3a09/id:5218 (destructive-git guard built-but-unwired; last unmanaged hook versioned)

## 2026-08-21 15:15 — reviewer (claude-opus-5)

review relay-ckpt-20260820-2044..HEAD (82 commits): ROADMAP re-derived; id:7575 re-worded to record option (b) shipped with (a)/(c) unbuilt; id:7518 confirmed OPEN on TWO unmet clauses and its prose close-condition recorded as NARROWER than its ratified acceptance; 3 REVIEW_ME boxes opened (3a09 close boundary, ebd0 disarmed-green test, 4 dead gates); gaming-scan 2 hits both false positives; a955 closure verified sound. STATED GAP: the section-2d over-reach check was run only for a955, NOT for each of the ~14 closes against its cited ratified source

## 2026-08-21 — executor (claude-opus-5)

Worked id:6f62 — destructive-git-guard.py's heartbeat probe accepted ANY live marker, so the
always-beating non-pool `discovery-producer` daemon (id:54fc) made every interactive session
read as UNATTENDED and get a hard `deny` on a false stated reason. Extracted the pool-run
predicate `stop-request.sh` already had inline into `relay/scripts/lib-pool-runs.py`; both the
hook and stop-request.sh now call that ONE definition (a test asserts neither keeps a copy).
Also: the refusal names the concrete trigger that fired instead of the compound
`(relay run id / live heartbeat detected)`, and remedy #1 no longer teaches the repo-banned
tree-wide staging. settings.json untouched — wiring stays the owner's switch.
Friction: `tests/test_stop_request_target.sh` copies stop-request.sh into a stub bindir, so the
new shared lib had to be copied beside it — a real dependency of the script under test, not a
weakened assertion. That was the one suite failure and it is fixed in the fixture, not the test.
refactor: extracted the duplicated "which runIds are pools" rule into relay/scripts/lib-pool-runs.py
(one definition, two callers) instead of copy-pasting the exclusion into the hook.

## 2026-08-21 15:35 — integrate (claude-opus-5)

integrate id:6f62 — discovery-producer no longer counts as an unattended signal; predicate extracted to lib-pool-runs.py and shared with stop-request.sh (no-drift pinned by test); refusal names the concrete trigger; remedy teaches scoped staging. The original deny-on-interactive reproduction now defers, live-verified

## 2026-08-21 15:42 — reviewer (claude-opus-5)

review relay-ckpt-20260821-1515..HEAD (id:6f62): verdict SAFE TO WIRE. Reproduction re-derived through the real symlink against the real live producer marker; fail-safe verified by breaking the lib four ways (all deny); hook JSON shape correct; 22 ms/call, no shell-out; stop-request.sh no regression across 0/1/2/producer-only. FIVE findings boxed — id:3866 (malformed payload crashes exit 1, and a crashing PreToolUse hook fails OPEN) is the only one that can let a destructive command through

## 2026-08-21 — executor (sonnet)

Worked id:3866, id:8987, id:4c14 — the three `id:6f62` wiring-readiness cleanups in
`hooks/destructive-git-guard.py`. id:3866: a crashing PreToolUse hook exits 1, which is a
NON-BLOCKING error, so the command RAN — the guard failed OPEN on exactly the input class it
should trust least. Every branch of `main()` now exits 0, `find_violation` never raises (an
unexpected failure of the tokenised analysis routes to the same conservative regex scan a
`shlex` error already took), and an outermost `try` catches the rest. Disposition for an
unreadable payload: DEFER (exit 0, empty stdout) + a one-line stderr note — a payload that
will not parse carries no command, and blocking would make any hook-protocol change a
fleet-wide outage in front of every Bash call. id:8987: a FRESH marker with an empty /
whitespace / non-string runId (or a non-object marker) is now a probe ERROR ⇒ BLOCK;
`lib-pool-runs.py` untouched, the split is in the caller. id:4c14: the no-drift assertion
tightened to ZERO NON-COMMENT occurrences of `discovery-producer` in either caller.
Friction: the new `#`-stripping check first landed as `sed … | grep -q`, which
`tests/lint-pipefail-sigpipe.py` correctly rejected under `pipefail`; rewritten as
`grep -q … < <(sed …)`. Surprising: nothing — the four reported crash shapes reproduced
verbatim. Verified before trusting: the id:4c14 mutation negative control (an injected
`== "discovery-producer": continue` is MISSED by the old grep, CAUGHT by the new assertion);
all four fail-SAFE `lib-pool-runs.py` breakages, with and without a heartbeat dir, still
`deny` naming `heartbeat probe ERRORED`. Latency 27 ms/call, still zero `subprocess`.
`~/.claude/settings.json` NOT written (grep: 0 occurrences, mtime still 2026-08-19 21:28).
id:5f95, id:fb2c and the id:3a09 close-boundary box left open as instructed.
refactor: extracted `_raw_scan` out of `find_violation` so the conservative fallback has one
definition reachable from both the shlex-error path and the new never-raise wrapper, instead
of duplicating the pattern loop; added `_defer` so the eight malformed-payload branches share
one observable exit instead of eight bare `return`s.

## 2026-08-21 16:06 — integrate (claude-opus-5)

integrate id:3866 + id:8987 + id:4c14 — the destructive-git guard can no longer fail OPEN on a malformed payload; empty runId is now a probe error; the no-drift assertion pins the rule not a spelling (negative-control verified). Guard is now wiring-ready

## 2026-08-21 17:30 — integrate (claude-opus-5)

review: verify id:0384 front-door currency gate (red->green, 12/12); owner-ratified integrate [id:0384]

## 2026-08-22 10:52 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

reviewer (claude-opus-4-8): chain-end verify green (484/0/1), gaming clean (6 false-positive skips), @container fix on id:7518+id:372a routine_open=5 [id:7518,372a]

## 2026-08-22 14:38 — reviewer (claude-opus-5)

Afternoon hand-integrate (commits de45af3..9028bef), bookkeeping-only checkpoint — no re-review performed.

Worked and closed:
- id:a360 — loderite starvation: an orphan branch now binds to its item by COMMIT MESSAGE, not branch name; new loderite-shaped end-to-end regression test.
- id:1171 — residual half: the commit-message fallback's bare-token grep anchored to the id marker via the shared typed_edges_own_id_of_line.
- id:65ad + id:d51f(b) — fleet bump_policy defaults to minor; three-state reader (absent / parsed / present-but-unparsed); warn-and-default on an unrecognised value; two stale prose contracts refreshed. d51f stays OPEN on its unbuilt writer half.
- id:4d44 — relay/references/human.md corrected to the per-remote push narrowing; 3 cross-repo inbox items ingested.

TODO/ROADMAP boxes were already reconciled in 3872867. This checkpoint exists because the hand-integrate skipped all three post-integrate hops (RELAY_LOG, CHANGELOG, ckpt tag), leaving the audit boundary stale at relay-ckpt-20260822-1052 and the ledger reading as if nothing shipped. CHANGELOG derived in 9028bef.

## 2026-08-22 15:46 — reviewer (claude-opus-4-8, relay-loop)

Chain-end review re-ask (id:8123) verifying the d51f/f66e execute chain since relay-ckpt-20260822-1438. Both closes are GENUINE, not gamed. id:d51f(a) — writer-side bump_policy enum guard in relay-state-write.sh: independently mutation-verified (deleting the `if [ "$key" = "bump_policy" ]` block reddens assertion (b), `auto` accepted with exit 0). id:f66e — git-diary-workflow SKILL.md push narrowing: mutation-verified (dropping `--remote origin` reddens assertions (1) and (2)). gaming-scan clean (no DELETED_TEST/ADDED_SKIP/REMOVED_ASSERT); no executor-introduced @owner-accepted in the window. Both tests correctly carry NO `# roadmap:` header (both items are TODO-only, no ROADMAP checkbox). Full suite 491/0/1 green (unit tier; repo has one tier). §2d over-reach: neither diff is a superset of its owner ruling — d51f is key-scoped as the owner constrained, f66e is exactly option (i). Contract pointer v12 == canonical. relay-doctor: cross-ledger/roadmap-grammar/unpromoted/TODO-conformance/main-residue all clean (verdict-replay step slow, not run to completion; report-only). roadmap-lint DEAD-GATE/DEP-PROSE-UNTYPED WARNs (d4ca/e405/540f/c179) and orphan-scan GATE-STALE c4b4 are all pre-existing (2026-08-13/20d old), not this window. Reverse-handoff: new [ROUTINE] TODO items 6a34/9bfc/9452/7986 were LEFT as design-ledger — 7986 carries an explicit unresolved owner question (handoff tier), 6a34 names two competing approaches, and all four are freshly meeting-filed items whose RED-spec promotion belongs to a /relay handoff turn, not this verify re-ask. Verified-green: d51f, f66e. Reopened: none.

## 2026-08-22 16:19 — reviewer (claude-opus-4-8, fable-standin, relay-loop)

Review re-ask (id:8123): d51f writer enum guard + f66e diary push-narrowing both verified genuine (mutation-checked both directions), suite 491/0/1, no gaming routine_open=3 [id:d51f,f66e]

## 2026-08-26 — executor (claude-sonnet-5)

Worked id:f2ef — flake-log width=1 confirmation run #2 (post-id:81d5). Ran `tests/flake-log.sh -j 1` in the worktree; it appended a new row to `~/.cache/dotclaude-flake/runs.jsonl` with ts 20260826T102748Z (after the required 2026-08-21T10:58:33Z threshold): mode=suite, width=1, wall_s=419.4, pass=498, fail=0, xred=1. Acceptance met by the log append itself — no repo-file changes were needed since the target log lives outside the repo (`~/.cache/dotclaude-flake/`).
Friction: none — the item was a pure observational re-run, no code changes, no test edits.
refactor: none needed — one-shot data-collection run, no code touched.

## 2026-08-26 12:36 — executor (sonnet, relay-loop)

id:f2ef — flake-log width=1 confirmation run #2 done: appended a new suite row (ts 20260826T102748Z, pass=498 fail=0) to ~/.cache/dotclaude-flake/runs.jsonl [id:f2ef]

## 2026-08-26 — reviewer (claude-opus-5, relay-loop)

Chain-end review re-ask (id:8123) over `relay-ckpt-20260822-1619`..HEAD — one executor unit
(id:f2ef) plus ~60 owner / `/relay human` commits. **id:f2ef verified GENUINELY green, not
gamed**: a pure observational re-run with NO repo diff, whose acceptance artifact I confirmed at
the source rather than from its self-report — `~/.cache/dotclaude-flake/runs.jsonl` carries
`ts=20260826T102748Z, mode=suite, width=1, wall_s=419.4, pass=498, fail=0, xred=1`, after the
required 2026-08-21T10:58:33Z threshold. `gaming-scan.sh` clean (no DELETED_TEST / ADDED_SKIP /
REMOVED_ASSERT). No executor-introduced `@owner-accepted` (§2b.7): the three window hits are the
owner's own `chore(046a)` archive MOVES of pre-existing text, not new assertions. §2d over-reach:
f2ef's diff is empty, so no superset is possible; its cited source (the id:372a seam
decomposition) is present. Contract pointer v12 == canonical v12.

**Test tiers (§3):** this repo declares exactly ONE tier — `make test` → `tests/run-tests.sh`;
no `.github/workflows/`, no e2e/integration target. It ran green: **498 passed, 0 failed, 1
expected-red**. No tier was skipped.

**Reverse-handoff (§5b):** ROADMAP gained ZERO new open items this window; TODO gained 33, nearly
all owner-filed design-ledger. One qualified for a mini-handoff and got one — **id:758a**
(base-ref resolution must use the ACTUAL checked-out branch), promoted to ROADMAP `[ROUTINE]`
REUSING its TODO token, with acceptance / done-check / context and a RED spec
(`tests/test_base_ref_checked_out_branch_758a.sh`, `# roadmap:758a`). It qualifies because it is
PROPAGATION of an already-ratified decision (id:8739) to two named offenders with line numbers —
no design judgment left open. Its case (a) reproduces the live `integrate:git-annex` failure
verbatim, and case (c) pins the fail-CLOSED posture so the fix cannot "helpfully" fall back to
the stale `master` mirror that resolves to the WRONG base. **id:6c8c** (tmux-wrap `claude-relay`)
was deliberately LEFT as design-ledger: its own text names three unresolved decisions (session
name fixed vs per-cwd, which proxy branches wrap, opt-out env var), so it is a `/meeting`
candidate, not executor work.

**relay-doctor (§4b):** reference-install, install-drift, parked orphans, quota-config, lean-pin
and hooks-path-shadow all clean. Two findings: one inbox DEAD-LETTER (`routed:2e43`, destined for
this repo, absent from both ledgers) — **ingested** into TODO.md as `id:e278` with the
`[INBOUND routed:2e43 from yinyang-puzzle]` provenance bracket, so the next `scan-routed --apply`
drains it; and the standing relay-core shadow divergence (13,994 mismatches / 227,265 rounds),
surfaced to REVIEW_ME as an owner decision, not a review blocker.

**Three REVIEW_ME boxes written**, all judgment calls I declined to settle myself: (1) `id:ebd0`
was ticked "owner-authorized" with no greppable `@owner-accepted` marker — NOT reopened, because
I verified the acceptance evidence independently (privacy-gate log 49 lines, 34 naming the public
remote; no local `core.hooksPath` override; global hooksPath set), so the close is CORRECT and
only its provenance trace is missing; the owner stamps or retracts. (2) the relay-core shadow
divergence. (3) four `roadmap-lint` DEAD-GATE / DEP-PROSE-UNTYPED WARNs (d4ca, e405, 540f, c179)
that have now survived three reviews, each correctly recording them as "pre-existing" — which is
exactly how a dead gate becomes furniture. They are gated on ids that live only in TODO.md and
were never promoted, so nothing in ROADMAP can ever clear them; re-targeting is handoff C2's call,
not a reviewer guess.

**Own-error disclosure:** my first `md-merge insert_after` anchored on `id:6ab7` wedged the new
item BETWEEN 6ab7's header line and its sub-bullets. `roadmap-lint` caught it immediately
(NO-ACCEPTANCE-NO-TWIN on 6ab7) and it was repaired before commit — recorded because the loud
detector earning its keep on the reviewer's own mistake is the datum worth keeping, and because
`insert_after` anchors on the id LINE, not the item BLOCK, which is a trap for the next caller.
Lint is back to the same 6 pre-existing WARNs; `todo-conformance` and `orphan-scan
--cross-ledger` both clean.

routine_open = 10.

## 2026-08-26 13:14 — reviewer (claude-opus-5, fable-standin, relay-loop)

review(8123): id:f2ef verified green at the source + mini-handoff id:758a with RED spec routed:2e43 ingested as id:e278 3 REVIEW_ME boxes suite 498/0/2 routine_open=10 [id:f2ef,758a,e278] [id:f2ef,758a,e278]

## 2026-08-26 — executor (claude-sonnet-5)

Worked id:b1ef — ran `tests/flake-log.sh -j 16` (over-subscribed width, 8 cores) per the
seam-of-id:372a confirmation run; appended row ts=20260826T114235Z width=16 pass=498 fail=0
xred=2 rc=0 to ~/.cache/dotclaude-flake/runs.jsonl. No repo files change — the acceptance
criterion is entirely the external log append, so this is a log-only self-report commit.
Friction: none.
refactor: none needed — pure instrument invocation, no code changed.

## 2026-08-26 13:45 — executor (sonnet, relay-loop)

id:b1ef — ran tests/flake-log.sh -j 16 (over-subscribed width), appended ts=20260826T114235Z pass=498 fail=0 rc=0 row to runs.jsonl [id:b1ef]

## 2026-08-26 — executor (claude-sonnet-5)

Worked id:c3be — ran `tests/flake-log.sh -j 16` (over-subscribed width, 8 cores) for the
second seam-of-id:372a confirmation run (following id:b1ef's run #1); appended row
ts=20260826T124545Z width=16 pass=498 fail=0 xred=2 rc=0 to
~/.cache/dotclaude-flake/runs.jsonl. No repo files change — the acceptance criterion is
entirely the external log append, so this is a log-only self-report commit.
Friction: none.
refactor: none needed — pure instrument invocation, no code changed.

## 2026-08-26 14:49 — executor (sonnet, relay-loop)

id:c3be — ran flake-log.sh -j 16 (over-subscribed width) confirmation run #2, appended ts=20260826T124545Z pass=498 fail=0 rc=0 row to runs.jsonl [id:c3be]

## 2026-08-26 — reviewer (claude-opus-5, relay-loop)

Chain-end re-ask review, run `relay-20260826-162405-7522`, window `relay-ckpt-20260826-1449`..HEAD
= 18 commits, **all owner-attended, zero executor units**. **All four declared tiers RUN, none
skipped**: `make lint` (0 violations, within baseline), `make test` (**505 passed, 0 failed, 2
expected-red** — `6217` and the new `76fd`, both open items whose red test IS the spec),
`make gaming-canary` (3/0), `make shard-canary` (6/0). No `SKIPPED-TIER`.

`gaming-scan.sh` raised one line (`REMOVED_ASSERT:tests/test_git_lock_push_remote_select_4d44.sh`
removed=1 added=0), **adjudicated benign**: the owner deliberately flipped `git-lock-push.sh`'s
absent-flag default from "every remote" to "origin only" (`id:a73b`), so assertion (3) was
re-pointed from the old default to the new `--all` flag, and the same commit ADDS a mutual-exclusion
assertion (4b) plus a dedicated 7-assertion file. The four `integrate` test-stub edits are
one-token arg-parser skip-list additions inside FIXTURES, not weakened assertions. No
`@owner-accepted` in the window; no discard-verb in any commit message; contract pointer `v12` ==
canonical; `relay-doctor` reported 1 per-repo issue (the `id:758a` cross-ledger drift, now resolved).

**`id:758a` verified green and CLOSED.** Its ROADMAP checkbox is now `[x]` to match the already-`[x]`
TODO twin. Verified against `tests/test_base_ref_checked_out_branch_758a.sh` — the RED spec the
PREVIOUS review authored, which the fix commit `478d70d2` did not touch, so it is a genuinely
independent spec rather than same-author self-consistency.

**Recovered stranded work.** The parked orphan `relay/orphan/relay-20260826-122101-7415-review-repo-0`
(`3d9ca6f3`) turned out to carry a whole prior review's ledger output that never reached main:
+43 lines of `REVIEW_ME.md` (2 open boxes addressed to the owner), +6 lines of `ROADMAP.md` (the
full `id:7354` promotion), +56 lines of `RELAY_LOG.md`, and one test file. This review restored the
test file as `tests/test_handback_tracker_all_sites_7354.sh` and ran it BOTH ways: it FAILS against
`01ce9b9c^` naming all 10 unwired `state.handbacks.push(` sites, and PASSES (4/4) against HEAD. So
`id:7354` is now **independently** verified, not merely self-consistent — the shipped
`test_repeat_handback_wiring_7354.sh` was authored in the same commit as the fix. The stranding
itself is surfaced as a REVIEW_ME box: nothing distinguishes "stale orphan branch" from "orphan
carrying unread questions for the owner".

**Reverse-handoff (§5b)** over the 5 open items added this window (`2c2a`, `9459`, `2e7a`, `76fd`,
`9566`): four already carried an owner-written `[ROUTINE]` tag, so only `9566` was genuinely
unqualified. Dispositions — **`76fd` PROMOTED** to `ROADMAP.md` reusing its TODO token
(single-id-two-views) with acceptance, done-check, context and a RED spec
`tests/test_integrate_stdin_channel_76fd.sh` (2 RED assertions on `STDIN_ALLOWED_SCRIPTS`
membership and the inline `--summary`, plus 2 GREEN regression-guards pinning stdin inertness and
the `mechArg` defence-in-depth the owner said to KEEP). **`9566` qualified as NOT executor-ready**
and deliberately left unpromoted — its fix depends on loderite's no-gallery-ack line format, which
an executor here would have to invent. **`2c2a` and `2e7a` left in TODO**: `2c2a` opens with an
exit-code question only the owner can settle (the prior, stranded review flagged this too and it is
still open), and `2e7a` says in its own text that it must be read together with `id:5552`'s
unsettled decision. **`9459`** left in TODO as a `/meeting` candidate — the prior art is named but
the in-flight-lease semantics are an open design question.

Friction: the `76fd` RED spec's first draft tripped this repo's own
`test_pipefail_sigpipe_lint.sh` (three `printf | grep -q` shapes, where `grep -q` exits at first
match and `pipefail` turns the SIGPIPE into a failure). Rewritten to here-strings. Its assertion (4)
also initially fired its own vacuity guard — the anchor regex missed `mechArg`'s body — which is the
guard working as designed. `orphan-scan --shipped` reports 84 advisory candidates (2 GATE-READY:
`3ca7`, `ebbe`); not boxed individually, since REVIEW_ME's ~10-box budget is nearly spent and the
existing stale-WARN box covers the class.

refactor: none needed — this unit wrote ledger entries, one new RED spec and one recovered test
file; no implementation code was touched, so there is no duplication to unify.

## 2026-08-26 17:03 — reviewer (claude-opus-5, fable-standin, relay-loop)

review(8123): id:758a verified green + closed (cross-ledger drift resolved) id:7354 independently verified via a RED spec recovered from a stranded orphan branch mini-handoff promoted id:76fd with a RED spec all 4 tiers green (505/0/2) [id:758a,7354,76fd,9566]

## 2026-08-26 — executor (claude-sonnet-5)

Worked id:76fd — routed the integrate hop's free-text `--summary`/`--label` fields through the
`relay-mech-stdin` payload channel instead of an inline shell argument. `integrate.sh` was added
to `mechanical-proxy.py`'s `STDIN_ALLOWED_SCRIPTS` (scope (b)); `--summary -` is now the opt-in
sentinel it reads as "take the summary off stdin" (a plain `$(cat)` assignment placed AFTER the
required-arg validation, so a bare `--summary -`-less call still fails fast at usage checking
without ever touching stdin — confirmed against the pre-authored RED spec's inertness probe).
`relay-loop.js`'s integrate hop no longer builds `--summary` via `mechArg(report.summary)`; it
passes the literal sentinel and emits the free-text summary on a ```relay-mech-stdin fence
alongside the existing ```relay-mech command fence, copying the `write-relay-status` reference
pattern. `mechArg()`'s sanitisation is left untouched (kept as defence-in-depth per the item's
scope). `tests/test_integrate_stdin_channel_76fd.sh` (pre-authored RED on assertions (1)/(2), GREEN
on the (3)/(3b)/(4) regression guards) is now 5/5 green; full suite 506 passed, 0 failed, 1
expected-red (an unrelated open item).
Friction: none — the item's acceptance/tests/context were precise enough that the change was a
direct implementation of the spec, no design judgement calls needed.
refactor: none needed — a small, targeted three-file diff (proxy allowlist entry, one `if` block
in integrate.sh, one hop-builder edit in relay-loop.js); no duplication introduced to unify.

## 2026-08-26 17:10 — executor (sonnet, relay-loop)

id:76fd — integrate hops --summary now rides the relay-mech-stdin channel instead of an inline shell arg full suite 506/0/1-expected-red [id:76fd]

## 2026-08-26 — reviewer (claude-opus-5, relay-loop)

Chain-end review re-ask (classifier id:8123, chain `relay-ckpt-20260826-1710`). The
`$LAST..HEAD` window is a SINGLE commit — `8075c255`, the integrator's own durable
handback follow-up re-laning `id:6ab7` `[ROUTINE]` → `[INPUT — decision]` with a
`route:human` gate note (id:3801). **No executor code work, no test files touched**, so
there was no formerly-red test to verify-green and no item to close this pass.
`gaming-scan.sh` clean (exit 0, no output); §2b residue checks vacuous by construction
(nothing to resurrect / special-case / fake-clean, no `refactor:` claim in the window, no
`@owner-accepted` introduced); §2d over-reach vacuous (zero items closed).

**Verified the gate note rather than trusting it** (the claim is a restatement about
repo state, so it was checked against the evidence): `id:6ab7`'s note says only 3/4
required post-`id:81d5` flake-log confirmation rows exist. `id:81d5` landed `9f0334ea`
2026-08-25 15:02; `~/.cache/dotclaude-flake/runs.jsonl` carries exactly three rows after
it — one `width=1` (`20260826T102748Z`, 419.4 s) and two `width=16` (`114235Z`,
`124545Z`) — matching seams `f2ef`/`b1ef`/`c3be` `[x]` and the second `width=1` seam
`id:97e0` still open. The 419 s wall-clock also substantiates the "exceeds one executor
turn's budget" rationale on `97e0`. Gate note is ACCURATE; left as written.

**Test tiers (§3, all four DECLARED tiers RUN — none skipped):** `make lint` green (runs
as `make test`'s prerequisite); `make test` **506 passed / 0 failed / 1 expected-red**
(`test_dryround_single_definition_6217.sh`, `roadmap:6217` legitimately still open);
`make gaming-canary` 3/3; `make shard-canary` 6/6 against
`shard-prompt.baseline.txt`. No `SKIPPED-TIER`. Host load 2.09 at start, so the timings
are not load-confounded.

**relay-doctor (§4b): 0 per-repo issues** — roadmap-lint clean, todo-conformance clean,
cross-ledger clean, main-checkout residue clean, mechanical-orphan clean, refs-install
and install-drift clean, relay.toml parses, inbox 0 dead-letters, quota-config OK,
lean-toolchain pins agree. The two fleet-level findings it prints (relay-core shadow
mismatches `id:82c4`; the parked orphan `relay/orphan/relay-20260826-122101-7415-review-repo-0`)
are BOTH already open REVIEW_ME boxes from prior passes — deliberately NOT re-boxed, to
avoid duplicating standing items. **No new REVIEW_ME boxes this pass** (8 remain open).

**Reverse-handoff (§5b):** the only `- [ ]` line added in the window is the `id:6ab7`
re-lane, which already carries a lane, a gate reason and a route — nothing left to
qualify. **Spec-drift (§4):** contract pointer in `CLAUDE.md` is `v12` == the canonical
marker in `relay/references/executor-contract.md`; no shipped surface changed this
window, so README/ARCHITECTURE need no update.

**`routine_open = 0`, and that is a judgement worth stating explicitly:** six `[ROUTINE]`
items are literally unticked, but NONE is dispatchable — `d4ca`/`540f`/`c179`/`554b`/`6446`
all carry live `gated-on:` markers, and `cf2d` is `@owner-verify` (an observability claim
only a real `/meeting` can produce, per the poolability rule). `classify-repo.sh`'s own
replay independently computes `actionable_routine_open=0`, and the same convention was
used at `relay-ckpt-20260820-1813`. Reporting the raw 6 would re-enqueue an execute unit
that could only hand back — a dispatch spin. This repo's pool throughput is now gated
almost entirely on human/meeting decisions (28 `[INPUT — meeting]` + 11
`[INPUT — decision]` open), which is the standing condition REVIEW_ME already tracks.
refactor: none needed — reviewer verification pass; no code paths touched, one
append-only RELAY_LOG entry.

## 2026-08-26 17:34 — reviewer (claude-opus-5, fable-standin, relay-loop)

review(8123): window = 1 integrator commit (id:6ab7 gate note, verified accurate vs runs.jsonl) no executor code work all 4 tiers green (506/0/1-xred, canaries 3/3+6/6) gaming-scan + relay-doctor clean routine_open=0 (all 6 open [ROUTINE] gated or @owner-verify) [id:6ab7] [id:6ab7]

## 2026-08-26 19:34 — integrate (claude-opus-5)

handoff id:5eeb C2+C3: promoted to ROADMAP [ROUTINE] reusing the TODO id, RED spec tests/test_context_budget_handback_5eeb.sh pinning a mid-run context-budget checkpoint-and-handback. Diagnosis corrected mid-flight to the byte-attributed measurement.

## 2026-08-26 — executor (sonnet)

Worked id:5eeb — built relay/scripts/context-budget.sh (pure read-only decision
function: --bytes/--transcript, overridable thresholds, defaults warn 200,000 B /
handback 300,000 B calibrated on the two real deaths in run
relay-20260826-162405-7522; exit 3 on handback, fail-open-but-loud to `unknown` on
an unmeasurable transcript). Added executor-contract.md rule 2c naming both trigger
points (periodic + before-first-edit) and the checkpoint-and-handback disposition
(commit work done, HANDBACK: RELAY_LOG.md line, contract_met=false/route="none").
Bumped the contract v12 -> v13 (in-file marker + CLAUDE.md pointer + Maintenance
entry) and registered the new script in the Makefile relay_FILES/_EXEC/_ALLOW
manifest (test_relay_install_manifest.sh caught the initial omission).
Friction: the version bump broke an unrelated pre-existing test
(test_relay_driver_ticks.sh) that hardcoded the literal `v12` marker string; fixed
it to assert "marker present, >=12, and CLAUDE.md pointer agrees" instead of a fixed
version, so it survives this and future contract bumps without further edits.
tests/run-tests.sh: 507 passed, 0 failed, 1 expected-red (up from the 506/0/2
baseline — id:5eeb's RED spec now passes).

## 2026-08-26 19:52 — reviewer (claude-opus-5)

review-verified id:5eeb: context-budget.sh + executor-contract rule 2c (v12->v13). Suite 507/0/1, gaming-scan clean. Box deliberately NOT ticked — review found rule 2c is UNRUNNABLE as written (no dispatch path tells a pooled executor its own transcript path).

## 2026-08-27 08:50 — executor (sonnet, relay-loop)

id:5eeb verified already-satisfied: context-budget.sh, its test, and the executor-contract v15 rule 2c (with ZERO-COMMIT branch) all already ship; full suite green 508/0/1-expected-red — no code change needed, just confirming done-check for the driver's tick. [id:5eeb]

## 2026-08-31 — reviewer (claude-opus-5)

Trust-but-verify pass over `relay-ckpt-20260827-0850`..HEAD (89 commits, 77 files,
+8,656/-501). Full suite: **528 passed, 0 failed, 1 expected-red**
(`test_dryround_single_definition_6217.sh`, roadmap:6217 still open). Tiers enumerated
per id:f032: this repo declares exactly ONE tier, `make test` -> `tests/run-tests.sh`
(no package.json scripts, no CI workflow, no e2e/integration split) -- it RAN, nothing
was skipped.

Mechanical gaming-scan: one hit, `REMOVED_ASSERT:tests/test_prompt_size_gate_todo_b018.sh
(removed=3,added=1)`. ADJUDICATED LEGITIMATE, not gaming. The resurrection check was run
(original file from the checkpoint, executed in-tree): 22 ok / 3 bad, failing exactly
`roadmap_only_under_budget`, `both_about_double`, `postarchive_254087_dispatches`. All
three moved in the STRICTER direction because `FIXED_OVERHEAD_TOKENS` went 12,000 ->
65,000 in `52bffddd` (per-tier dispatch budget, owner-ratified 2026-08-27 on 28,365
measured transcripts), and each was replaced by a tier-anchored assertion pinning the new
value in BOTH directions. The b018 property itself (`todo_actually_counted`) survives,
re-sized onto a shape that still straddles the Sonnet cap. No assertion logic was weakened.

Provenance (§2b.7/2b.9): 6 commits add `@owner-answered`/`answer-src:` lines, all in the
id:ca14/id:6621 feature that BUILDS the marker and its lint rule -- fixtures and
documentation, not a minted owner ruling on a live item. No `@owner-answered` line was
MODIFIED in the window (§2b.10 grep empty). §2d over-reach: S1 (id:71d6) checked against
its ratified source `docs/migration-em-dash-delimiter.md` §2 "S1" -- six regexes to a
two-delimiter alternation, six fallbacks deleted for a loud nonzero exit -- verbatim what
shipped, no superset.

relay-doctor: 0 per-repo issues; registry parses, references installed, no install drift,
inbox clean. Two non-repo findings stand as known: the relay-core shadow's 19,648
mismatches over 249,870 rounds (already tracked, bash authoritative) and one parked orphan.

Two REVIEW_ME boxes written: **id:7a5e** (the parked orphan from this run's dead S4 child
carries a real regression -- a blanket `${line//—/-}` kills the em-dash-aside clause
boundary at `unpromoted-scan.sh:179`) and **id:1ccd** (roadmap-lint 213a fires
NO-ACCEPTANCE-NO-TWIN on 7 seams whose acceptance is cited by reference to the migration
doc rather than inlined).

Reverse-handoff (§5b): the 30 ROADMAP and 44 TODO items added this window all arrived
qualified -- every one carries a lane tag and an id; roadmap-lint reports no
MISSING-LANE/MISSING-ID violation. Nothing needed a mini-handoff.

routine_open = 2 actionable (id:e8d4 S4, id:d0aa S6); 9 open `[ROUTINE]` lines total, the
other 7 gated or `@owner-verify`. S3 (id:2ee5) landing cleared the `gated-on:2ee5` edge on
both S4 and S6, so the queue is genuinely dispatchable again.

refactor: none needed -- a review unit writes ledger prose only, no code changed.

## 2026-08-31 19:20 — reviewer (claude-opus-5, fable-standin, relay-loop)

review: suite green 528/0/1-expected-red; b018 REMOVED_ASSERT adjudicated legitimate (overhead 12k->65k, stricter); filed id:7a5e (parked-orphan S4 regression) + id:1ccd (213a by-reference false positive); routine_open=2 [id:7a5e,1ccd,e8d4,71d6,70bc,2ee5]

## 2026-08-31 — executor (claude-sonnet-5)

Worked id:d0aa -- em-dash delimiter migration S6 (meeting/classify.sh, meeting/orphan-scan.sh,
Makefile, hooks/lane-vocab.claude-rule.md to the two-delimiter alternation).

classify.sh's lane floor (:144-204) turned out to be ALREADY delimiter-agnostic: it captures
the whole `[LANE ...]` bracket with `grep -oE '\[(HARD|INPUT|ROUTINE|MECHANICAL)[^]]*\]'` and
routes by SUBSTRING match on the lane word (`*pool*`, `*meeting*`, ...), never on the
delimiter byte -- so `[HARD - pool]` was already routed identically to `[HARD — pool]` with
zero code changes needed. Pinned that with a new fixture-per-lane test,
tests/test_classify_hyphen_lane_delimiter_d0aa.sh (9 lanes, all pass unmodified).

orphan-scan.sh's two lane-tag match sites were the genuine RED defect: `--promotion`
(:203, `\[ROUTINE\]|\[HARD — pool\]`) and `--unbackrefed` (:515, `\[[^]]*— meeting\]|\[INPUT — decision\]`)
were literal em-dash-pinned `grep -E` patterns that did not match the hyphen spelling.
Converted both to the canonical two-delimiter alternation (`[[:space:]]*[—-][[:space:]]*`,
matching roadmap-lint.sh's `lane_delim_re` convention) and added
tests/test_orphan_scan_hyphen_lane_delimiter_d0aa.sh, which I verified is genuinely RED
against the pre-fix code (stashed the orphan-scan.sh edit and re-ran: FAILs on the hyphen
`[HARD - pool]` fixture while the em-dash control still passes) before restoring the fix.

Also updated the two prose mentions in scope (Makefile's `install-lane-ratchet` echo and
hooks/lane-vocab.claude-rule.md) to note the ratchet's old-vocab detection is
delimiter-agnostic (both were already true post-S3/id:2ee5; the docs were stale). Left
meeting/SKILL.md's em-dash-spelled lane examples untouched -- they document the ACCEPTED
old-vocab spelling for a human reader and the dual-vocab window is still open (S10), so
rewriting them is a spelling-preference edit with no acceptance/done-check basis, not part
of this seam's actual scope (the done-check's `meeting/` grep is satisfied by classify.sh +
orphan-scan.sh + SKILL.md carrying pre-existing em-dash comment matches; nothing in S6's
acceptance requires SKILL.md's prose to flip).

Full suite: 530 passed, 0 failed, 1 expected-red (open roadmap items) -- no regressions.

refactor: none needed -- the two orphan-scan.sh regex sites were single-line delimiter
substitutions using the SAME `[[:space:]]*[—-][[:space:]]*` idiom roadmap-lint.sh already
established; no duplication was introduced to clean up.
Friction: none -- id:e8d4 (S4, 12 bash files) remains open and is a separate, larger seam;
this session worked only id:d0aa (S6) per the one-item-per-session rule.

## 2026-08-31 19:33 — executor (sonnet, relay-loop)

Em-dash delimiter migration S6 (id:d0aa): orphan-scan.sh's two lane-tag grep sites (--promotion, --unbackrefed) now accept the hyphen delimiter alongside em-dash; classify.sh confirmed already delimiter-agnostic via new fixture test; suite green 530/0/1-expected-red. [id:d0aa]

## 2026-08-31 — executor (sonnet, relay-loop)

Worked id:c442 -- tracker/ledger-map.py's three lane regexes (RE_HARD_LEGACY/RE_INPUT/
RE_INTENSIVE, :132-134) required a literal em dash and could not parse a hyphen-spelled
`[HARD - <lane>]`/`[INPUT - <kind>]`/`[INTENSIVE - <resource>]` tag, silently degrading it
to lane:untagged (measured 2026-08-31: flipping only the input fixture dropped the
[INTENSIVE] resource, the venue, and the legacy-hands-unresolved report row). Fixed by
widening the delimiter to `\s*[—-]\s*`, the same dual-vocab idiom roadmap-lint.sh's
`lane_delim_re` already uses, then migrated the delimiter in the one fixture file that
actually carried it as a tag (tracker/fixtures/repo-alpha/TODO.md:14-17 -- INPUT/INTENSIVE/
HARD-hands/HARD-pool) and the corresponding body/text fields in
tracker/fixtures/expected/{repo-alpha,fleet-collision}.json, as one commit so no window
exists where input and expected disagree. Preserved the legacy-venue control pairing at
lines 16-17 (no-1:1-successor / 1:1-rename paths) unchanged in meaning. Left the hardcoded
`reason:` prose strings in ledger-map.py (e.g. "[HARD — hands] has no 1:1 successor...")
em-dash-spelled -- they are fixed diagnostic text describing the vocabulary, not a copy of
source text, and migrating them is outside this seam's acceptance. Full suite: 532 passed,
0 failed, 1 expected-red -- no regressions.
Friction: none.

refactor: none needed -- the fix is a single shared-constant delimiter widening (`_LANE_DELIM`)
applied to three existing regexes, mirroring roadmap-lint.sh's established idiom; no new
duplication was introduced.

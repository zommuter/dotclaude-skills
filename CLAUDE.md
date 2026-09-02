# CLAUDE.md — dotclaude-skills

Public toolkit of Claude Code **skills**, **hooks**, and a **statusline** by @zommuter.
Mostly bash scripts + markdown skill specs; Python is stdlib-only (no venv, no deps).
See `ARCHITECTURE.md` for design decisions and rationale; `ROADMAP.md` for the
executor task queue; `TODO.md` for the broader work inventory.

> Maintenance note: the `## Relay contract` pointer below is auto-refreshed by
> relay review mode when its version marker goes stale (version lives in
> `relay/references/executor-contract.md`). Everything else in this file is hand-maintained.

## Commands

```bash
make help               # list targets
make install            # symlink all skills + hooks into ~/.claude, merge allowlist
make install-<skill>    # one skill (meeting, meeting-cross, git-diary-workflow, todo-update, relay, projects)
make install-hooks      # hooks (+ statusline) only
make install-statusline # the quota/cost/model statusbar only (symlinks statusline/ into ~/.claude)
make status             # show symlink state for all skills + statusline
make print-allowlist    # read-only preview of settings.json Bash allowlist entries
make install-allowlist  # idempotent merge into ~/.claude/settings.json (backup → .bak)
make test               # run the full test suite (tests/run-tests.sh)

tests/run-tests.sh                       # full suite
tests/run-tests.sh tests/test_foo.sh     # one test file
```

There is no build step, no version manifest, and no release process — the live
install IS the published version (per-file symlinks, see Layout).

## Versioning

**By design, this repo has no repo-wide version** — no `VERSION` file, no `vX.Y.Z`
tags (the 260+ tags are all `relay-ckpt-*`), no manifest. **Git is the version SSOT**
(SHA + log + tag graph); a hand-maintained version number would just be a drift-prone
cache of what git already derives. The global `~/.claude/CLAUDE.md` **Versioning** rule
(bump-and-tag, bump-includes-lockfile, loose-0.x) is written for `pyproject.toml`-style
repos and **does not apply here** — do not "helpfully" mint a `VERSION` file to satisfy it.
Decided 2026-07-12 (`docs/meeting-notes/2026-07-12-1030-repo-self-governance-versioning-formal-docs.md`, id:8ef3).

**Versions live only on _contract surfaces_** — the few places where a stale copy causes
*silent* breakage, so a `vN` marker carries a real compatibility handshake. Each such
surface carries its own marker AND its own co-located bump discipline (change the contract
⇒ bump the marker ⇒ update any pointer). Current + candidate surfaces:

| Surface | Marker | Why it needs one |
|---|---|---|
| `relay/references/executor-contract.md` | `contract vN` HTML-comment marker (currently v12) | `/relay executor` + the `## Relay contract` pointer must agree on `vN`; bump discipline documented in-file |
| memory-index frontmatter format (id:2e6d) | *(unmarked — candidate)* | a hook regenerates `MEMORY.md` from it; a format change silently breaks the index |
| `classify.sh` TSV column contract | *(unmarked — candidate)* | SKILL.md parses fixed columns |
| allowlist generator's 8-entries-per-script expansion | *(unmarked — candidate)* | literal-match settings.json entries |

**A public-repo `CHANGELOG.md` is ADOPTED — this AMENDS the 2026-07-12 deferral (D3, meeting
`docs/meeting-notes/2026-07-17-1541-semver-trigger-and-fleet-changelog.md`, id:b8fa).** The
superseded text read: *"A public-repo `CHANGELOG.md` is deferred — trigger is the first external
consumer who needs to pin a version for a reproducible install (none exists today; `git log`
covers the rest)."* That trigger has **not** fired and is **not** the basis for the change —
the amendment rests on a premise `8ef3` never weighed: it evaluated only *external* consumers
and correctly found none, but this repo is consumed **internally**, through per-file symlinks,
by every other repo's sessions. That is a different consumer class. Recorded as an **explicit
amendment on an unconsidered premise**, not a reinterpretation of `8ef3`'s words (owner-ratified
2026-07-17; the distinction is the CLAUDE.md "derived doc vs ratified source" rule).

**`8ef3`'s no-version ruling STANDS, unamended** — still no repo-wide version, no `VERSION`
file, no `v*` tags, git remains the version SSOT. This repo is version-less **and** has a
CHANGELOG; the two are independent. Because it has no manifest, it has no bump to key entries
off, so its changelog is **date-bucketed**, fired per relay integrate — whereas semver repos
bucket by release (id:e647/b8fa, shipping together per D4). Entries are **derived** from
existing relay state (`workedIds`, `relay-ckpt-*` tag messages, `RELAY_LOG.md`) and start from
now — never backfilled, since per-close tags are unrecoverable after the 2026-07-16 batch.
The deriver is `relay/scripts/changelog-append.sh` (invoked from the relay integrator's
step 2b); its semver sibling — the reviewer-only bump — is `relay/scripts/version-bump.sh`
(step 2a). Neither is ever run by an executor.

## Layout

| Path | What |
|---|---|
| `meeting/` | The big skill: SKILL.md + format/personas/broker-mode/cross-mode specs and ~12 helper scripts (`append.sh`, `orphan-scan.sh`, `classify.sh`, `broker-curl.sh`, `broker.py`, …) |
| `git-diary-workflow/` | Post-prompt commit+push+diary skill; `git-lock-push.sh` is the flock'd push serializer used repo-wide |
| `todo-update/` | TODO.md maintenance skill; `archive-done.sh` moves `[x]` items to `TODO.archive.md` and prunes empty sections |
| `meeting-cross/` | Deprecated alias skill → `/meeting --cross` (deletion gated, TODO id:4f5f) |
| `projects/` | Project-dashboard skill (SKILL.md only) |
| `relay/` | The reviewer/executor relay skill itself (this contract comes from there). `references/executor-contract.md` is the versioned executor contract loaded by `/relay executor`; the `## Relay contract` pointer below must match its `vN` marker. `scripts/lib-private-remote.sh` is THE single "is this remote a PRIVATE/LAN host?" predicate — sourced by BOTH `hooks/pre-push-privacy-gate.sh` and `scripts/integrate.sh`'s per-remote push narrowing (id:4d44); it reads `private-host:` directives from the PRIVATE, never-committed pattern file at runtime, and `git-lock-push.sh`'s `is_ssh_url()` is NOT a substitute (it is an SSH-AUTH predicate and fails toward auto-publish). `scripts/self-transcript.sh` is THE single "where is the CALLING agent's own transcript?" resolver (id:ff30) — `$CLAUDE_SESSION_ID` names the top-level session, which is the *directory* holding a child's `subagents/agent-<id>.jsonl`; siblings are disambiguated by a `--marker` string from the child's own dispatch prompt. `context-budget.sh --self` is its only consumer today and is what makes executor-contract rule 2c runnable at all. `scripts/heartbeat.sh` is the run-liveness marker (id:e149) the outage watchdog (id:98f0) + auto-reconcile-on-restart (`relay-reconcile.sh --auto`, id:7809) both read |
| ~~`fables-turn/`, `fables-executor/`~~ | **Removed 2026-06-15** — deprecated alias stubs → `/relay` + `/relay executor`. Migrated (no remaining cron/invocations); untracked, deleted locally, and the `~/.claude/skills` symlinks uninstalled. The 3 `fables-*` meeting-notes stay as history. `.gitignore` still blocks accidental re-add. |
| `hooks/` | Stop/Notification hook scripts; settings.json snippets in `hooks/README.md`. `memory-index-sync.py` (PostToolUse) regenerates the auto-memory index on any memory-file write (id:2e6d); `parallel-edit-detector.py` + `pathspec-drop-guard.py` guard concurrent-edit / pathspec-drop hazards. The PreToolUse/Bash guard family is `pathspec-drop-guard.py`, `rm-force-guard.sh` (id:5218) and `destructive-git-guard.py` (id:3a09, WIRED since 2026-08-21; since the owner's 2026-08-22 ruling its five tree-wide forms are an UNCONDITIONAL DENY — no context branch, no defer to `permissions.ask`; the rationale is in the file's docstring, do not re-litigate it); `make status-hooks` reports each hook's symlink state plus any hook present in `~/.claude/hooks/` that this repo does not manage |
| `statusline/` | `statusline-command.sh` — quota/cost/model statusline (reads JSON on stdin) |
| `tools/` | `allowlist.py` (settings.json allowlist generator) + `allow-extra.txt`; `ctx-budget.sh` (advisory SKILL.md token-budget audit); `settings-env.py` (settings.json env-block applier, used by `make install-relay-env`); `model-probe.sh` + `model-probe.battery.jsonl` (standing model-quality probe, id:dba3); `quota-sample.sh` + `quota-sample.{service,timer}` + `quota-report.py` (idle-resilient usage-quota sampler → git-versioned JSONL in `~/src/claude-diary/quota/`, `make install-quota-timer`, id:d267); `relay-watchdog.sh` + `relay-watchdog.{service,timer}` (outage watchdog — notifies when a local relay loop died without a clean stop, via the shared run-heartbeat; NO `claude -p`; `make install-relay-watchdog`, id:98f0); `memory-index.py` (GENERATES the auto-memory `MEMORY.md`/`MEMORY.archive.md` index from per-file frontmatter — `--check` exits non-zero on drift, `--write` regenerates atomically; the derived-index/SSOT source-of-truth for the `hooks/memory-index-sync.py` PostToolUse hook, id:2e6d); `privacy-audit.sh` (TREE-scoped privacy audit over `git ls-files`, id:9bfc part (a) — the companion to the DIFF-scoped `hooks/pre-push-privacy-gate.sh`, which structurally cannot see already-published exposure. Prints pattern INDICES, never the pattern: the gate's `pattern<TOKEN>` output spells out the PRIVATE pattern, and pasting it into a tracked file in this PUBLIC repo publishes it. Resolved report goes to `~/.claude/logs/privacy-audit.log`, and the script REFUSES to write that log anywhere git could commit it) |
| `tracker/` | Tracker-pilot mapping (TODO id:2bb1, `children-of:4a5c`). `SCHEMA.md` is the durable artifact — the construct-by-construct bespoke-markdown→tracker mapping; `schema/ledger-intermediate.schema.json` is the machine-readable contract adapters (id:90f2) read; `ledger-map.py` is the stdlib-only reference mapper/validator/round-trip projector; `fixtures/` holds fixture ledgers + golden documents. Composite `(repo,id)` key; per-view `todo_status`/`roadmap_status`/`review_status`, **never** collapsed into one status; cross-repo id collisions fail loudly. Markdown stays SSOT and **no relay script writes to a tracker**. The fleet driver is id:94ce, not this. `homonym-worksheet.sh`/`.py` render the adjudication evidence behind `homonym-allowlist.txt` (id:e977); their OUTPUT quotes private-repo titles, so it is written outside any repo and never committed. `mirror-tokens.txt` is a SEPARATE surface from `homonym-allowlist.txt` (id:9fa2): the allow-list claims two items are UNRELATED, a mirror claims they are the SAME item on both sides of a `<parent>`/`<parent>-<suffix>` pair. Each line declares `<4-hex token> <repo> <repo>` and a mirror is scoped to that EXACT PAIR, never to the parent's whole plugin family (owner's narrowing ruling 2026-09-01): `validate` requires SET EQUALITY between the declared repos and the repos observed to carry the token, so the same token minted independently in a THIRD family repo stays a class-A ERROR naming both sets. A BARE token is REJECTED (exit 2) — that spelling carried the superset hole, since the family predicate is satisfied by any superset; `fleet-import.sh` matches the bare form too, so a file still in the old spelling fails LOUDLY through the driver instead of silently building no flag. A REFUSED mirror declaration OUTRANKS `homonym-allowlist.txt`: a declared token never falls through to the allow-list, so allow-listing it can neither cancel the refusal nor make the run pass, and the error tells the operator to fix or remove the DECLARATION. Repo-name shape only GUARDS a declared mirror, it never drives one — a purely structural rule was tried and reverted for swallowing `5e19`/`cfd1` (owner ruled: re-mint) and `df4e`; every recognised mirror is counted in `validate` output |
| `tests/` | Plain-bash test suite (see Testing) |
| `CHANGELOG.md` | DATE-bucketed (this repo carries no version — see Versioning); DERIVED at relay integrate by `relay/scripts/changelog-append.sh`, never hand-edited, never backfilled |
| `docs/meeting-notes/` | Design-meeting records — the project's decision log; cited from TODO items |

## Conventions

- **SOPs are co-located, not filed separately.** This repo's two de-facto Standard
  Operating Procedures are `relay/references/executor-contract.md` (the executor SOP,
  versioned `vN`) and `git-diary-workflow/SKILL.md` (the post-prompt commit+diary SOP).
  They live next to the code they govern by design — there is **no `SOP/` or `adr/`
  directory**, and decision supersession is tracked via typed ledger edges on the `id:`
  ecosystem, not parallel ADR files (decided 2026-07-12, id:a6e1).
- **Edit canonical paths.** Skills are installed as per-file symlinks
  `~/.claude/skills/<skill>/<f>` → this repo. Always edit files **here**
  (`~/src/dotclaude-skills/...`), never via the `~/.claude/skills/` symlink paths.
- **`id:XXXX` token ecosystem.** Action items in TODO.md / meeting notes / ROADMAP.md
  carry opaque 4-hex tokens as `<!-- id:XXXX -->`. Mint via
  `meeting/append.sh new-id` (or `new-ids N <root>`) — **never invent tokens**.
  `meeting/orphan-scan.sh` correlates meeting-note items against the TODO ledger by
  exact token match.
- **Single-id-two-views (relay ↔ meeting).** TODO.md is the design ledger ("why");
  ROADMAP.md is the relay's execution queue ("now"). When the relay promotes work
  TODO already tracks (handoff C2 / review step 5), it **reuses the existing TODO id**,
  never mints a duplicate — the same token spans both ledgers. `orphan-scan.sh
  --cross-ledger` flags any id whose checkbox state disagrees across the two (e.g.
  closed in ROADMAP, still open in TODO). TODO/ROADMAP/REVIEW_ME are shared, non-union
  write surfaces between `/meeting` and the relay worktree merge — keep writes
  line-scoped. See `docs/meeting-notes/2026-06-15-0715-meeting-fables-interaction.md`.
- **Registry appends go through `append.sh`.** Never Edit/Write
  `discoveries.md`/`personas.md`/the shared inbox directly — `append.sh` is the
  allowlisted, flock-guarded path.
- **Local-only files.** `meeting/discoveries.md` and `meeting/user-profile.md` exist
  only in `~/.claude/skills/meeting/` and are **never committed** here.
- **Detail notes are EDITABLE, and an edit is DECLARED in the note's header** (owner-ratified
  2026-09-02; loderite raised it, same ruling both repos). When a fleet rule — retired
  vocabulary, the lane-delimiter migration, a banned token — is violated inside prose that
  `tools/ledger-shrink.py` relocated into `docs/ledger-notes/<id>.md`, **fix it in the note**
  and say so in the header. Notes are not immutable. Two reasons: a note that permanently
  violates a rule keeps that rule's guard red forever, and note prose gets copied back out
  into new items, so a violation parked there is a violation in flight. Rejected alternative:
  exempting notes — which is what we had, **by accident rather than by decision** (the
  vocabulary ratchet is a staged-diff hook matching a checkbox line's leading lane bracket,
  and notes contain no checkbox lines, so it structurally cannot fire on them). loderite found
  a retired token that had been invisible for exactly that reason. **Why the declaration is
  load-bearing and not bookkeeping:** every generated note asserts in its own header that
  "Nothing was deleted -- the prose below is reproduced verbatim". An edit makes that sentence
  FALSE, so the declaration is what keeps the note honest about itself. It belongs in the
  header, not only in a commit message.
- **`REVIEW_ME.md` is OUT of the ledger line-shrink; it is compacted by ARCHIVING resolved
  boxes** (ratified for THIS repo by its owner 2026-09-02). **Provenance, stated precisely
  because the distinction is the point:** the reasoning came to us as loderite's session
  RELAYING its owner's lean, and he had not ratified it there at the time we adopted it --
  so this is our own owner's decision, taken on a relayed argument we found convincing, not
  a joint fleet ruling. If loderite's ratification amends it, expect a delta rather than
  assuming the two repos already agree. (This is `id:1365` in miniature: a claim carrying an
  owner's authority, arriving through a channel that cannot be verified.) A review box is
  evidence written to be read IN FULL by the
  person it is for, so relocating its prose into `docs/ledger-notes/<id>.md` puts the evidence
  one indirection away from its only reader -- a loss the byte count does not show. Archive
  RESOLVED boxes aggressively instead; never relocate prose out of an open one. A review box
  has a natural terminal state that a TODO item does not, which is what makes archiving the
  right lever here and the wrong one there. **This was an ACCIDENTAL exemption before it was a
  decision** -- wave 1 shrank 10 boxes because nothing said not to, which is the same
  by-accident-not-by-decision shape as the notes-are-editable question. Most REVIEW_ME boxes
  legitimately carry NO `id:` (7 of 21 here), so id-keyed tooling does not reach them and the
  archive pass is the only mechanism that does.
- **Shared-file writes use `flock`.** See `append.sh`, `diary-append.sh`,
  `git-lock-push.sh`, `ckpt-tag.sh` for the pattern (fd 8/9 + lock file; `*.lock`
  is gitignored).
- **merge=union files**: `meeting/personas.md` and `RELAY_LOG.md` (append-only).
- **Bash style**: `set -euo pipefail`; scripts accept an optional root arg defaulting
  to `git rev-parse --show-toplevel`; helper scripts print short stdout and log
  details to `~/.claude/logs/*.log`.
- **OS / tooling**: Manjaro — `pamac`, never `pacman -S`. Python via `uv` if deps
  ever appear (currently stdlib-only, system `python3` is fine).

## Gotchas (hard-won; do not rediscover)

- **Permission-prompt classes**: `${VAR:-default}` expansion in a Bash call triggers
  a permission prompt regardless of allowlist — probe env vars with plain
  `echo "$VAR"`. Compound `cd X && cmd` and `;`-chained commands also bypass
  allowlist patterns; use separate Bash calls.
- **Allowlist matching is literal**, so `tools/allowlist.py` emits **8 entries per
  script** (tilde/abs × symlink-dest/source × bare/`*`). Patterns the generator
  can't express go in `tools/allow-extra.txt`.
- **broker-curl.sh JSON**: build bodies with `jq -n --arg` (apostrophes break
  single-quoted literals). Never inline a brace-containing default in `${...}` —
  bash closes the expansion at the first `}` and corrupts the JSON. All broker HTTP
  goes through `broker-curl.sh`, never raw curl (keeps allowlist to one entry).
- **statusline**: `/api/oauth/usage` 429s aggressively; the script has its own
  cache/backoff/lockfile in `/tmp` — don't add polling.
- **Makefile testing**: override the install root with `make DEST_DIR=/tmp/x
  install-<skill>`; never point tests at the real `~/.claude`.
- **Never launch Claude with cwd=`~/.claude/`** (harness treats it as config root;
  see global CLAUDE.md). For `~/.claude` git ops use `git -C ~/.claude`.
- **archive-done.sh** only archives `[x]` items that were already done in the prior
  commit, or are ≥30 days old by trailing "on YYYY-MM-DD" date; section pruning
  protects `Done`/`Current` headings.
- **relay discovery is signature-cached** (id:c3a6): `discover-sig.sh` hashes a SUPERSET
  of every input the classifier shard reads; `relay-loop.js` reuses last round's verdict
  when a repo's sig is unchanged, so the shard re-runs only on churn. It is **fail-open** —
  an empty/sentinel sig (or a cache miss) always re-classifies; the cache is never a
  correctness authority. If you add a NEW signal to the shard prompt, add it to
  `discover-sig.sh`'s blob too, or its verdict can go stale (under-invalidation is the only
  hazard — over-hashing merely wastes a re-classify).
- **Discovery is MECHANICAL, not an LLM hop — do not cost it as inference.** Both discovery
  hops dispatch at `MECH_MODEL` (`relay-loop.js:137`), which is `'bash'` unless
  `MECH_FALLBACK === 'fallback-haiku'`: the prelude at `:1944` (id:86a2) and the shard at
  `:2113` (id:24ec), where `discover-chunk.sh` is one fenced `relay-mech` command with ZERO
  agents and no LLM judgment. **This line previously read "the `discover-shard` agent is
  pinned `model: 'sonnet'`" — true when written, false since id:24ec**, and the stale copy
  was traced (2026-08-26) as the likely source of `id:79fd`'s false premise that continuous
  re-discovery costs Sonnet tokens. It does not. The real per-scan cost is that the shard
  runs `reconcile-repo.sh` LIVE with bounded git side effects (fetch / ff-merge when behind
  origin / uv.lock cascade commit / worktree reap+park) — unmeasured, and the thing to price
  in any continuous-dispatch design. Note `meta.phases[1].detail` still says "parallel
  discover-shard classifiers"; `relay-loop.js:5-8` marks that block as purely a DISPLAY
  grouping with zero behavioural change, so do not read it as a model claim.

## Testing

Plain-bash harness, zero dependencies beyond `bash`/`python3`/`jq`/`make`:

- `tests/run-tests.sh` runs every `tests/test_*.sh`. Each test file that specs a
  roadmap item declares it with a `# roadmap:XXXX` header comment. Defect-fix
  tests without a roadmap item omit the header (and say so in a comment) — their
  failures always count.
- **Expected-red semantics**: a failing test file whose roadmap item checkbox in
  `ROADMAP.md` is still **unticked** is reported `EXPECTED-RED` and does **not**
  fail the suite (red tests are the spec for open items). Once the item is ticked,
  failures are real failures. Passing tests always count.
- Therefore: tick your item's checkbox in ROADMAP.md, then `make test` must be
  fully green — that is the definition-of-done check.
- Tests must be hermetic: work in `mktemp -d`, override `HOME`/`DEST_DIR`/roots via
  args or env, never touch `~/.claude` or the network.
- **`# fails-against:` -- a defect-fix test declares the negative case it must fail against**
  (id:292b), and `make verify-negatives` RUNS that case (id:a73c). The rule the runner
  enforces, which the declaration alone cannot: **it is not enough that the test fails
  against the declared revision -- the assertion that fails must be the one the file claims
  to pin.** Dying at an earlier assertion, or being killed by a fixture-sanity probe, is red
  for the wrong reason and is exactly as vacuous as passing. Machine-readable form, in the
  file's LEADING comment block (directives lower down belong to fixture heredocs, not to the
  file): `# fails-against-rev: <rev> -- <path>…` or `# fails-against-mutation: <command>`,
  each followed by `# fails-against-assertion: <substring of the FAIL: line that must fire>`.
  Where a fix changes a FORMAT, author the negative case in the ancestor's OWN spelling and
  order it FIRST, and record per-ancestor reachability in the header -- some assertions are
  structurally unreachable at the parent, which is legitimate but must be on the record.
  Two rules the runner ENFORCES, both learned by being fooled into a false pass on 2026-09-01:
  **the declared substring must match EXACTLY ONE line of the file's body** (0 or 2+ is a
  CONFIG ERROR, exit 2 -- a bare case prefix like `L non-C locale:` cannot say which of a
  case's four assertions fired, and an early message that NAMES a later assertion, e.g.
  `"(a) old format rejected outright, so (b) guard was never reached"`, matched `(b) guard` by
  substring and was reported green); and **when a non-exiting accumulator emits several FAIL
  lines, the declaration must match the LAST one** -- all fired lines are reported, and
  matching any-of degrades the guarantee to little more than exit status. Narrow the
  declaration; never loosen the check. A file that emits no line-leading `FAIL:` at all (55 of
  546 today) can never be verified this way and needs an exemption with a reason.
  `tests/lint-vacuous-fixtures.py` (advisory) checks the declaration; the runner is opt-in
  and NOT part of `make test` (seconds per case). Exemptions live in ONE reviewable file,
  `tests/negative-case-exemptions.txt`, each with a written reason.
- **A `# fails-against-mutation:` command is an arbitrary `bash -c` and is NOT sandboxed.**
  The runner gives it a private sandbox (its own `TMPDIR`, a `GIT_CEILING_DIRECTORIES` that
  stops git discovery walking up out of the scratch, and a post-run stray-entry check), but a
  mutation can still write any ABSOLUTE path the invoking user can write -- confirmed by
  clobbering a canary in a real fixture repo. Treat a mutation command as reviewed code, like
  any other script here; confine it to relative paths under its cwd.

## Relay contract <!-- relay-executor contract v18 -->

This repo is managed by a reviewer/executor relay. Load `/relay executor` before
working on any item, then follow its rules exactly.

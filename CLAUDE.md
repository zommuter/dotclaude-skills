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
| `relay/references/executor-contract.md` | `contract vN` HTML-comment marker (currently v8) | `/relay executor` + the `## Relay contract` pointer must agree on `vN`; bump discipline documented in-file |
| memory-index frontmatter format (id:2e6d) | *(unmarked — candidate)* | a hook regenerates `MEMORY.md` from it; a format change silently breaks the index |
| `classify.sh` TSV column contract | *(unmarked — candidate)* | SKILL.md parses fixed columns |
| allowlist generator's 8-entries-per-script expansion | *(unmarked — candidate)* | literal-match settings.json entries |

A public-repo `CHANGELOG.md` is **deferred** — trigger is the first external consumer who
needs to pin a version for a reproducible install (none exists today; `git log` covers the rest).

## Layout

| Path | What |
|---|---|
| `meeting/` | The big skill: SKILL.md + format/personas/broker-mode/cross-mode specs and ~12 helper scripts (`append.sh`, `orphan-scan.sh`, `classify.sh`, `broker-curl.sh`, `broker.py`, …) |
| `git-diary-workflow/` | Post-prompt commit+push+diary skill; `git-lock-push.sh` is the flock'd push serializer used repo-wide |
| `todo-update/` | TODO.md maintenance skill; `archive-done.sh` moves `[x]` items to `TODO.archive.md` and prunes empty sections |
| `meeting-cross/` | Deprecated alias skill → `/meeting --cross` (deletion gated, TODO id:4f5f) |
| `projects/` | Project-dashboard skill (SKILL.md only) |
| `relay/` | The reviewer/executor relay skill itself (this contract comes from there). `references/executor-contract.md` is the versioned executor contract loaded by `/relay executor`; the `## Relay contract` pointer below must match its `vN` marker. `scripts/heartbeat.sh` is the run-liveness marker (id:e149) the outage watchdog (id:98f0) + auto-reconcile-on-restart (`relay-reconcile.sh --auto`, id:7809) both read |
| ~~`fables-turn/`, `fables-executor/`~~ | **Removed 2026-06-15** — deprecated alias stubs → `/relay` + `/relay executor`. Migrated (no remaining cron/invocations); untracked, deleted locally, and the `~/.claude/skills` symlinks uninstalled. The 3 `fables-*` meeting-notes stay as history. `.gitignore` still blocks accidental re-add. |
| `hooks/` | Stop/Notification hook scripts; settings.json snippets in `hooks/README.md`. `memory-index-sync.py` (PostToolUse) regenerates the auto-memory index on any memory-file write (id:2e6d); `parallel-edit-detector.py` + `pathspec-drop-guard.py` guard concurrent-edit / pathspec-drop hazards |
| `statusline/` | `statusline-command.sh` — quota/cost/model statusline (reads JSON on stdin) |
| `tools/` | `allowlist.py` (settings.json allowlist generator) + `allow-extra.txt`; `ctx-budget.sh` (advisory SKILL.md token-budget audit); `settings-env.py` (settings.json env-block applier, used by `make install-relay-env`); `model-probe.sh` + `model-probe.battery.jsonl` (standing model-quality probe, id:dba3); `quota-sample.sh` + `quota-sample.{service,timer}` + `quota-report.py` (idle-resilient usage-quota sampler → git-versioned JSONL in `~/src/claude-diary/quota/`, `make install-quota-timer`, id:d267); `relay-watchdog.sh` + `relay-watchdog.{service,timer}` (outage watchdog — notifies when a local relay loop died without a clean stop, via the shared run-heartbeat; NO `claude -p`; `make install-relay-watchdog`, id:98f0); `memory-index.py` (GENERATES the auto-memory `MEMORY.md`/`MEMORY.archive.md` index from per-file frontmatter — `--check` exits non-zero on drift, `--write` regenerates atomically; the derived-index/SSOT source-of-truth for the `hooks/memory-index-sync.py` PostToolUse hook, id:2e6d) |
| `tests/` | Plain-bash test suite (see Testing) |
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
  when a repo's sig is unchanged, so an LLM shard fires only on churn. It is **fail-open** —
  an empty/sentinel sig (or a cache miss) always re-classifies; the cache is never a
  correctness authority. If you add a NEW signal to the shard prompt, add it to
  `discover-sig.sh`'s blob too, or its verdict can go stale (under-invalidation is the only
  hazard — over-hashing merely wastes a re-classify). The `discover-shard` agent is pinned
  `model: 'sonnet'` (it used to inherit the Opus session model — the 35%-overhead leak).

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

## Relay contract <!-- relay-executor contract v8 -->

This repo is managed by a reviewer/executor relay. Load `/relay executor` before
working on any item, then follow its rules exactly.

# CLAUDE.md — dotclaude-skills

Public toolkit of Claude Code **skills**, **hooks**, and a **statusline** by @zommuter.
Mostly bash scripts + markdown skill specs; Python is stdlib-only (no venv, no deps).
See `ARCHITECTURE.md` for design decisions and rationale; `ROADMAP.md` for the
executor task queue; `TODO.md` for the broader work inventory.

> Maintenance note: only the `## Relay contract` section below is auto-refreshed
> (by fables-turn review mode, when its version marker goes stale). Everything else
> in this file is hand-maintained and preserved across relay turns.

## Commands

```bash
make help               # list targets
make install            # symlink all skills + hooks into ~/.claude, merge allowlist
make install-<skill>    # one skill (meeting, meeting-cross, git-diary-workflow, todo-update)
make install-hooks      # hooks + statusline only
make status             # show symlink state for all skills
make print-allowlist    # read-only preview of settings.json Bash allowlist entries
make install-allowlist  # idempotent merge into ~/.claude/settings.json (backup → .bak)
make test               # run the full test suite (tests/run-tests.sh)

tests/run-tests.sh                       # full suite
tests/run-tests.sh tests/test_foo.sh     # one test file
```

There is no build step, no version manifest, and no release process — the live
install IS the published version (per-file symlinks, see Layout).

## Layout

| Path | What |
|---|---|
| `meeting/` | The big skill: SKILL.md + format/personas/broker-mode/cross-mode specs and ~12 helper scripts (`append.sh`, `orphan-scan.sh`, `classify.sh`, `broker-curl.sh`, `broker.py`, …) |
| `git-diary-workflow/` | Post-prompt commit+push+diary skill; `git-lock-push.sh` is the flock'd push serializer used repo-wide |
| `todo-update/` | TODO.md maintenance skill; `archive-done.sh` moves `[x]` items to `TODO.archive.md` and prunes empty sections |
| `meeting-cross/` | Deprecated alias skill → `/meeting --cross` (deletion gated, TODO id:4f5f) |
| `projects/` | Project-dashboard skill (SKILL.md only) |
| `fables-turn/` | The reviewer/executor relay skill itself (this contract comes from there) |
| `hooks/` | Stop/Notification hook scripts; settings.json snippets in `hooks/README.md` |
| `statusline/` | `statusline-command.sh` — quota/cost/model statusline (reads JSON on stdin) |
| `tools/` | `allowlist.py` (settings.json allowlist generator) + `allow-extra.txt` |
| `tests/` | Plain-bash test suite (see Testing) |
| `docs/meeting-notes/` | Design-meeting records — the project's decision log; cited from TODO items |

## Conventions

- **Edit canonical paths.** Skills are installed as per-file symlinks
  `~/.claude/skills/<skill>/<f>` → this repo. Always edit files **here**
  (`~/src/dotclaude-skills/...`), never via the `~/.claude/skills/` symlink paths.
- **`id:XXXX` token ecosystem.** Action items in TODO.md / meeting notes / ROADMAP.md
  carry opaque 4-hex tokens as `<!-- id:XXXX -->`. Mint via
  `meeting/append.sh new-id` (or `new-ids N <root>`) — **never invent tokens**.
  `meeting/orphan-scan.sh` correlates meeting-note items against the TODO ledger by
  exact token match.
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

## Testing

Plain-bash harness, zero dependencies beyond `bash`/`python3`/`jq`/`make`:

- `tests/run-tests.sh` runs every `tests/test_*.sh`. Each test file declares its
  roadmap item with a `# roadmap:XXXX` header comment.
- **Expected-red semantics**: a failing test file whose roadmap item checkbox in
  `ROADMAP.md` is still **unticked** is reported `EXPECTED-RED` and does **not**
  fail the suite (red tests are the spec for open items). Once the item is ticked,
  failures are real failures. Passing tests always count.
- Therefore: tick your item's checkbox in ROADMAP.md, then `make test` must be
  fully green — that is the definition-of-done check.
- Tests must be hermetic: work in `mktemp -d`, override `HOME`/`DEST_DIR`/roots via
  args or env, never touch `~/.claude` or the network.

## Relay contract <!-- fables-turn contract v1 -->

This repo is managed by a reviewer/executor relay. Executor sessions (you, unless
you were told you are the reviewer) follow these rules:

1. **Scope**: work only `[ROUTINE]` items from ROADMAP.md, one item per session.
   Never start `[HARD]` items — they are reserved for the reviewer model.
2. **Definition of done**: the item's previously-failing tests pass, a refactor
   pass is done, and the FULL test suite is green. Nothing else counts.
3. **Test integrity**: never weaken, delete, skip, or rewrite a test to make it
   pass. The reviewer diffs all test files against the last `fable-ckpt-*` tag
   and re-runs the original test versions; gamed tests will be found and the
   item reopened. If a test looks wrong or the spec seems ambiguous: STOP,
   append `BLOCKED: <item-id> <reason>` to RELAY_LOG.md, and pick another item.
4. **Self-report**: before ending the session, append one paragraph to
   RELAY_LOG.md — what was done, friction encountered, anything surprising.
   If an item was mis-sized (too big/small for one session), add a
   `friction: <item-id> <note>` line to the relevant commit message.
5. **Hygiene**: commit early and often with conventional messages; never force-push;
   never edit ROADMAP.md item definitions (tick checkboxes only); pamac not pacman;
   uv for Python.

# Deep audit — `meeting/` skill

**Date:** 2026-07-01
**Scope:** whole-skill audit of `meeting/` (SKILL.md + format/personas/broker/cross specs +
~13 helper scripts). Complements the relay loop's diff-since-checkpoint review, which does not
re-scan unchanged files.
**Method:** every finding was verified by reading the source and, where a behaviour is claimed,
by running the script on a hermetic fixture — not asserted from inspection alone.

## Verdict summary

| Dimension | Verdict |
|---|---|
| 1. Bash discipline (`set -euo pipefail`, swallow ban, root-arg, logging) | 3 findings (1 MED, 2 LOW) |
| 2. Concurrency (flock on shared writes) | CLEAN |
| 3. Spec ↔ implementation drift | 2 findings (1 MED, 1 LOW) |
| 4. Tests (coverage + hermeticity) | 1 finding (LOW) |
| 5. broker.py / broker-curl.sh security + robustness | 2 findings (1 MED, 1 LOW) |
| 6. Ctx budget | CLEAN (known WARN, no new issue) |
| 7. Known-gotcha adherence (allowlist, `${VAR:-}`, compound cmds) | CLEAN |

**Total: 8 findings — 0 HIGH, 3 MED, 5 LOW.** No correctness-critical or data-loss defect found;
concurrency (the highest-risk dimension) is CLEAN. The two MED functional bugs both cause a
*silent* wrong result (an advisory scan that no-ops, a gate flag that mis-fires), which is exactly
the class the repo's own "no silent swallow / fail loud" doctrine targets.

---

## Dimension 2 — Concurrency: CLEAN

Every shared-file write path was traced and each is correctly serialised:

- `append.sh` — registry appends (`discoveries`/`personas`/`inbox`) and the destructive
  `inbox-done` both wrap the write in `( flock -x 9 … ) 9>"${dest}.lock"` (lines 34-47, 132-135).
- `memory-append.sh` — `( flock -x 9 … ) 9>"$lock_file"` around the trailing-newline+append
  (lines 46-56); lock path is resolved to an absolute path first (line 37) so the lock is stable
  regardless of cwd. The parent-dir/`touch` outside the lock is a benign create race, correctly
  called out in its own comment (lines 42-44).
- `md-merge.py` — `fcntl.flock(lock_fd, LOCK_EX)`, re-reads the file *under* the lock (picks up
  concurrent deltas), writes atomically via tmp+rename, and — with `--commit` — performs the
  scoped `git add -- <file>` + commit *inside the same lock* so write+commit is atomic (lines
  112-138, 150-193). No TOCTOU: the read that the merge is computed against happens after the lock
  is held.
- `persona-state.py` — shard-then-collapse: per-session shard writes are contention-free (unique
  filename), and `collapse` re-globs the shard set *under* the flock before folding (lines 118-142).

No write path bypasses its lock. Lock files all match the gitignored `*.lock` convention.

---

## Dimension 1 — Bash discipline

### Finding 1.1 (MED) — `cost-of.sh` and `find-todos.sh` lack `set -euo pipefail`
- **Evidence:** `meeting/cost-of.sh` (no `set` line anywhere; relies solely on `${1:?…}` for the
  missing-arg case) and `meeting/find-todos.sh` (starts straight into a `find …` pipeline). Every
  other meeting `*.sh` sets it (`append.sh:14`, `classify.sh:16`, `orphan-scan.sh:24`,
  `gh-audit.sh:12`, `profile-active.sh:6`, `broker-curl.sh:14`, `memory-append.sh:17`).
- **Why it matters:** the project Bash-style convention (CLAUDE.md) mandates `set -euo pipefail`.
  In `cost-of.sh` an unset intermediate (e.g. a malformed `jq` pass) silently yields a blank field
  rather than failing; `find-todos.sh` masks any `find`/`while` error. Low blast radius (both are
  read-only advisory helpers) but a convention breach that the style rule exists to catch.
- **Fix:** add `set -euo pipefail` after the shebang/comment header in both; verify `cost-of.sh`
  still exits non-zero on a missing session (the `${1:?}` already does) and that `find-todos.sh`'s
  intentional `2>/dev/null` on the `find` is annotated (see 1.2).
- **Action:** `- [ ] [dotclaude-skills] add set -euo pipefail to meeting/cost-of.sh + find-todos.sh <!-- id:b3ca -->`

### Finding 1.2 (LOW) — meeting is the largest un-annotated-swallow offender under the id:4347 ban
- **Evidence:** `tools/check-no-silent-swallow.sh meeting` reports **38 un-annotated suppressions**
  (25 × `2>/dev/null`, 13 × `|| true`) across `append.sh`, `classify.sh`, `cost-of.sh`,
  `find-todos.sh`, `gh-audit.sh`, `memory-append.sh`, `orphan-scan.sh`. Many are legitimate
  (fail-soft `gh`, missing-ledger `cat`, git-toplevel fallback) but none carry the
  `# swallow-ok: <reason>` annotation the ban (id:4347) requires to distinguish deliberate from
  accidental. The checker currently ships advisory (exit 0), so the suite stays green — but the
  moment id:4347 flips to `--enforce`, the meeting tree is the biggest source of failures.
- **Why it matters:** the whole point of id:4347 is that a legitimate swallow is *sized and
  annotated* so a future accidental one stands out. An un-annotated legitimate swallow is
  indistinguishable from the false-"0 orphans / clean" regressions the ban was built to prevent.
- **Fix:** annotate each intentional swallow with `# swallow-ok: <reason>` (e.g. on
  `orphan-scan.sh:59` `# swallow-ok: missing ledger files are expected — cat union is best-effort`);
  the few that are *not* obviously intentional (see 3.x) get fixed instead of annotated. Do this
  before id:4347 flips to enforce.
- **Action:** `- [ ] [dotclaude-skills] annotate the 38 legitimate # swallow-ok swallows in meeting/*.sh before id:4347 flips to --enforce <!-- id:2f15 -->`

### Finding 1.3 (LOW) — `orphan-scan.sh` root-arg default lacks the sibling fail-soft fallback
- **Evidence:** `orphan-scan.sh:38` is `ROOT="${1:-$(git rev-parse --show-toplevel)}"` — no
  `2>/dev/null || pwd`. Every other helper uses the fail-soft form
  (`append.sh:67`, `classify.sh:18`, `gh-audit.sh:28`: `$(git rev-parse --show-toplevel 2>/dev/null || pwd)`).
  Run outside a git repo with no arg, `orphan-scan.sh` aborts with a git error (and under
  `set -euo pipefail` the whole script dies) instead of degrading to cwd.
- **Why it matters:** minor inconsistency; in practice `/meeting` always runs inside a repo, so the
  path is rarely hit — but the divergence is a latent trap if the helper is ever reused standalone.
- **Fix:** make line 38 match the sibling convention: `ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"` (annotate the swallow per 1.2). Fold into id:b3ca or id:2f15.
- **Action:** (folded into id:2f15 / id:b3ca — no separate id)

---

## Dimension 3 — Spec ↔ implementation drift

### Finding 3.1 (MED) — `cross-mode.md` calls `orphan-scan.sh <path>/TODO.md`; the script expects a *root dir* → silent no-op
- **Evidence:** `cross-mode.md:34` instructs `~/.claude/skills/meeting/orphan-scan.sh <project-path>/TODO.md`.
  But `orphan-scan.sh` takes a **root directory** as `$1` and derives `NOTES_DIR="$ROOT/docs/meeting-notes"`
  (line 39) and the ledger union from `$ROOT/TODO.md` etc. Passing a `…/TODO.md` path makes
  `NOTES_DIR = …/TODO.md/docs/meeting-notes` (nonexistent) and the ledger paths `…/TODO.md/TODO.md`.
  Verified on a fixture: `orphan-scan.sh <fix>/TODO.md` prints **nothing** and exits 0, while
  `orphan-scan.sh <fix>` correctly surfaces the orphan. So the cross-mode forward-orphan surface for
  the top-pick project **silently produces no output** — it always looks clean.
- **Why it matters:** cross-mode's orphan surface (step 6) is dead — a real orphan in the dispatched
  project is never flagged, defeating the past-meetings audit for every `/meeting --cross` dispatch.
  Silent (exit 0, empty), so nothing signals the breakage. Note the very next line
  (`cross-mode.md:35`) calls `orphan-scan.sh --reverse` with *no* path, which then scans the
  *dotclaude-skills* cwd, not the target project — a second half of the same drift.
- **Fix:** change `cross-mode.md:34-35` to pass the project **root**, not its TODO.md:
  `orphan-scan.sh <project-path>` and `orphan-scan.sh --reverse <project-path>`. Add a hermetic test
  asserting `orphan-scan.sh <dir>` and `orphan-scan.sh <dir>/TODO.md` differ (guards the calling
  convention).
- **Action:** `- [ ] [dotclaude-skills] fix cross-mode.md orphan-scan calls: pass project ROOT not <path>/TODO.md (silent no-op); add calling-convention test <!-- id:b767 -->`

### Finding 3.2 (LOW) — SKILL.md end-of-meeting step labels are non-sequential (2c before 2a; 2b/2d/2e scrambled)
- **Evidence:** SKILL.md "End-of-meeting steps" lists, in file order: `1`, `2`, **`2c`**, **`2a`**,
  `2a-replay`, **`2b`**, **`2e`**, **`2d`**, `3`, `4`, `5`. The `2x` sub-steps appear in the order
  2c → 2a → 2b → 2e → 2d, and `2a-replay` (a *setup*-phase action, per its own text "At the START of
  the `/meeting` setup") is documented in the end-of-meeting section. Steps are meant to run in the
  listed textual order, so the labels are cosmetic — but a maintainer reading "do 2a then 2b" gets a
  file where 2c physically precedes 2a.
- **Why it matters:** this is the biggest, most safety-critical section (relay-pool peek-and-warn,
  ledger write-back, deferred-writeback replay). Mis-ordered labels raise the odds a future edit
  wires a step in the wrong place or a reader executes them out of intended order. No functional bug
  today; a maintainability/clarity hazard on a hot path.
- **Fix:** renumber the end-of-meeting sub-steps into monotonic order (or convert to plain 1..N), and
  relocate the `2a-replay` description to the Setup section where it actually fires (leaving a
  one-line pointer at its current spot).
- **Action:** `- [ ] [dotclaude-skills] renumber SKILL.md end-of-meeting sub-steps monotonically; move 2a-replay to Setup <!-- id:4d6c -->`

### `classify.sh` GATED substring false-positive — see Finding 5.n? (No — placed here as it is a classify drift)

### Finding 3.3 (MED) — `classify.sh` GATED detector fires on any word containing the substring "gate"
- **Evidence:** `classify.sh:69` greps the body with `grep -qiE 'gated?|gate:|…'`. The `gate` /
  `gated?` alternative is unanchored, so it matches "gate" *anywhere* — including inside common
  words: **dele**gate, aggre**gate**, navi**gate**, miti**gate**, propa**gate**, **gate**way.
  Verified: a TODO body "investigate the delegate aggregator" classifies as `C2 … GATED` (the item
  is not gated at all). `echo delegate | grep -oiE 'gated?'` → `gate`.
- **Why it matters:** the GATED flag drives a `[GATED]` annotation in the bucket summary that tells
  the user (and the cross-mode judgment step) an item is condition-blocked. A false GATED on ordinary
  vocabulary is noise that erodes trust in the flag and can steer dispatch away from a perfectly
  ready item. The header comment states it is "Advisory only," which caps severity, but the mis-fire
  is silent and frequent (any "delegate/aggregate/navigate" wording trips it).
- **Fix:** anchor the gate vocabulary to word boundaries — e.g. `\bgated?\b` (GNU grep `-E` supports
  `\b`), or require the gate keyword to be a standalone token (`(^|[^a-z])gated?([^a-z]|$)`). Add a
  classify unit test with a "delegate aggregator" fixture asserting no GATED.
- **Action:** `- [ ] [dotclaude-skills] anchor classify.sh GATED regex to word boundaries (delegate/aggregate/navigate false-positive); add fixture test <!-- id:123d -->`

---

## Dimension 4 — Tests

### Finding 4.1 (LOW) — six meeting helpers have no test coverage
- **Evidence:** mapping each helper to `tests/test_*.sh` that references it by name:
  covered — `append.sh`, `broker-curl.sh`, `broker.py`, `classify.sh`, `md-merge.py`,
  `memory-append.sh`, `orphan-scan.sh`; **naked** — `cost-of.sh`, `find-todos.sh`, `gh-audit.sh`,
  `persona-state.py`, `profile-active.sh`, `retrieve-top-k.py`. The covered ones that exist are
  properly hermetic (mktemp fixtures, `trap rm`, mock broker over a `--port-file`, no `~/.claude` or
  network touch — confirmed by reading `test_memory_append.sh`, `test_broker_say.sh`,
  `test_md_merge_commit.sh`, `test_id_ecosystem.sh` headers).
- **Why it matters:** `persona-state.py` (flock'd shard-collapse folding YAML state) and
  `gh-audit.sh` (fail-soft remote parsing + limit capping) both carry non-trivial logic that would
  benefit from a regression net; `cost-of.sh`/`profile-active.sh` are lower-risk read-only advisory
  helpers. `find-todos.sh` and `retrieve-top-k.py` are thin. Prioritise `persona-state.py` (concurrency
  + data-shape) and `gh-audit.sh` (parser).
- **Fix:** add hermetic tests for at least `persona-state.py` (shard→collapse fold, MAX_EVENTS
  truncation, affinity running-sum, missing-yml no-op) and `gh-audit.sh` (no-remote fail-soft,
  limit cap). Others optional.
- **Action:** `- [ ] [dotclaude-skills] add hermetic tests for persona-state.py (shard/collapse fold) + gh-audit.sh (fail-soft parse) <!-- id:fe68 -->`

---

## Dimension 5 — broker.py / broker-curl.sh security + robustness

Positives verified: `broker.py` binds **`127.0.0.1`** only (line 153/165), never `0.0.0.0`;
`broker-curl.sh` hard-validates `PORT` against `^[0-9]{1,5}$` before building the URL (lines 26-29,
guarding a poisoned `broker.json` from relocating the host — a real defensive win); the documented
`jq -n --arg` apostrophe/brace discipline is honoured in the `say`/`event`/`question`/`response`
branches (no raw single-quoted JSON literal), and `test_broker_say.sh` proves apostrophe + quote +
backslash survive round-trip.

### Finding 5.1 (MED) — broker sets `Access-Control-Allow-Origin: *` with no auth on a localhost daemon
- **Evidence:** `broker.py` emits `Access-Control-Allow-Origin: *` on every response (`_ok` line 55,
  OPTIONS line 62, SSE line 122) and has **no** auth/token/Origin check. Any web page open in the
  user's browser can `fetch('http://127.0.0.1:64109/event', {method:'POST', …})` and, because the
  port is a fixed well-known default (64109), inject persona events / questions / responses into a
  live meeting session, or read the SSE stream (classic localhost-CSRF / DNS-rebinding surface).
- **Why it matters:** the broker relays *meeting discussion content* to a renderer. A malicious page
  could spoof a decision `/response` (unblocking `/await` with an attacker-chosen answer) or inject
  discussion text. Low likelihood (requires the user to have both a live broker and a hostile tab
  open) and low stakes (local design-meeting tooling, ephemeral content) — but the `*` CORS +
  fixed-port + no-auth combination is exactly the anti-pattern a security pass flags.
- **Fix:** the minimal, behaviour-preserving hardening is to (a) reflect only a localhost Origin (or
  drop CORS entirely for POST endpoints — the renderer is same-origin via the launcher's
  `web/config.json`), and/or (b) require a per-session token (already have the session id; add a
  launch-time secret the renderer echoes). At minimum, add a `Host`/`Origin` allowlist check
  rejecting non-`127.0.0.1`/`localhost` Origins to close the DNS-rebinding path.
- **Action:** `- [ ] [dotclaude-skills] broker.py: tighten CORS off wildcard + add localhost Origin/token guard (localhost-CSRF/DNS-rebind on POST /event,/response) <!-- id:e32a -->`

### Finding 5.2 (LOW) — broker `sessions` dict grows unbounded; POST body read has no size cap
- **Evidence:** `get_session` (lines 38-42) inserts a new entry per distinct `session` id and nothing
  ever removes a session (no GC on disconnect; `/status`, `/event`, `/await` all create-on-miss). A
  long-lived daemon accreting session ids leaks memory. Separately, `_json_body` (line 48-49) reads
  `int(Content-Length)` bytes with no upper bound, so a large declared body is fully buffered.
- **Why it matters:** both are DoS/leak footguns, heavily mitigated by the idle self-shutdown
  (`MEETING_BROKER_IDLE` default 300s clears the whole process) and localhost-only bind, so real-world
  impact is small. Worth noting for a long-running `systemd --user` always-on deployment (README
  Option B) where idle shutdown is often disabled (`IDLE=0`).
- **Fix:** GC a session when its last subscriber disconnects and no `answer` is pending; cap
  `Content-Length` (reject > e.g. 1 MiB). Low priority given the mitigations.
- **Action:** `- [ ] [dotclaude-skills] broker.py: GC empty sessions + cap POST body size (leak/DoS on always-on IDLE=0 deploy) <!-- id:0e29 -->`

---

## Dimension 6 — Ctx budget: CLEAN (known WARN, no new issue)

`tools/ctx-budget.sh` reports `meeting/SKILL.md` at 8064 tokens (advisory threshold 2000 → WARN),
consistent with `relay/SKILL.md` (11598) and `git-diary-workflow/SKILL.md` (2022). This is a known,
pre-existing advisory WARN, not a regression from this audit. `/meeting` is **not** a
"mandatory-after-every-prompt" skill (unlike `/todo-update` + `git-diary-workflow`), so the
per-prompt ctx-multiplier concern from CLAUDE.md's "Per-prompt ctx multipliers" heuristic does not
apply — SKILL.md loads once per explicit invocation, and setup already defers most bulk (personas,
format, profile filtered to med/high-confidence only) to conditional reads. No new finding; flagged
here only to record that the WARN was reviewed and is acceptable for an on-demand skill.

---

## Dimension 7 — Known-gotcha adherence: CLEAN

- **`${VAR:-default}` permission-prompt class:** SKILL.md (step 7) and broker-mode.md both explicitly
  mandate plain `echo "$MEETING_LIVE"` / `echo "$MEETING_BROKER_PORT"` and warn against
  `${VAR:-…}`. Scripts honour it — no `${VAR:-default}` appears in a *command position* that would
  trip the matcher; the `${1:-…}` root-arg defaults are in assignment context (safe, and the
  established convention).
- **Compound-command ban:** SKILL.md step 2 explicitly instructs "each as a separate Bash call —
  combined calls don't match the allowlist." No `;`/`&&`-chained allowlisted commands are prescribed.
- **Allowlist coverage:** `meeting_ALLOW` (Makefile) covers all directly-invoked helpers
  (`append.sh`, `cost-of.sh`, `find-todos.sh`, `orphan-scan.sh`, `broker-curl.sh`, `profile-active.sh`,
  `persona-state.py`, `retrieve-top-k.py`, `md-merge.py`, `gh-audit.sh`, `classify.sh`,
  `memory-append.sh`). `allowlist.py` emits the 8 entries/script (path×arg forms); `tools/allow-extra.txt`
  correctly carries the one literal the generator can't express (the `broker-curl.sh … status` probe
  with unexpanded `$MEETING_BROKER_PORT`/`$CLAUDE_SESSION_ID`). `broker.py` is intentionally omitted
  from ALLOW (self-started via `run_in_background`, not a per-call allowlisted command) — acceptable.
  No coverage gap found.

---

## Action-item ledger (for routing — not written to TODO.md by this audit)

| id | sev | one-line |
|---|---|---|
| b767 | MED | cross-mode.md orphan-scan passes `<path>/TODO.md` not root → silent no-op |
| 123d | MED | classify.sh GATED regex matches "delegate/aggregate/navigate" substring |
| e32a | MED | broker.py wildcard CORS + no auth on fixed-port localhost daemon |
| b3ca | LOW | cost-of.sh + find-todos.sh missing `set -euo pipefail` |
| 2f15 | LOW | 38 un-annotated swallows in meeting/*.sh (id:4347 pre-enforce debt) |
| 4d6c | LOW | SKILL.md end-of-meeting step labels non-sequential |
| fe68 | LOW | naked helpers: persona-state.py / gh-audit.sh want hermetic tests |
| 0e29 | LOW | broker.py unbounded sessions dict + uncapped POST body |

# 2026-06-22 — Strong-model audit Run 30 (id:401c)

**Started:** 2026-06-22 01:40
**Auditor:** relay HARD-execute child (claude-opus-4-8, id:da26 apex), `/relay --afk` pool
**Window:** `422e95d..HEAD` — first-seen changes since the Run 29 audit merge (`422e95d`).
**Verdict:** **CLEAN** — no code/security defects; one TODO-mirror coherence-drift fixed inline.

## Scope of the window

Unlike Runs 11/12/16–29 (ledger-only), this is a **substantive code window**: ~831 insertions
across 11 code files (4 production, 7 test). First-seen production changes:

| File | Change | id |
|---|---|---|
| `relay/scripts/gather-human-backlog.sh` | `emit_gated_hard` → `emit_hard_lanes`: read EXPLICIT `[HARD — pool\|meeting\|hands]` lane tag, bucket per-lane; untagged HARD = LOUD reject (stderr ERROR + nonzero exit) | 78ff / 415b |
| `relay/scripts/relay-reconcile.sh` | `--all` cross-repo orphan list (own_repos from relay.toml; unreadable repo SURFACED, never swallowed); `--all` + `--integrate/--discard` rejected (exit 2) | 4e14-adjacent |
| `meeting/orphan-scan.sh` | `--promotion` mode (un-promoted executable TODO items) + `xledger-ok` suppression of intentional scope-splits | d9b0 |
| `git-diary-workflow/git-lock-push.sh` | `GIT_TERMINAL_PROMPT=0` + `ssh-add -l` precheck (no key → local commit, retry next tick) + per-push `GIT_SSH_COMMAND` BatchMode/ConnectTimeout | — |
| `tools/check-no-silent-swallow.sh` (new) | deterministic swallow-ban guard (advisory→`--enforce`); `# swallow-ok: <reason>` annotation, empty reason fails | 4347 |

New tests: `test_hard_lane_buckets.sh` (78ff), `test_ledger_seam.sh` (d9b0),
`test_no_silent_swallow.sh` (4347), `test_relay_reconcile_all.sh`; hardened
`test_relay_human.sh` (rewritten for lanes) + `test_relay_claim_liveness.sh` (6b91 TTL fix).

## Pass 1 — Code review (correctness)

**Clean — no inline fix needed.** Items verified:

- **`emit_hard_lanes` awk lane regex** — `[hard[[:space:]]*[—-][[:space:]]*pool[[:space:]]*]`
  etc. Ran the regex against THIS repo's 4 open `[HARD]` items: all classify correctly
  (`[HARD — pool]`→hard_pool, `[HARD — meeting]`/`[HARD — decision gate]`/`route:human`→
  hard_meeting). The `[—-]` char class is a code-point-backwards range (U+2014 `—` >
  U+002D `-`) but gawk treats it as a two-element literal set in practice; output verified
  correct, no defect. `END { if (saw_untagged) exit 3 }` + `scan_repo`'s `|| rc=$?` +
  `UNTAGGED_FOUND` accumulation correctly survives `set -e` and forces the loud nonzero
  exit only after emitting every well-tagged item (verified: bad-repo fixture still emits
  its good item before the reject).
- **`scan_repo` rc plumbing** — `local rc=0; emit_hard_lanes … || rc=$?` then `(( rc == 3 ))`
  vs `(( rc != 0 )) → return rc`. Correct: status 3 = untagged-found (accumulate, continue);
  any other nonzero propagates. No status-code collision (awk only ever exits 0 or 3 here).
- **`relay-reconcile.sh --all`** — `own_repos()` python is a faithful copy of the
  gather-human-backlog parser (classification=own, `# path:` comment recovery, `paused`
  skip, `expandvars/expanduser`). Missing path → `NOTE:` on stderr; non-git path →
  `ERROR:` on stderr — both SURFACED, the exact id:4e14 anti-pattern (silent
  `2>/dev/null` "clean") avoided by design. `--all` + integrate/discard → exit 2 guard
  fires before any single-repo action.
- **`orphan-scan.sh` cross-ledger `xledger-ok`** — `[[ -n "$xok" ]] && todo_xledger_ok[..]=1 || true`
  under `set -e` is safe (the `|| true` catches the empty-`xok` false branch; non-empty
  branch's assignment always succeeds). Suppression keyed by token, applied from EITHER
  ledger side — matches the documented intent.
- **`check-no-silent-swallow.sh`** — `mapfile` per file, previous-line annotation lookback,
  pure-comment-line skip, per-line single-count (`break`), `tests/` path excluded. Advisory
  exits 0; `--enforce` exits 1 only when `total > BASELINE`. Self-consistent (the script
  carries no un-annotated swallow itself).
- **`git-lock-push.sh`** — `ssh-add -l` precheck closes fd 8 and `exit 0` (clean local
  commit, retries next tick — same contract as flock timeout). BatchMode prevents the
  askpass/browser hang the change targets. No regression to the existing flock/clean-tree
  guards (out of window, unchanged).

## Pass 2 — Security audit

**Clean — no injection / path / secrets defect.**

- No external (network/untrusted) input crosses a boundary in the window. `relay.toml`
  is local user config (trusted); `ROADMAP.md`/`TODO.md` are repo files. The awk/grep
  patterns are fixed internal literals — no user data interpolated into a regex or a shell
  word.
- `relay-reconcile.sh --all` git calls all use `git -C "$rpath"` with quoted args; branch
  names come from `for-each-ref` (git-controlled), not user strings. `os.path.expandvars`
  in `own_repos()` expands env in a TRUSTED config path only — same surface as the existing
  gather-human-backlog parser (id:c8db-class, already-accepted).
- `check-no-silent-swallow.sh` reads file contents into an array and greps them with FIXED
  patterns; filenames come from `find … -print0` (null-delimited, space-safe). No `eval`,
  no command interpolation of file content.
- No secrets, tokens, or credentials introduced. `git-lock-push.sh` HARDENS the auth path
  (BatchMode refuses interactive credential entry) — a security improvement, not a risk.

## Pass 3 — Design coherence

**Coherent.** Checks performed on decisions added since Run 29:

- **id:78ff explicit-lane contract** is internally consistent across its four surfaces:
  `relay/references/hard-lanes.md` (the canonical marker set), `gather-human-backlog.sh`
  (the bash consumer), `relay/references/human.md` (the three distinct dispositions:
  pool→FYI, meeting→/meeting, hands→you-run), and `tests/test_hard_lane_buckets.sh`
  (cross-checks the doc's marker set against the collector). The test asserts the doc
  defines each marker — so a future drift between doc and parser fails the suite. Sound.
- **Legacy `[HARD — strong model]` now LOUD-rejects.** The contract treats the most-common
  legacy bare tag as `untagged`. Verified THIS repo has NO open `[HARD — strong model]`
  items that would break the collector (all 4 open HARD items carry a recognized lane;
  the id:78ff done-note already back-filled them). The **residual** cross-repo back-fill of
  OTHER own repos' bare tags is correctly scoped OUT of this worktree (a relay child works
  one repo) and is self-surfacing (the collector LOUD-rejects any un-back-filled tag) — no
  silent gap. Tracked in the id:401c done-note's "Residual" paragraph; no new item needed.
- **`route:human` → bucket `meeting` (not `hands`).** Observed: the auto-gate (id:3801)
  alias `route:human` maps to the *meeting* bucket, while `[HARD — hands]` is the distinct
  "you run these" lane. For dba3 (tagged `route:human`, genuinely needs `useradd`/sudo —
  a hands disposition) this means it surfaces to `/meeting` rather than `hands`.
  **Explicitly ACCEPTED, not a contradiction:** `route:human` is documented in
  hard-lanes.md (line 60) as a *human-must-route* signal, and the meeting lane IS where a
  human reads + routes it (human.md tier-(a/b/c) downgrades when unsure). The auto-gate
  emits a coarse "a human decides" route; the fine pool/meeting/hands disposition is a
  human's hand-tag job. Conflating route:human→hands would mis-imply the machine knows the
  work is hands-only. Acceptable as designed.
- **id:4347 swallow-ban ships ADVISORY**, consistent with the meeting note's
  "observe/size-before-gate". Ran it on the live corpus: 51 scripts, 231 un-annotated
  swallows (180 `2>/dev/null`, 51 `|| true`) — exactly why the gate is advisory-first, not
  enforcing. The `--enforce` flip path is documented and matches the meeting D2.
- **id:d9b0 seam tooling** (`--promotion`, `xledger-ok`) coheres with the single-id-two-views
  invariant (TODO=why / ROADMAP=now): promotion-detection catches the id:78ff class
  (filed TODO-only, pool-invisible until promoted), and `xledger-ok` lets an intentional
  scope-split coexist without a false cross-ledger flag. Both tested (`test_ledger_seam.sh`).
- **Cross-ledger state coherent.** 0 open ROUTINE; 4 open `[HARD]` lines — 3 executable
  (dba3 decision-gated, 401c pool, 3346 meeting) + de4e DEFERRED (non-executable design
  entry). d5e0 summary agrees (Run 17's drift fix holds). All three executable HARD ids
  open in BOTH ROADMAP and TODO.

## Inline fix made this run

- **TODO id:401c MIRROR-line drift** (Run 4/8/17/21–29 recurring class) — the TODO.md
  mirror line still read "Latest ✓ Run 29"; refreshed to Run 30 with this window's verdict.
  (The d5e0 summary itself was NOT stale this run; only the 401c mirror needed the refresh.)

## Test suite

`tests/run-tests.sh`: **80 passed, 0 failed, 0 expected-red.** Both pre-existing tracked
flakes (id:16e9 `test_relay_claim_liveness.sh`, id:05e8 `test_git_lock_push_slash_branch.sh`)
did NOT recur — note the id:6b91 fix (CLAIM_TTL 1→3600) directly hardens the id:16e9 class.

## No new follow-on items

Every finding is fixed inline (the mirror drift), explicitly accepted with rationale (the
`route:human`→meeting bucketing; the awk `[—-]` range; the cross-repo back-fill residual),
or already-tracked. No finding silently dropped.

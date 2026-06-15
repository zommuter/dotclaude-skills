> **Provenance (re-landed 2026-06-15 by reviewer).** This audit was produced by a relay
> HARD-execute child (id:401c) in worktree `relay/relay-20260615-145245-27422-hard`, but that
> child branched from a STALE base: its commit also deleted `tests/test_relay_resolution_inject.sh`
> and rewrote ROADMAP/TODO, so the commit was discarded rather than merged. The audit *content*
> below is intact and was salvaged verbatim. The one actionable finding (F1/F2) is re-filed as
> ROADMAP **id:c8db**. id:401c stays open (recurring audit; next run diffs against this checkpoint).

# 2026-06-15 — strong-model audit: code review, security, design coherence

**Started:** 2026-06-15 15:20
**Session:** relay HARD-execute child (worktree relay/relay-20260615-145245-27422-hard), Opus-apex
**Mode:** Class 2 audit record (ROADMAP id:401c, second run — three-pass solo audit, no meeting held)
**Topic:** Adversarial review of the relay-skill rebuild and autonomous-pool hardening landed
since the first audit (`fable-ckpt-20260612-1827`). Correctness, security, design coherence.

## Context

ROADMAP id:401c specifies a recurring strong-model audit after each significant executor /
design batch. First run (2026-06-12-1811) covered `fable-ckpt-20260612-1328`..HEAD. This
second run's *nominal* window is `fable-ckpt-20260612-1827`..HEAD — 156 commits, 90 files,
~7400 insertions — far too large to audit exhaustively and safely in one bounded turn. Per
handoff-C5 "only if small enough to finish safely" discipline, the pass was **scoped to the
highest-risk NEW surface** rather than every line: the entire `relay/` skill (the
`fables-turn`→`relay` rename brought in 9 new shell scripts plus the autonomous pool engine),
which is where the security/correctness exposure concentrates (shell quoting, `jq`/`awk`
interpolation, `git`/`ssh` operations, force-push, cross-session race conditions, and the
apex-only HARD dispatch gate). Docs-only churn (ROADMAP/TODO/RELAY_LOG/meeting-notes) and the
already-audited 06-12 artifacts were not re-read.

**Surface audited (read in full):** `relay/scripts/claim.sh`, `force-push.sh`, `quota-stop.sh`,
`inject.sh`, `sync-origin.sh`, `probe-fable.sh`, `relay-state-write.sh`; the dispatch /
model-assignment / verdict-gate sections of `relay/scripts/relay-loop.js`.

Every finding below is fixed inline, tracked with a token, or explicitly accepted with
rationale. No finding is silently dropped.

## Pass 1 — Code review (correctness)

- **F1 (ACCEPTED — controlled input)** `relay-state-write.sh toml-set` interpolates `value`
  into the awk program via `-v val="$value"` and re-emits it with `print key " = " val`. awk's
  `-v` assignment processes C-style backslash escapes, so a value containing a backslash (`\t`,
  `\\`) would be silently mangled before it ever reaches the file. In practice every caller
  (relay-loop.js integrate step 6) passes only checkpoint tag strings, ISO dates, and bare
  tokens (`false`, `"active"`, `"handed-off"`) — none contain a backslash — so today the write
  is faithful. **Tracked for hardening** (not urgent) as the value-quoting robustness item
  below so a future caller passing an arbitrary string can't be corrupted. <!-- finding F1 -->

- **F2 (ACCEPTED — controlled input)** Same script: `key` is spliced into an awk *regex*
  (`kre="^" key "[ \t]*="`). A key containing regex metacharacters (`.`, `[`, `*`) would
  match the wrong line or fail to match, replacing/adding the wrong field. All keys are fixed
  TOML identifiers minted by relay-loop.js (`last_ckpt`, `last_review`, `status`,
  `handoff_date`, `last_strong_ckpt`, `fable_rechecked`) — none carry metacharacters. Folded
  into the same hardening item (anchor key matching to a literal compare).

- **F3 (ACCEPTED — minor, no action)** `claim.sh`, `inject.sh`, and `claim.sh reap`/`peek`
  iterate shards with `for f in $(printf '%s\n' "$DIR"/*.json | sort)`, which word-splits on
  IFS — a shard filename containing whitespace would break iteration. Filenames are derived
  from `safekey()` (repo/item/`resource:` keys → `/` and `:` → `_`) and from inject tokens
  (`inj-<date>-<pid>-<rand>`); none can contain a space. The `sort` is purely for
  deterministic FIFO display order. Real risk ≈ 0; flagged for awareness only — if shard keys
  ever admit spaces, switch to a `while read` over a NUL-delimited `find -print0`.

- **F4 (verified, no action)** `claim.sh` re-entrancy: a FRESH shard held by the SAME runId is
  re-acquirable (heartbeat refresh) while a DIFFERENT runId is refused (exit 1, holder JSON to
  stderr). The `[ -z "$run" ]` branch means an acquire with no `--run` is *always* refused
  against any fresh foreign claim — correct (an anonymous acquirer can never steal). Release is
  symmetrically run-scoped (no `--run` ⇒ force-release for admin cleanup). Logic is sound.

- **F5 (verified, no action)** `sync-origin.sh` divergence math: `git rev-list --left-right
  --count "HEAD...$upstream"` emits `<ahead>\t<behind>`; `${counts%%[[:space:]]*}` /
  `${counts##*[[:space:]]}` correctly split on the single tab. The four-way decision
  (diverged→exit 3, behind+--ff+clean→ff-merge, behind→exit 2, else ok) matches the documented
  contract and the ai-codebench incident it was built to prevent. A failed `ff-only` merge
  correctly falls through to `behind` (exit 2) rather than claiming success.

- **F6 (verified, no action)** `quota-stop.sh` stale-cache self-refresh is flock-guarded
  (fd 8, `-w 10`) with a double-check (`M2` mtime > 60s) so concurrent quota gates don't
  stampede the `/api/oauth/usage` ~5-req limit; on any refresh failure it stays conservative
  and stops (exit 2). The percent-vs-fraction scale conversion (`v >= t*100`) is correct and
  documented. The decay-threshold interpolation clamps `d` to [0,1] and falls back to the flat
  threshold on an unparseable `resets_at`.

## Pass 2 — Security audit

- **S1 (ACCEPTED — trusted input, by design)** `force-push.sh` builds a remote command
  `ssh "$host" "git -C '$bare_path' config receive.denyNonFastForwards false"` with
  `bare_path` single-quoted inside a double-quoted string. A `bare_path` containing a single
  quote would break out of the quoting. But `bare_path` is derived from the repo's OWN
  configured push URL (`git remote get-url --push`), i.e. operator-controlled local git config,
  not external/network input — and the whole script is gated behind `FORCE_PUSH_CONFIRM=1`
  (refused with exit 2 for any unattended/relay caller before it touches anything). The
  threat model (accidental/automated force-push) is fully addressed; an attacker who can write
  your git remote URL already has local code execution. Accepted; no change.

- **S2 (verified, strong design)** `force-push.sh` `--force-with-lease` (never bare `--force`),
  per-repo guard lift (never `--global`), and an EXIT trap that re-arms
  `receive.denyNonFastForwards=true` whether the push succeeds, fails, or is interrupted — with
  a printed manual re-arm command if the re-arm SSH itself fails. The guard cannot be left down
  by a crash. This is the correct shape for a "deliberate-human-only" escape hatch.

- **S3 (verified, no action)** `relay-state-write.sh status-write` requires an absolute path
  (`case "$target" in /*) ;; *) reject`), preventing a `~`/`$HOME`/`${...}`-literal target
  (id:c34a). `toml-set` aborts (exit 1, no clobber) if the file or `[repos.<repo>]` block is
  missing, so it can never *create* a malformed relay.toml. Both writes are temp-file+`mv`
  atomic under one flock — no torn writes across concurrent relay runs.

- **S4 (verified, no action)** All JSON construction across `claim.sh`, `inject.sh`,
  `probe-fable.sh` uses `jq -n --arg` / `python3 json.dump` — never shell string interpolation
  — so a repo name, item id, or free-form `--prompt` containing quotes/braces/newlines cannot
  break out of the JSON or inject fields. This matches the CLAUDE.md "broker-curl.sh JSON"
  gotcha discipline. `inject.sh` validates `--verdict` against the
  `execute|review|hard|handoff` enum before writing.

- **S5 (verified, no action)** `quota-stop.sh` reads the OAuth bearer token from
  `~/.claude/.credentials.json` via `jq -r`, passes it only as an `Authorization:` header to
  the hard-coded `api.anthropic.com` host over HTTPS, and writes the response to a tmp file it
  `mv`s into place. The token is never echoed, logged, or placed on a command line visible to
  other users' `ps` beyond the unavoidable curl arg (same exposure as the statusline already
  has). No secret leak introduced.

## Pass 3 — Design coherence

- **D1 (verified — the headline invariant holds)** The id:da26 concern that gave this whole
  HARD-verdict its "Why HARD" — *HARD work must never leak onto the Sonnet execute tier* — is
  airtight in code. Two independent gates enforce it: (a) the **dispatch gate** (relay-loop.js
  ~L463) pulls every `hard` unit out of `actionable` and into `hardDeferred` unless
  `STRONG_MODEL === 'claude-opus-4-8'`, logging the deferral; (b) the **model-assignment**
  (runUnit ~L751) pins `execute → 'sonnet'` and everything else → `STRONG_MODEL`, which for a
  surviving `hard` unit is provably `claude-opus-4-8`. There is no path by which a `hard` unit
  reaches a Sonnet agent. `PRIORITY = {execute:0, review:1, hard:2, handoff:3}` correctly ranks
  hard after the anti-gaming review window but before fresh handoff.

- **D2 (verified — self-consistent dispatch contract)** The unitPrompt template (L591+) issued
  to every child — lease-acquire-FIRST (id:ebfb), worktree-exclusive, verdict-specific
  procedure, the exact C5 "size-it-first / don't-half-do-it" HARD discipline — matches this
  audit child's own received prompt verbatim. The cross-session lease invariant is applied
  uniformly across execute/review/hard/handoff, and the supervisor (not the child) releases it
  at integration. No verdict class is exempt; no double-claim path.

- **D3 (verified — the two strong-tier axes compose cleanly)** `STRONG_TIER` (which strong
  model: opus|fable) and `--fable-down`/`-d` (is the Fable tier reachable) are orthogonal and
  their four-way composition is fully covered: `-d` alone (STRONG_MODEL=fable) → defer strong
  work, demote review-with-routine to execute, keep the Sonnet pool busy; `-d + STRONG_TIER=opus`
  → substitute Opus, dispatch review/handoff NORMALLY marked `fable-standin`, defer nothing.
  The fable-down demote block (L499) is correctly gated on `STRONG_MODEL === 'claude-fable-5'`
  so it is SKIPPED entirely under the Opus-substitute path. `-d` undefined-coercion footgun is
  guarded (comment L14). No contradiction with the HARD gate: a `hard` unit needs apex Opus,
  which the Opus-substitute path provides and the pure-fable-down path correctly withholds.

- **D4 (verified — classifier precedence is consistent end-to-end)** The discovery prompt
  (L372+), the verdict enum (L206), and the precedence string (L380, `review > execute >
  hard > handoff > idle`) agree. `hard` requires *no unaudited commits AND no open [ROUTINE]
  AND ≥1 open [HARD]* — the ROUTINE-drained steady state — which is exactly the gap (~46 HARD
  items would otherwise stall) the verdict was minted to close. `hasRoutine`/`openHard` are
  computed INDEPENDENT of the chosen verdict, which is what lets the fable-down path keep
  executors busy on routine work in a repo whose review must wait. No gate that can never fire.

- **D5 (verified — id:e030 masking fix is coherent)** The `last_strong_ckpt` /
  `strong_model` / `fable_rechecked` triple in relay.toml SURVIVES a later executor checkpoint
  (an executor's integrate must not clear them), so the optional Fable-recheck signal stays
  visible after a Sonnet checkpoint overwrites `last_ckpt`. This is consistent with the
  "Opus decisions are final; Fable recheck is a non-gating free second opinion" stance — a
  repo with non-empty `last_strong_ckpt` + `fable_rechecked=false` is surfaced, never blocks.

### Sizing note (why this run is bounded, not a half-audit)

The full 156-commit window cannot be adversarially audited line-by-line in one safe turn. The
honest, in-budget deliverable is a *complete* audit of the *highest-risk new surface* (the
relay scripts + dispatch gate) — done here — plus an explicit statement of what was NOT
re-read: the 06-12 artifacts already covered by the first audit, and pure docs/ledger churn.
A future audit run should diff against this checkpoint and, if a large code batch lands,
consider splitting the window or running the audit more frequently so it stays bounded.

## Outcome

No critical or high-severity finding. The relay-skill rebuild is correct and internally
coherent; the security-sensitive operations (force-push, token handling, shared-state writes,
JSON construction) follow safe patterns. Two low-severity input-robustness findings (F1, F2)
in `relay-state-write.sh` are tracked as one hardening ROADMAP item (id:c8db). The
word-splitting and SSH-quoting items (F3, S1) are explicitly accepted as controlled-input,
zero-real-risk today, documented here so a future change that widens their input domain has
the prior reasoning on record. id:401c remains an open recurring item (next run diffs against
this checkpoint).

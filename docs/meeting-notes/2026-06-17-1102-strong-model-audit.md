# Strong-model audit — Run 13 (2026-06-17-1102)

Recurring audit item id:401c. Window: **first-seen code since Run 10/12** (last audit note
`2026-06-16-1247`) up to HEAD. (Run numbering: the existing log already had Run 11/12 with
out-of-chronological timestamps; this run is the chronologically-latest, numbered Run 13.) relay-loop.js was
audited as a diff only (`relay-ckpt-20260616-2241..HEAD`, ~52 insertions — the discovery-cache
integration). Suite 3/3 on the audited test files at arrival.

Window contents (5 files):
1. `relay/scripts/discover-sig.sh` (88 lines — content-addressed discovery signature, id:c3a6)
2. `relay/scripts/relay-loop.js` (diff only — discovery-cache integration, id:c3a6)
3. `tools/model-probe.sh` (241 lines — standing model-quality probe, id:dba3/c345)
4. `tools/settings-env.py` (90 lines — settings.json env-block applier, install-relay-env)
5. `tools/model-probe.battery.jsonl` (data — JSONL validity / secrets sanity check)

Covering tests skimmed: `tests/test_discover_sig.sh`, `tests/test_discover_cache.sh`,
`tests/test_model_probe.sh` — all green at arrival.

## Pass 1 — Code review (correctness, error handling, quoting, races, edge cases)

**1.1 Clean — `discover-sig.sh` set-e / pipefail discipline.** `repo_sig` declares all
locals on one bare `local` line (52) then assigns separately with `|| true` guards, so no
`local x=$(...)` exit-code masking. Every `git`/`ls`/`cat` capture has `2>/dev/null || true`,
so a transient git error degrades to an empty section (over-invalidation) rather than killing
the script under `set -e`. The final hashing pipeline `{...} | sha256sum | cut | tr` is the
function's return value; none of its stages realistically fail. Labeled NUL-free section
headers (`== head ==` …) prevent cross-field collision. FAIL-OPEN gate (47–51) returns the
empty sentinel and exits 0 on a non-repo path — verified by test (3).

**1.2 Clean — `discover-sig.sh` main loop.** `n` defaults to 0 via `|| echo 0` if jq fails on
malformed stdin; the `while [[ "$i" -lt "$n" ]]` loop then runs zero times and emits nothing
(caller re-classifies everything — fail-open). Malformed/missing `.repos[i].repo` yields the
jq string `"null"`, which still produces a deterministic (wrong-but-harmless) sig or fail-opens
on the bad path. No unquoted expansions in command position.

**1.3 Clean — relay-loop.js cache partition (diff).** The changed-vs-cached split (553–561)
is correct: a repo reuses its cached unit ONLY when `sig && cached && cached.sig === sig &&
cached.unit` — an empty sentinel sig (`''`) is falsy so it always re-classifies; a repo absent
from the cache (`cached` undefined) re-classifies. `SHARDS = Math.max(1, Math.min(DISCOVER_SHARDS,
changed.length || 1))` plus the empty-chunk `.filter(c => c.length)` means a fully-cached round
spawns ZERO shards (`changed.length` falsy → `shardResults = []`), and `shardOk` is seeded
`true` for that case so the round is still valid. Fresh units are cached keyed by the round's sig
BEFORE the reused units are folded in (654–655), so reused units are not re-written. Shape is
preserved (`units`/`surfaced`/`skipped`, `runId: prelude.runId` downstream).

**1.4 Clean — `model-probe.sh` grade / set-e.** `grade`: `echo … | grep -qP "$regex" && exit 0;
exit 1` — the `&&`-guarded `exit 0` is exempt from set-e abort, so a non-match falls through to
`exit 1` correctly (verified by test 1). `battery-version` heredoc parses the meta line and
exits non-zero with a message when absent. The run path delegates to Python via `exec`, so the
bash layer's exit code is Python's.

**1.5 TRACK (LOW, forward-robustness) — `model-probe.sh grade` echo-flag swallowing.** `echo
"$output"` will treat an output that begins with `-n`/`-e`/`-E` as an echo flag rather than
literal text, and `printf`-style backslashes are not expanded by `echo` consistently across
shells. For the offline `grade` subcommand fed arbitrary model output this could (very rarely)
mis-grade an item whose response starts with `-n`. Zero impact today (battery golden outputs are
numbers/words), but `printf '%s\n' "$output"` would be robust. NOT fixed inline: it is a
behaviour-adjacent change to a graded path and I would rather it be a tracked, tested change than
a silent audit edit. Severity LOW.

## Pass 2 — Security (injection, unvalidated boundaries, secrets, permissions)

**2.1 Clean — no injection seams in `discover-sig.sh`.** `repo`/`path` from jq are passed to git
as quoted positional args (`git -C "$path" …`), never eval'd or interpolated into a shell string.
`toml_block` passes `name` through `awk -v want="[repos.$name]"` — awk `-v` does process C-style
backslash escapes (the id:c8db F1 class), but the value is a repo name from controlled relay.toml
config and only ever drives an exact-string `==` match for log/hash content, never a destructive
op. Same zero-today / forward-robustness posture as id:c8db — noted, not filed. `RELAY_TOML` /
`RELAY_WORKTREE_BASE` are test-only overrides; in production they default to fixed `$HOME` paths.

**2.2 Clean — `model-probe.sh` secrets.** The log schema deliberately records `model_id_str`,
`fingerprint` (= `session_id`), `cli_version`, `quota_tier`, `os_user`, `config_hash` — no API
key, no prompt/response text is logged (only PASS/FAIL + token counts). Shape B (API-key path) is
commented out. `config_hash` is a hash, not the config. The log goes to `~/.claude/logs/` (D2
schema), not committed. `golden_regex` is fed to Python `re.search` wrapped in `try/except
re.error` (214) → no crash on a bad battery regex. `grep -qP "$regex"` in the bash `grade` arm is
local/offline; ReDoS is the operator's own input — accepted.

**2.3 Clean — `model-probe.sh` privilege use.** The Shape-A invocation `sudo -u claude-probe env
HOME=… claude -p "$prompt"` runs the model as a dedicated unprivileged probe user with an empty
HOME — this is the documented D1/id:d0c0 design, and the empty-config assertion (82–91) refuses to
run if that HOME has Claude config. `prompt` comes from the versioned battery file (trusted), passed
as a single argv element to `subprocess.run` (list form, no shell) — no command injection. Accepted
as designed.

**2.4 Clean — `settings-env.py` write safety.** Atomic write via `mkstemp` in the target dir +
`os.replace`, with `os.unlink(tmp)` on failure — no partial/truncated settings.json. Backup to
`.json.bak` before overwrite. Writes into `~/.claude/` only the `--settings` path the caller passes
(Makefile passes the real settings.json). No secrets; values are env-policy strings.

**2.5 Clean — battery JSONL.** 16 valid JSONL lines (1 meta + 15 items), parsed without error. No
tokens, keys, paths, or PII — only arithmetic/string prompts and golden regexes.

## Pass 3 — Design coherence (superset signature, probe design, merge semantics)

**3.1 discover-sig.sh DOES hash a superset of the shard's inputs — with two tracked gaps.**
Cross-checked every input the discovery shard reads (relay-loop.js 567–620) against the hashed
sections:
  - HEAD / unaudited-commit detection → `head` + `tags` (review verdict). ✓
  - checkpoint tag list + latest-tag `fable-standin` message (standin) → `tags` + `tagmsg`. ✓
  - ROADMAP.md (hasRoutine / openHard / EXECUTABLE-HARD gate / handoff marker) → `roadmap`. ✓
  - dirty tree + acceptable-dirty relay.toml comments (surfaced) → `porcelain` + `toml`. ✓
  - relay.toml block: income / intensive / path / handoff_date / last_strong_ckpt /
    fable_rechecked (strongRecheckPending, id:e030) → `toml`. ✓
  - stale/claimed-elsewhere worktree dirs → `worktrees`. ✓
  - parked orphan refs (suppress-redispatch id:1f53) → `orphans`. ✓
  - global live-claim membership → `inlive`. ✓
  Tests (2a–2i in test_discover_sig.sh) independently prove each of these 9 inputs moves the sig.

  **3.1a TRACK (LOW, under-invalidation — the only hazard class) — origin-behind state is not
  in the signature.** The shard's SYNC-WITH-ORIGIN guard (id:c3f7, relay-loop.js 589–594) runs
  `git fetch origin` and then classifies on the post-fetch ahead/behind, fast-forwarding a clean
  behind-only repo. The signature's `upstream` field (line 59) reads `HEAD...@{upstream}` WITHOUT
  fetching, so it reflects the LAST-FETCHED upstream ref. If origin advances between rounds while
  the local `@{upstream}` ref is untouched, the sig is byte-identical → the cached verdict is
  reused → no fetch, no fast-forward, the new origin commits are not seen until something else
  (a local commit, ROADMAP edit, tag) moves the sig. This is true under-invalidation, but bounded:
  it only delays *picking up origin-side* work within a single pool run, the data is inherently
  racy (any fetch is a point-in-time snapshot), and the very next sig-moving event re-syncs. Fix
  would be to fold a `git fetch` (or a remote-tracking `ls-remote` of the upstream branch) into
  discover-sig.sh — a behaviour + cost change (adds network to every sig), so it must be a tracked,
  measured decision, not an inline edit. Severity LOW. Per the CLAUDE.md gotcha this is exactly the
  "add a NEW signal to the shard prompt → add it to discover-sig.sh" hazard, here pre-existing in
  the shard.

  **3.1b ACCEPT — `git log <tag>..HEAD` content is not separately hashed, but HEAD+tags cover it.**
  The review verdict reads the commit list between the latest checkpoint tag and HEAD. The sig hashes
  HEAD and the full tag list; any change to that range necessarily changes HEAD or the tag set, so the
  derived signal cannot go stale without a sig change. Coherent — no gap.

**3.2 model-probe.sh "cold per-item, versioned battery, 3-tier" is coherent.** The battery meta
line carries `version` (required; run aborts if absent, 131–133) and propagates into every log
line — versioned ✓. The 3 tiers (opus/sonnet/haiku) are a single `MODEL` arg, default opus ✓.
"Cold per-item": each item is a fresh `claude -p` subprocess with an empty-HOME probe user, so
there is no cross-item conversation state — the design intent holds. One internal-consistency note,
**3.2a ACCEPT**: in real (non-mock) mode the per-item `claude -p` carries no `--model` flag — the
tier is selected by the probe user's environment/subscription, not by the `MODEL` argv. The `model`
field in the log is therefore the operator's *label*, reconciled against the observed `model_id_str`
from the init event. This matches the D6 "frontend metadata" design (observe the served model, don't
assert it) and id:dba3's "investigation expected inconclusive" framing — accepted as designed, not a
defect.

**3.3 settings-env.py merge semantics are idempotent and non-clobbering.** It `setdefault("env",
{})` then writes ONLY the keys whose value differs (`changes`), via `env.update(changes)` — unrelated
`env` keys and all other top-level settings keys are preserved (the whole `data` dict is re-dumped).
`--mode print` is read-only. Idempotent: a no-change run prints "nothing to set" and does not touch
the file (no spurious backup churn). Matches allowlist.py's documented write style (indent=4, trailing
newline, .bak backup, atomic replace). No gate that can never fire; no contract contradiction.

**3.4 No internal contradictions across the new code.** The cache's "over-invalidation safe /
under-invalidation hazard" framing in relay-loop.js comments matches discover-sig.sh's header and the
CLAUDE.md gotcha verbatim. Surfaced/idle-without-unit repos are deliberately NOT cached (re-classify
each round) — consistent with the comment and safe. Injected units are never cached (consumed each
round) — consistent with inject.sh's take semantics.

## Outcome

Zero inline fixes (the audited code is clean to a high bar). Two findings to TRACK, both LOW and
explicitly in the "zero-today / forward-robustness" or "bounded under-invalidation" class — neither
is fixed inline because both are behaviour/cost changes that warrant a tested, measured item rather
than a silent audit edit:
  - **1.5** `model-probe.sh grade` uses `echo "$output"` (flag/escape swallowing) — LOW.
  - **3.1a** discover-sig.sh `upstream` field does not fetch, so origin-behind advances within a
    pool run can be under-invalidated until the next sig-moving event — LOW.
Three findings explicitly ACCEPTED with rationale (2.1 awk-`-v` id:c8db class; 3.1b log-range covered
by HEAD+tags; 3.2a no `--model` flag is the D6 observe-don't-assert design). No correctness, security,
or coherence DEFECT left open. Audited test files 3/3 green.

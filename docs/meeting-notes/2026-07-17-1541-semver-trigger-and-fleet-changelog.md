# 2026-07-17 — The semver trigger and the fleet CHANGELOG (e647 + b8fa)

**Started:** 2026-07-17 15:41
**Session:** 4b11c740-39f0-4db9-aef8-20562124bb79
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 🛰️ Hank (config-management — cache-vs-derivation topology), 🎛️ Orla (multi-agent orchestration — integrate-time collision)
**Topic:** When does a repo bump (`id:e647`), and is a fleet CHANGELOG derived or authored (`id:b8fa`) — which `b8fa` requires be decided together.

**Mode note:** run in **auto mode, no plan mode**, at the user's direction — this session was holding background relay executors, and plan mode's read-only guard would have blocked integrating their branches. That interaction is the new cost recorded in `id:fc0f`.

## Context

- `id:e647` — inbound `routed:38db` from truncocraft (2026-06-29). The global CLAUDE.md defines **how** to bump but never **when**, so repos sit at 0.1.0 indefinitely. Deliberately parked in observe-before-preventing mode.
- `id:b8fa` — from the user 2026-07-16: a `CHANGELOG.md` across the fleet, "especially for the semver repos but in general", "bucketed by sensible time ranges (e.g. daily)". It states: **"Decide e647 and this together."**
- **The observation window has closed with data.** The 2026-07-16 session found loderite 5 user-observable closes past v0.40.0, zkm 3 past v0.18.0, chidiai 12 past v0.1.0 — all shipped unversioned. The owner ruled "bump now, one per close" → loderite v0.45.0, chidiai v0.13.0, zkm v0.21.0.
- **Fleet scale — cited, not re-derived.** `b8fa` records 25 own repos carrying `v*` tags, verified 2026-07-16. A re-count attempted this session hit tooling friction (`own_repos` resolved 48 registry entries but only 24 to on-disk repos) and produced a partial figure: **15 of 24 resolvable own repos carry `v*` tags, 9 carry none**. The item's figure stands as its own verified claim; the partial count is recorded as partial. *(A first attempt used a `~/src/*` glob — which this repo's own rules ban, since it includes vendored clones like manim/whisper.cpp and misses the zkm plugins. `relay.toml` via `lib-own-repos.sh` is the canonical set.)*

## Discussion

### Items 1 & 2 — the trigger, and derive-vs-author

🏗️ **Archie:** These are one mechanism. `e647` already settled the hard part: the bump is the reviewer's job at integrate, never the executor's in a worktree, because parallel worktrees collide on the manifest and lockfile. `b8fa` observes a changelog entry has the **identical** collision profile. Same hook, or they fight.

🛰️ **Hank:** Ask my question first: *who decides the value, who stores it?* A version is a **decision** — "this close is user-observable, therefore minor". A changelog entry is a **cache of a derivation** — the relay already knows every close (`workedIds`, `relay-ckpt-*` tag messages, `RELAY_LOG.md`). Derive the changelog, decide the version. The thing to forbid is a hand-edited cache, not the cache.

😈 **Riku:** Too clean. "User-observable" is exactly what a deriver can't judge. `e647`'s own evidence: loderite had **5 user-observable** closes past v0.40.0 — someone looked and said "these are user-facing, that one's a refactor". Derive the bump from "a box got ticked" and every internal cleanup bumps; the number stops meaning anything.

🛰️ **Hank:** I'd take that trade — a meaningless-but-present number beats an absent one.

😈 **Riku:** You can't, and here's why: **the drift is measured, so we're not guessing.** The owner applied judgement per close on 2026-07-16. That ruling is the evidence *against* full derivation.

✂️ **Petra:** You're both designing the deriver before naming the trigger. `e647` says the global rule defines how but never when. Name the when.

🏗️ **Archie:** At integrate, per closed ROADMAP item, if the close is user-observable. The reviewer is already there — already re-deriving the roadmap, already re-running tests. It's the only actor with the context to judge *and* the authority to commit to main.

🎛️ **Orla:** And the only one that can do it safely. This very session: two executors landed in parallel and their ROADMAP ticks auto-merged, because they were **disjoint lines**. A version bump is not a disjoint line — one field, one manifest, plus a lockfile. Two executors bumping = guaranteed conflict, and `routed:c3a3` proved today octopus can't rescue a shared-file collision. Integrate-time is single-threaded by construction.

😈 **Riku:** Name the failure you're buying. The bump commit must leave the tree clean or `clean-tree-gate.sh` **defers the whole repo** — so a botched bump doesn't mis-version, it stalls the repo's next pool run. And `bump-includes-lockfile` means regenerating `uv.lock` at integrate, in the expensive tier.

✂️ **Petra:** N=2 on the deriver: (1) semver repos at integrate, (2) `claude-diary` as cross-repo narrative. Passes — but only if the source is genuinely already-there. A new "user-facing?" flag on every ROADMAP item is authoring with extra steps, not derivation.

😈 **Riku:** And the retroactivity trap: per-close tags are **unrecoverable after the fact** (`e647` records this from the 2026-07-16 batch). Retroactive generation produces a plausible, unverifiable narrative — a fabricated record.

🏗️ **Archie:** Then start from now. A changelog that begins today and is true beats one that reaches back and is fiction.

**Tobias:** Ratified D1 "Global default: reviewer bumps at integrate, per user-observable close" and D2 "Derived at integrate, from existing relay state, starting from now".

### Items 3 & 4 — home, scope, sequencing

😈 **Riku:** Start with the exemption — it can't be fudged. `b8fa` **reopens a ratified decision and says so**: "Do not silently override 8ef3." `id:8ef3` (2026-07-12) ruled this repo has no version by design and deferred a CHANGELOG until a first external consumer. No such consumer exists.

✂️ **Petra:** And the ask named "especially for the semver repos". This repo has no manifest, no `v*` tags — its 260+ tags are all `relay-ckpt-*`. Weakest candidate in the fleet.

🏗️ **Archie:** The exemption is free by construction: if the trigger is "the reviewer bumps the manifest", a repo with no manifest is exempt with no special case to write.

😈 **Riku:** Cleanest available — but name the cost. This repo then has no human-readable record of what changed, and it's the repo whose changes break *other* repos' sessions. Today: a stale install broke loderite's lint. **A changelog wouldn't have caught that — `make install` would.** So I'm not arguing to overturn `8ef3`; I'm arguing nobody may later cite this exemption as evidence the repo needs no release discipline.

🛰️ **Hank:** On *where* — don't put a CHANGELOG in 25 repos because 25 have tags. Separate decides from stores. The decision is per-repo; the narrative already exists in `claude-diary`. A per-repo file is warranted only where a consumer reads it.

✂️ **Petra:** Who reads `zkm-telegram`'s? Nobody. 9 of the resolvable own repos carry no tags at all.

🎛️ **Orla:** Sequencing constraint you're all skipping: the reviewer-at-integrate turn is the **expensive tier**, already doing roadmap re-derivation, the test-integrity audit, and the merge. `e647` adds a manifest+lockfile write; `b8fa` adds a changelog write. Both land in the critical path that gates every repo's throughput. And zkm's bump **cascades** to every plugin's `uv.lock`.

😈 **Riku:** So: `e647` first, alone, and watch it. If it doesn't fire — bumps skipped, repos stalled on `clean-tree-gate.sh` — then `b8fa` was built on a hook that doesn't work.

🏗️ **Archie:** Conceded. Deciding them together, as `b8fa` demands, doesn't mean shipping them together.

**Tobias:** Ratified D3 "Amend 8ef3 — dotclaude-skills gets a CHANGELOG but still no version" and D4 "Per-repo CHANGELOG in every semver repo; ship both together" — **overriding** the recommendation on both.

### Amendment session

😈 **Riku:** D2 (derive at integrate **from the bump**) and D3 (changelog, **no version**) don't compose. No manifest → no bump → nothing fires the hook. As written, D3 asks for an entry nothing produces.

🏗️ **Archie:** The resolution is in the original ask: `b8fa` quotes "bucketed by sensible time ranges (e.g. daily)". Date buckets need no version. Semver repos bucket by release; version-less repos bucket by date. Same deriver, different key.

😈 **Riku:** Second problem, which I can't resolve for him: **what is the amendment's basis?** `8ef3`'s trigger was an external consumer; still none. Today's incident is *internal* harm — and a changelog wouldn't have caught it. So today's incident is **not** evidence for D3.

✂️ **Petra:** Doesn't make D3 wrong — means the reason isn't the one on the table. `8ef3` weighed *external* consumers and found none. "Other repos' sessions read this repo through symlinks" is a **different consumer class it never considered** — a legitimate basis for an explicit amendment, not a reinterpretation. But he has to state it.

🎛️ **Orla:** And D4 runs against your own pattern — the profile records an empirical-pilot preference, and `e647` was *deliberately* parked in observe-first mode. Shipping the changelog on a hook with zero observed firings may be exactly right now the drift is measured, but it's a reversal worth making on purpose.

**Tobias:** Ratified the date-bucket resolution, and the amendment basis: **"a different consumer class 8ef3 never weighed: other repos' sessions"**. Answered the `af5a` are-we-done gate with "Done — write it up".

## Decisions

- **D1 — Global default: the reviewer bumps at integrate, once per user-observable close.** Standing rule for every semver repo: at integrate the reviewer judges each closed ROADMAP item, bumps + tags per user-observable close, and regenerates the lockfile in the **same** commit (`bump-includes-lockfile`). The judgement stays with the reviewer — a refactor close must NOT bump. **Out of scope:** deriving the bump itself (Riku: "user-observable" is not derivable); the executor ever bumping (worktrees collide on manifest+lockfile — Orla); per-repo opt-in (that IS the status quo `e647` complains about).
- **D2 — The CHANGELOG is derived at integrate, from existing relay state, starting from now.** Source is what the relay already has: `workedIds`, `relay-ckpt-*` tag messages, `RELAY_LOG.md`. **If it requires a new per-item "user-facing?" field, this decision is wrong and must come back** — that is authoring with extra steps, not derivation. **Out of scope:** retroactive backfill — per-close tags are unrecoverable after the 2026-07-16 batch, so generated history would be plausible and unverifiable (a fabricated record).
- **D3 — `8ef3` is EXPLICITLY AMENDED: `dotclaude-skills` gets a CHANGELOG, but still no version.** Git remains the version SSOT — no `VERSION` file, no `v*` tags, no manifest. **Amendment basis (owner-stated, on record):** `8ef3` evaluated only *external* consumers and correctly found none; this repo is consumed *internally*, through per-file symlinks, by every other repo's sessions — **a consumer class `8ef3` never weighed**. This is an explicit amendment on a premise the original did not consider, NOT a reinterpretation of its words. **Trigger for a version-less repo:** date buckets (per the user's own original ask), fired per relay integrate; semver repos bucket by release. **Out of scope:** giving this repo a version (`8ef3`'s no-version ruling stands unamended); citing this amendment as precedent that `8ef3` was wrong about versions.
- **D4 — Per-repo `CHANGELOG.md` in every semver repo; `e647` and `b8fa` ship together.** Overrides the recommended pilot-first sequencing. **Recorded dissent (Riku/Orla, for the record, not to re-litigate):** this builds `b8fa` on a hook with zero observed firings; if the bump stalls repos via `clean-tree-gate.sh`, the changelog rides a mechanism that does not work yet. **Out of scope:** central-only (`claude-diary`) as the sole record — it fails the external-consumer case that motivates a changelog.

## Action items

- [ ] `id:e647` — implement the D1 bump trigger: global CLAUDE.md §Versioning gains the **when** (reviewer, at integrate, per user-observable close), and the relay integrator does it. Contract a test verifies: an integrate wave with one user-observable close produces exactly one bump+tag with a clean tree and a regenerated lockfile; a refactor-only wave produces none. Must honour `git describe --match 'v[0-9]*'` (relay-ckpt-* tags outnumber v*), and zkm's parent bump must cascade to every plugin `uv.lock`. See `docs/meeting-notes/2026-07-17-1541-semver-trigger-and-fleet-changelog.md`.
- [ ] `id:b8fa` — implement the D2 deriver, shipping with `e647` per D4. Per-repo `CHANGELOG.md` in every semver repo, release-bucketed; `dotclaude-skills` date-bucketed per D3. From now, never backfilled. Contract a test verifies: the deriver reads only existing relay state (no new per-item field), and a version-less repo produces a date-bucketed entry with no bump. See the note above.
- [x] Amend this repo's `CLAUDE.md` §Versioning to record the D3 amendment of `8ef3` — the derived doc must match the newly-ratified source. *(Done in-session 2026-07-17.)*

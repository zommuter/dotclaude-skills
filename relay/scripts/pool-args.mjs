// pool-args.mjs (id:d530) — first-class per-RUN --priority / --exclude pool args for the
// autonomous relay, so a user need NEVER hand-edit relay.toml (the destructive-registry
// anti-pattern) or hand-call inject.sh to bias one run. Both are SCOPED TO THIS RUN ONLY —
// the sticky registry is untouched.
//
// Two PURE, unit-testable helpers extracted here (the redispatch-guard.mjs precedent: the
// Workflow sandbox cannot `import`, so relay-loop.js carries BYTE-IDENTICAL inline copies of
// the bodies guarded by a structural test — keep the two in sync).
//
//   --exclude <repo|repo,repo>  → A.excludeRepos (array): DROP those repos from the own-repo
//     list BEFORE sharding (no shard ever sees them, no unit is ever emitted). Each dropped
//     repo gets a `skipped` rollup line `excluded for this run (--exclude)`. An exclude name
//     that is NOT a confirmed `own` repo is a LOUD reject — surfaced, never silently ignored.
//
//   --priority <repo|repo,repo> → A.priorityRepos (array): a per-run ORDERING bump ONLY. It
//     ranks a priority repo's NATURALLY-DISCOVERED unit ahead of non-priority units WITHIN the
//     same verdict class (above `income`, below injected-unit precedence + the D3 verdict-class
//     order — NEVER a verdict override). CRITICAL (the id:d530 finding): priority must NOT
//     create or inject a unit — it ONLY reorders the repo's own discovered unit, so it can never
//     cause the double-dispatch that `inject.sh`-as-priority did (the 2026-06-23 zkm-stt event:
//     an injected unit ran ahead AND discovery still emitted its own unit the same round).
//
// FAIL-SAFE: an empty/absent arg ⇒ no exclusion, no priority change = today's behaviour.

// Normalize a pool-arg value (a string "a,b" / a JSON-or-CLI array / undefined) to a clean
// array of trimmed non-empty repo names. Accepts an array (already split by the front door)
// or a single comma-or-space-separated string.
export function normalizeRepoArg(val) {
  if (!val) return []
  const parts = Array.isArray(val) ? val : String(val).split(/[\s,]+/)
  return parts.map(s => String(s).trim()).filter(Boolean)
}

// applyExcludeFilter(ownRepos, excludeRepos) — drop excluded repos from the own-repo list
// BEFORE sharding. ownRepos is the prelude's repos array ({repo, path, income}). Returns:
//   - kept:     ownRepos minus the excluded ones (the list that gets sharded).
//   - skipped:  {repo, reason} for each EXCLUDED + CONFIRMED-own repo (a benign skip rollup line).
//   - surfaced: {repo, reason} for each exclude NAME that is NOT a confirmed own repo (LOUD reject).
export function applyExcludeFilter(ownRepos, excludeRepos) {
  const exclude = normalizeRepoArg(excludeRepos)
  const kept = [], skipped = [], surfaced = []
  if (!exclude.length) return { kept: ownRepos.slice(), skipped, surfaced }
  const ownNames = new Set(ownRepos.map(r => r.repo))
  for (const name of exclude) {
    if (!ownNames.has(name)) {
      surfaced.push({ repo: name, reason: `--exclude: unknown/unconfirmed repo '${name}' — ignored (not a confirmed own repo; registry untouched, id:d530)` })
    }
  }
  const excludeSet = new Set(exclude)
  for (const r of ownRepos) {
    if (excludeSet.has(r.repo)) {
      skipped.push({ repo: r.repo, reason: 'excluded for this run (--exclude)' })
    } else {
      kept.push(r)
    }
  }
  return { kept, skipped, surfaced }
}

// resolveScopeRepo(onlyRepo, ownRepos) — first-class SINGLE-REPO scope (id:7633). Resolve a
// `--only <repo>` / bare-positional / `.`-resolved repo NAME against the canonical own-repo list
// (ownRepos = the prelude's relay.toml read, honoring `# path:` — never a `~/src` glob). Returns
// {scoped, surfaced}:
//   - scoped:   the matched {repo, path, income} entry (the SOLE repo that enters the discover
//               fan-out — the 40-repo universe classification is bypassed), or null.
//   - surfaced: a LOUD-reject {repo, reason} when the name is NOT a confirmed own repo (never a
//               silent guess — [[feedback-use-existing-tools-not-improvise]]), or null.
// FAIL-SAFE: an empty/absent onlyRepo ⇒ {scoped:null, surfaced:null} = no scope = today's
// behaviour (the whole own list is classified). The caller keys "single-repo mode" on a non-empty
// onlyRepo, so a null scoped WITH a surfaced reject means "asked for a repo that isn't own".
export function resolveScopeRepo(onlyRepo, ownRepos) {
  const name = onlyRepo ? String(onlyRepo).trim() : ''
  if (!name) return { scoped: null, surfaced: null }
  const match = (ownRepos || []).find(r => r.repo === name)
  if (match) return { scoped: match, surfaced: null }
  return {
    scoped: null,
    surfaced: { repo: name, reason: `--only: '${name}' is not a confirmed own repo in relay.toml — refusing to guess a path (id:7633; canonical own set only, never a ~/src glob)` },
  }
}

// priorityRank(unit, prioritySet) — within-class ordering key for the unit sort comparators.
// Lower sorts sooner. A priority repo's unit ranks 0 (ahead), every other unit 1 (behind).
// prioritySet is a Set of repo names. NEVER a verdict override — this value is only ever
// compared AFTER the injected-precedence and the D3 verdict-class keys in the comparator.
export function priorityRank(unit, prioritySet) {
  return (prioritySet && prioritySet.has(unit.repo)) ? 0 : 1
}

// validatePriorityNames(priorityRepos, ownRepos) — LOUD reject of unknown/unconfirmed priority
// names (the exclude symmetry). Returns {prioritySet, surfaced}: the Set used by priorityRank
// (confirmed own names only) + a surfaced line per unknown name. An unknown name simply has no
// discovered unit, so it can never bump anything — but it must be SURFACED, never silent.
export function validatePriorityNames(priorityRepos, ownRepos) {
  const priority = normalizeRepoArg(priorityRepos)
  const ownNames = new Set(ownRepos.map(r => r.repo))
  const prioritySet = new Set(), surfaced = []
  for (const name of priority) {
    if (ownNames.has(name)) prioritySet.add(name)
    else surfaced.push({ repo: name, reason: `--priority: unknown/unconfirmed repo '${name}' — ignored (not a confirmed own repo; registry untouched, id:d530)` })
  }
  return { prioritySet, surfaced }
}

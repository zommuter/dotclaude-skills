#!/usr/bin/env bash
# roadmap:7633 — first-class single-repo scope for the autonomous relay: `/relay <repo>` /
# `/relay .` / `--only <repo>` short-circuits the own-repo universe enumeration + discover
# fan-out, classifying ONLY that repo (the SAME per-repo path, discover-repo.sh, is reused —
# never forked). The repo resolves against the canonical relay.toml own set (honoring `# path:`);
# an unconfirmed name is a LOUD reject, never a `~/src` guess. The scope filter is a PURE helper
# (relay/scripts/pool-args.mjs::resolveScopeRepo) so it is node-unit-testable; relay-loop.js
# carries a byte-equivalent inline copy (the Workflow sandbox cannot import). Structural
# assertions below pin the wiring + that the scoped list drives the fan-out BEFORE sharding.
# Hermetic: node-only, no git, no network.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$SRC_DIR/relay/scripts/pool-args.mjs"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
SKILL="$SRC_DIR/relay/SKILL.md"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }
command -v node >/dev/null 2>&1 || { echo "FAIL: node not found"; exit 1; }
[[ -f "$HELPER" ]] || { echo "FAIL: pool-args.mjs missing"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ── Pure helper: resolveScopeRepo(onlyRepo, ownRepos) ──
cat > "$TMP/drive.mjs" <<NODE
import { resolveScopeRepo } from 'file://$HELPER'

const own = [
  { repo: 'alpha', path: '/p/alpha', income: true },
  { repo: 'beta',  path: '/src/zkm/plugins/zkm-beta', income: false }, // a # path:-relocated repo
  { repo: 'gamma', path: '/p/gamma', income: false },
]
const out = []

// (a) a confirmed own name resolves to its FULL entry (repo + the canonical # path: path) and
//     surfaces nothing.
{
  const { scoped, surfaced } = resolveScopeRepo('beta', own)
  out.push('a_scoped_repo=' + (scoped && scoped.repo))
  out.push('a_scoped_path=' + (scoped && scoped.path))   // must be the # path: override, not a ~/src guess
  out.push('a_surfaced=' + (surfaced ? '1' : '0'))
}

// (b) an UNCONFIRMED name is a LOUD reject (surfaced), scoped stays null — NO guessed repo.
{
  const { scoped, surfaced } = resolveScopeRepo('ghost', own)
  out.push('b_scoped_null=' + (scoped === null ? '1' : '0'))
  out.push('b_surfaced_repo=' + (surfaced && surfaced.repo))
  out.push('b_surfaced_loud=' + (surfaced && /not a confirmed own repo/.test(surfaced.reason) ? '1' : '0'))
  out.push('b_surfaced_noguess=' + (surfaced && /never a ~\/src glob/.test(surfaced.reason) ? '1' : '0'))
}

// (c) FAIL-SAFE: an empty/absent onlyRepo ⇒ {scoped:null, surfaced:null} = no scope (today's
//     whole-fleet behaviour). The caller keys single-repo mode on a NON-empty onlyRepo, so this
//     null-scoped/null-surfaced pair must NOT be mistaken for a reject.
{
  const empty = resolveScopeRepo('', own)
  const undef = resolveScopeRepo(undefined, own)
  const ws    = resolveScopeRepo('  ', own)
  out.push('c_empty_noop=' + (empty.scoped === null && empty.surfaced === null ? '1' : '0'))
  out.push('c_undef_noop=' + (undef.scoped === null && undef.surfaced === null ? '1' : '0'))
  out.push('c_ws_noop=' + (ws.scoped === null && ws.surfaced === null ? '1' : '0'))
}

console.log(out.join('\n'))
NODE

node "$TMP/drive.mjs" > "$TMP/res" 2>"$TMP/err" || { echo "FAIL: driver errored:"; cat "$TMP/err"; exit 1; }
get() { grep -E "^$1=" "$TMP/res" | head -1 | cut -d= -f2-; }

# (a)
[[ "$(get a_scoped_repo)" == "beta" ]] && ok "(a) a confirmed own name resolves to its entry" || bad "(a) scoped repo wrong: $(get a_scoped_repo)"
[[ "$(get a_scoped_path)" == "/src/zkm/plugins/zkm-beta" ]] && ok "(a) resolved path is the canonical # path: override (not a ~/src guess)" || bad "(a) scoped path wrong: $(get a_scoped_path)"
[[ "$(get a_surfaced)" == "0" ]] && ok "(a) a confirmed scope surfaces no reject" || bad "(a) confirmed scope wrongly surfaced"

# (b)
[[ "$(get b_scoped_null)" == "1" ]] && ok "(b) an unconfirmed scope name resolves to NO repo (no guess)" || bad "(b) unconfirmed name produced a scoped repo"
[[ "$(get b_surfaced_repo)" == "ghost" ]] && ok "(b) unconfirmed name is surfaced by name" || bad "(b) unconfirmed name not surfaced"
[[ "$(get b_surfaced_loud)" == "1" ]] && ok "(b) unconfirmed name is a LOUD reject (not a confirmed own repo)" || bad "(b) reject reason not loud"
[[ "$(get b_surfaced_noguess)" == "1" ]] && ok "(b) reject reason states the never-a-~/src-glob contract" || bad "(b) reject reason missing the no-glob contract"

# (c)
[[ "$(get c_empty_noop)" == "1" && "$(get c_undef_noop)" == "1" && "$(get c_ws_noop)" == "1" ]] \
  && ok "(c) fail-safe: empty/undefined/whitespace onlyRepo ⇒ no scope, no reject (today's behaviour)" || bad "(c) empty scope not a clean no-op"

# ── Structural: relay-loop.js wires a byte-equivalent inline resolveScopeRepo + scopes the fan-out ──
grep -q "id:7633" "$JS" || bad "relay-loop.js: no id:7633 marker (single-repo scope rationale missing)"
grep -q "const ONLY_REPO = A.onlyRepo" "$JS" || bad "relay-loop.js does not parse A.onlyRepo into ONLY_REPO"
grep -q "function resolveScopeRepo" "$JS" || bad "relay-loop.js missing the inline resolveScopeRepo helper (Workflow sandbox cannot import)"
grep -q "resolveScopeRepo(ONLY_REPO, allOwnRepos)" "$JS" || bad "relay-loop.js does not resolve ONLY_REPO against the canonical own list (allOwnRepos)"
# The scope must narrow the list that enters the shard fan-out (scopedOwnRepos), NOT allOwnRepos.
grep -q "let scopedOwnRepos = allOwnRepos" "$JS" || bad "relay-loop.js: scopedOwnRepos not seeded from allOwnRepos (fail-safe whole-fleet default)"
grep -q "scopedOwnRepos = \[scoped\]" "$JS" || bad "relay-loop.js: a confirmed scope does not narrow scopedOwnRepos to the one repo"
# The exclude/sig/shard loop must iterate scopedOwnRepos (the scoped list), so a single-repo run
# never enumerates the universe into the fan-out. Assert the ownRepos-build reads scopedOwnRepos.
grep -q "for (const r of scopedOwnRepos)" "$JS" || bad "relay-loop.js: the pre-shard own-list build does not iterate scopedOwnRepos (universe not bypassed)"
# Bypass-ordering: the scope resolution must happen BEFORE the discover fan-out (the runner agents).
python3 - "$JS" <<'PYEOF'
import sys
js = open(sys.argv[1]).read()
scope = js.find('resolveScopeRepo(ONLY_REPO, allOwnRepos)')
# the discover fan-out dispatches the mechanical runner agents (label 'discover-run')
fanout = js.find("label: `discover-run")
if scope < 0: sys.exit('no scope resolution call in relay-loop.js')
if fanout < 0: sys.exit("no discover-run fan-out label in relay-loop.js")
if scope > fanout: sys.exit('single-repo scope resolved AFTER the discover fan-out — universe still classified')
PYEOF
[[ $? -eq 0 ]] && ok "(struct) scope resolves BEFORE the discover fan-out, so the universe classification is bypassed" || bad "(struct) scope ordering wrong"

# LOUD reject wiring: an unconfirmed scope surfaces + empties the scoped list (no dispatch).
grep -q "scopedOwnRepos = \[\]" "$JS" || bad "relay-loop.js: an unconfirmed scope does not empty the scoped list (would dispatch a guess)"
grep -q "if (surfaced) poolArgSurfaced.push(surfaced)" "$JS" || bad "relay-loop.js: an unconfirmed scope reject is not surfaced (silent drop)"

# acceptance #3 regression: --exclude still validates against the FULL canonical set (ownNames),
# not the scoped list — an unknown exclude name loud-rejects even under a single-repo scope.
grep -q "ownNames = new Set(allOwnRepos.map" "$JS" || bad "relay-loop.js: ownNames not derived from the FULL canonical own list (exclude/priority validation)"

# ── SKILL.md front door documents the scope arg ──
grep -q "onlyRepo" "$SKILL" || bad "SKILL.md does not document args.onlyRepo (the single-repo scope arg)"
grep -qE "single-repo scope|--only" "$SKILL" || bad "SKILL.md does not document the --only/single-repo scope form"

[[ "$pass" -gt 0 ]] && ok "single-repo scope helper + relay-loop.js wiring verified" || true
echo "test_relay_single_repo_scope: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]

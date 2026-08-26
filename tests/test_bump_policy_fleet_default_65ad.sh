#!/usr/bin/env bash
# roadmap:65ad — FLEET DEFAULT `bump_policy = minor` in relay/scripts/integrate.sh.
#
# Owner-ratified 2026-08-22 (meeting D12). When a manifest repo's `[repos.<name>]` block in
# relay.toml carries NO explicit `bump_policy`, the bump trigger now resolves to `minor`
# instead of emitting the `SEMVER BUMP TRIGGER UNRESOLVABLE` HANDBACK[bump] (id:e647).
#
# This is an EXPLICIT owner AMENDMENT of the ratified 2026-07-17-1541 D1 rule ("a
# refactor-only / internal-cleanup close does NOT bump"): there is no no-bump branch under
# any level policy, so a defaulted close bumps unconditionally. `minor` over `patch`
# because under loose-0.x `patch` means bugfix-only — the harmful UNDER-signal for a
# defaulted feature close, where `minor` is the harmless over-signal.
#
# A FURTHER owner amendment (2026-08-26) withdrew D1's no-bump half OUTRIGHT — "a
# refactor/internal can still mess up plenty and must at least bump patch" — so the former
# `--no-bump` per-close escape now resolves to PATCH and is spelled `--internal`
# (`--no-bump` remains a deprecated, loudly-warning alias). NO per-close path skips a bump
# on a manifest repo any more; the only surviving skip is a durable owner-recorded
# `bump_policy = "never"`.
#
# Precedence this file pins (first match wins), across the whole resolution ladder:
#   --level > --internal > version-less repo > --substantive false > explicit bump_policy
#   > FLEET DEFAULT minor.
#
# ── THE THREE-WAY READER SEMANTIC this file pins (id:65ad reader hole + id:d51f(b)) ──
# A fleet default makes "absent" mean "bump", so the reader must never CONFUSE a line it
# failed to read with a line that is not there. Three states, three outcomes:
#
#   ABSENT              — no `bump_policy`-ish line in this repo's block (or no block, or
#                         no relay.toml at all)                    => FLEET DEFAULT minor.
#   PRESENT-BUT-UNPARSED— a line IS there but yielded no value: an empty/malformed RHS, or
#                         a NEAR-MISS KEY (any key whose normalised form contains `bump`,
#                         e.g. `bumppolicy`, `bump-policy`, `BUMP_POLICY`, `bump_polcy`)
#                                                     => LOUD HANDBACK[bump], exit 30.
#   PRESENT, PARSED, UNRECOGNISED VALUE
#                       — `auto`, `NEVER`, `mnior`, …  => LOUD WARNING naming the value,
#                         then FALL THROUGH to the minor fleet default (id:d51f(b),
#                         owner-decided 2026-08-22; the load-bearing guard is the WRITER-side
#                         enum validation, id:d51f(a), which makes this path near-unreachable).
#
# The parse must therefore be robust to VALID TOML spellings that a naive three-field awk
# split misses — `bump_policy="never"` (no spaces), arbitrary whitespace around `=`, an
# indented `[repos.<name>]` header — because under a fleet default every such miss is a
# SILENT bump against a recorded `never`, i.e. a fail-silent in the unsafe direction.
#
# Hermetic: everything under a mktemp -d, a local bare `origin`, a push stub. Never touches
# ~/.claude, the real ~/.config/relay/relay.toml (FABLES_CONFIG is overridden everywhere),
# or the network.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INT="${INT_OVERRIDE:-$SRC_DIR/relay/scripts/integrate.sh}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ERRLOG="$TMP/integrate.stderr"
: >"$ERRLOG"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; [[ -s "$ERRLOG" ]] && { echo "       last integrate.sh stderr:"; tail -n 20 "$ERRLOG" | sed 's/^/       | /'; }; exit 1; }

[[ -x "$INT" ]] || fail "integrate.sh not found/executable at $INT"

PUSH_STUB="$TMP/push-stub.sh"
cat > "$PUSH_STUB" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
p=""
for a in "$@"; do case "$a" in --ff-only|--all|-b|-m|-f) ;; *) p="$a" ;; esac; done
git -C "$p" push --follow-tags origin HEAD >/dev/null 2>&1
EOF
chmod +x "$PUSH_STUB"

# ── fixture builders (mirroring tests/test_integrate_mechanized_ports_087b.sh) ──
# $2 = "manifest" seeds a pyproject.toml at 0.4.0; anything else leaves the repo VERSION-LESS.
build() { # <suffix> <manifest|versionless> → prints the main checkout path
  local sfx="$1" kind="$2"
  local origin seed main
  origin="$TMP/o-$sfx.git"; seed="$TMP/s-$sfx"; main="$TMP/m-$sfx"
  git init --bare -b main -q "$origin"
  git clone -q "$origin" "$seed" 2>/dev/null
  git -C "$seed" config user.email t@e.st
  git -C "$seed" config user.name t
  echo base > "$seed/f"
  [[ "$kind" == manifest ]] && printf '[project]\nname = "x"\nversion = "0.4.0"\n' > "$seed/pyproject.toml"
  git -C "$seed" add -A
  git -C "$seed" commit -qm base
  git -C "$seed" push -q -u origin main
  git clone -q "$origin" "$main" 2>/dev/null
  git -C "$main" config user.email t@e.st
  git -C "$main" config user.name t
  printf '%s' "$main"
}

child() { # <main> <name> → prints the worktree path
  local main="$1" name="$2"
  local wt="$TMP/wt-$name"
  git -C "$main" worktree add -q -b "relay/$name" "$wt" main
  echo "work-$name" > "$wt/g-$name"
  git -C "$wt" add -A
  git -C "$wt" commit -qm "child work $name"
  printf '%s' "$wt"
}

cfg() { # <suffix> <repo-name> [policy-line] → prints the config dir
  local d="$TMP/cfg-$1"
  mkdir -p "$d"
  printf '[repos.%s]\nstatus = "active"\n' "$2" > "$d/relay.toml"
  [[ -n "${3:-}" ]] && printf '%s\n' "$3" >> "$d/relay.toml"
  printf '%s' "$d"
}

# run <suffix> <manifest|versionless> <policy-line|""> [extra integrate.sh args...]
#   → sets $RC and $OUT
run() {
  local sfx="$1" kind="$2" pol="$3"; shift 3
  local m r wt c
  m="$(build "$sfx" "$kind")"; r="$(basename "$m")"
  wt="$(child "$m" "$sfx")"
  c="$(cfg "$sfx" "$r" "$pol")"
  MAIN_PATH="$m"; HEAD_BEFORE="$(git -C "$m" rev-parse HEAD)"; WT_PATH="$wt"
  RC=0
  OUT="$(FABLES_CONFIG="$c" INTEGRATE_GIT_LOCK_PUSH="$PUSH_STUB" \
    "$INT" --repo "$r" --path "$m" --worktree "$wt" --branch "relay/$sfx" \
           --summary "close" --run r1 --label "executor (sonnet, relay-loop)" \
           --verdict execute --substantive true "$@" 2>"$ERRLOG")" || RC=$?
}

# runtoml <suffix> <manifest|versionless> <printf template, ONE %s for the repo name> [args...]
#   Same contract as run(), but the caller supplies the WHOLE relay.toml body — needed for
#   the spellings cfg() cannot express (indented block header, near-miss key, bare `=`).
#   Exactly one %s: printf REUSES a format string when given extra args, so never add more.
runtoml() {
  local sfx="$1" kind="$2" tpl="$3"; shift 3
  local m r wt c
  m="$(build "$sfx" "$kind")"; r="$(basename "$m")"
  wt="$(child "$m" "$sfx")"
  c="$TMP/cfg-$sfx"; mkdir -p "$c"
  # shellcheck disable=SC2059  # the template IS the payload here
  printf "$tpl" "$r" > "$c/relay.toml"
  MAIN_PATH="$m"; HEAD_BEFORE="$(git -C "$m" rev-parse HEAD)"; WT_PATH="$wt"
  : >"$ERRLOG"
  RC=0
  OUT="$(FABLES_CONFIG="$c" INTEGRATE_GIT_LOCK_PUSH="$PUSH_STUB" \
    "$INT" --repo "$r" --path "$m" --worktree "$wt" --branch "relay/$sfx" \
           --summary "close" --run r1 --label "executor (sonnet, relay-loop)" \
           --verdict execute --substantive true "$@" 2>"$ERRLOG")" || RC=$?
}

bump_of() { grep -m1 '^bump=' <<<"$OUT" | cut -d= -f2- ; }
version_of() { grep -m1 '^version = ' "$MAIN_PATH/pyproject.toml" | sed 's/.*"\(.*\)".*/\1/' ; }

# =====================================================================================
# (1) THE AMENDMENT — a manifest repo whose [repos.<name>] block carries NO bump_policy
#     resolves to a MINOR bump instead of handing back.
# =====================================================================================
run default manifest ""
[[ $RC -eq 0 ]] || fail "(1) no bump_policy still handed back (exit $RC) — the fleet default did not fire"
[[ "$(bump_of)" == v0.5.0 ]] || fail "(1) expected the fleet default to mint v0.5.0, got '$(bump_of)'"
grep -q '^version = "0.5.0"$' "$MAIN_PATH/pyproject.toml" \
  || fail "(1) the manifest was not actually bumped to 0.5.0: $(grep version "$MAIN_PATH/pyproject.toml")"
pass "(1) id:65ad: a manifest repo with NO bump_policy defaults to a MINOR bump, no handback"

# (1b) the same repo when relay.toml has no [repos.<name>] block AT ALL (an unregistered
#      repo reaches the same absent-policy state) — still the default, no BUMP handback.
#      NOTE: such a repo legitimately fails LATER at the relay-state-write step (exit 29,
#      there is no block to write last_ckpt into), so this case asserts only that the bump
#      GATE defaulted — exit != 30, no HANDBACK[bump], and the manifest really was bumped.
MB="$(build noblock manifest)"; RB="$(basename "$MB")"
WTB="$(child "$MB" noblock)"
CB="$TMP/cfg-noblock"; mkdir -p "$CB"
printf '[repos.someone-else]\nstatus = "active"\n' > "$CB/relay.toml"
rc=0
bout="$(FABLES_CONFIG="$CB" INTEGRATE_GIT_LOCK_PUSH="$PUSH_STUB" \
  "$INT" --repo "$RB" --path "$MB" --worktree "$WTB" --branch relay/noblock \
         --summary "close" --run r1 --label "executor (sonnet, relay-loop)" \
         --verdict execute --substantive true 2>"$ERRLOG")" || rc=$?
[[ $rc -ne 30 ]] || fail "(1b) a repo with no [repos.<name>] block still hit the BUMP handback (exit 30)"
grep -q 'HANDBACK\[bump\]' "$ERRLOG" && fail "(1b) an absent [repos.<name>] block produced a bump handback"
grep -q '^version = "0.5.0"$' "$MB/pyproject.toml" \
  || fail "(1b) the fleet default did not bump an unregistered repo: $(grep version "$MB/pyproject.toml")"
pass "(1b) id:65ad: an absent [repos.<name>] block takes the same fleet default"

# =====================================================================================
# (2) AN EXPLICIT bump_policy STILL WINS over the default — all three recognised values.
# =====================================================================================
run polnever manifest 'bump_policy = "never"'
[[ $RC -eq 0 ]] || fail "(2a) bump_policy = never handed back (exit $RC)"
[[ -z "$(bump_of)" ]] || fail "(2a) bump_policy = never produced a bump '$(bump_of)' — the default overrode an explicit policy"
grep -q '^version = "0.4.0"$' "$MAIN_PATH/pyproject.toml" || fail "(2a) bump_policy = never changed the manifest version"
pass "(2a) explicit bump_policy = never still wins over the fleet default (no bump)"

run polminor manifest 'bump_policy = "minor"'
[[ $RC -eq 0 ]] || fail "(2b) bump_policy = minor handed back (exit $RC)"
[[ "$(bump_of)" == v0.5.0 ]] || fail "(2b) expected v0.5.0 from bump_policy = minor, got '$(bump_of)'"
pass "(2b) explicit bump_policy = minor resolves to a minor bump"

run polpatch manifest 'bump_policy = "patch"'
[[ $RC -eq 0 ]] || fail "(2c) bump_policy = patch handed back (exit $RC)"
[[ "$(bump_of)" == v0.4.1 ]] || fail "(2c) expected v0.4.1 from bump_policy = patch, got '$(bump_of)' — the fleet default shadowed an explicit patch policy"
pass "(2c) explicit bump_policy = patch still wins over the fleet default (patch, not minor)"

# =====================================================================================
# (3) A VERSION-LESS repo never reaches the gate at all — the default must not invent a
#     bump for a repo that has nothing to bump (dotclaude-skills' own case, id:8ef3).
# =====================================================================================
run versionless versionless ""
[[ $RC -eq 0 ]] || fail "(3) a version-less repo handed back (exit $RC)"
[[ -z "$(bump_of)" ]] || fail "(3) a version-less repo reported a bump '$(bump_of)' — the fleet default reached past the version-less branch"
[[ ! -e "$MAIN_PATH/pyproject.toml" ]] || fail "(3) the fleet default CREATED a manifest in a version-less repo"
pass "(3) id:8ef3: a version-less repo still never reaches the bump gate"

# =====================================================================================
# (4) EXPLICIT CALLER FLAGS still override the fleet default.
# =====================================================================================
# (4a) --internal still OUTRANKS the fleet default — but since the owner's 2026-08-26
# amendment of meeting 2026-07-17-1541 D1 ("a refactor/internal can still mess up plenty and
# must at least bump patch") it resolves to PATCH, not to nothing. So the thing being proved
# here is that the explicit caller judgement still wins over the default's `minor`.
run flagnobump manifest "" --internal
[[ $RC -eq 0 ]] || fail "(4a) --internal handed back (exit $RC)"
[[ "$(bump_of)" == v0.4.1 ]] || fail "(4a) --internal resolved to '$(bump_of)', expected v0.4.1 (a PATCH bump) — the fleet default overrode an explicit caller judgement"
grep -q '^version = "0.4.1"$' "$MAIN_PATH/pyproject.toml" || fail "(4a) --internal did not bump the manifest to 0.4.1"
pass "(4a) --internal still overrides the fleet default's minor (refactor-only close, patch bump)"

run flaglevel manifest "" --level patch
[[ $RC -eq 0 ]] || fail "(4b) --level patch handed back (exit $RC)"
[[ "$(bump_of)" == v0.4.1 ]] || fail "(4b) expected v0.4.1 from --level patch, got '$(bump_of)'"
pass "(4b) --level patch still overrides the fleet default (patch, not the defaulted minor)"

# --level beats even an explicit contrary policy (precedence order unchanged).
run flagoverpol manifest 'bump_policy = "never"' --level minor
[[ $RC -eq 0 ]] || fail "(4c) --level over bump_policy=never handed back (exit $RC)"
[[ "$(bump_of)" == v0.5.0 ]] || fail "(4c) --level minor did not beat bump_policy = never, got '$(bump_of)'"
pass "(4c) --level still outranks an explicit bump_policy (precedence ladder intact)"

# --substantive false still resolves to no bump ahead of the default.
MS="$(build subfalse manifest)"; RS="$(basename "$MS")"
WTS="$(child "$MS" subfalse)"
CS="$(cfg subfalse "$RS")"
rc=0
sout="$(FABLES_CONFIG="$CS" INTEGRATE_GIT_LOCK_PUSH="$PUSH_STUB" \
  "$INT" --repo "$RS" --path "$MS" --worktree "$WTS" --branch relay/subfalse \
         --summary "no-op review" --run r1 --label "reviewer (claude-opus-5, relay-loop)" \
         --verdict review --substantive false --strong-model claude-opus-5 2>"$ERRLOG")" || rc=$?
[[ $rc -eq 0 ]] || fail "(4d) --substantive false handed back (exit $rc)"
grep -q '^bump=$' <<<"$sout" || fail "(4d) --substantive false produced a bump — the default reached past it"
pass "(4d) --substantive false still resolves to NO bump ahead of the fleet default"

# =====================================================================================
# (5) THE PARSE HOLE — a VALID TOML spelling the reader fails to split must NEVER be
#     mistaken for ABSENT. Before the fleet default, a miss here degraded to a loud
#     HANDBACK[bump]; WITH the default, the very same miss silently MINTS A VERSION
#     against an owner's recorded `never`. Every case below is real TOML.
# =====================================================================================

# (5a) `bump_policy="never"` — no spaces around `=`. VALID TOML, and precisely the
#      spelling a human hand-editing relay.toml (which the handback text tells them to
#      do) is likeliest to write. Must be HONOURED, not defaulted.
run polnospace manifest 'bump_policy="never"'
[[ $RC -eq 0 ]] || fail "(5a) bump_policy=\"never\" (no spaces) handed back (exit $RC)"
[[ -z "$(bump_of)" ]] || fail "(5a) bump_policy=\"never\" written WITHOUT spaces was parsed as ABSENT and silently bumped '$(bump_of)' — fail-silent in the unsafe direction"
[[ "$(version_of)" == 0.4.0 ]] || fail "(5a) the manifest was bumped to $(version_of) despite a recorded bump_policy=\"never\""
pass "(5a) bump_policy=\"never\" with no spaces around = is honoured, not defaulted"

# (5b) arbitrary whitespace (tabs + runs of spaces) around the `=`. Also valid TOML.
run polwsp manifest 'bump_policy 	=	  "never"'
[[ $RC -eq 0 ]] || fail "(5b) whitespace-padded bump_policy handed back (exit $RC)"
[[ -z "$(bump_of)" ]] || fail "(5b) whitespace-padded bump_policy = \"never\" was parsed as ABSENT and silently bumped '$(bump_of)'"
[[ "$(version_of)" == 0.4.0 ]] || fail "(5b) the manifest was bumped to $(version_of) despite a recorded never"
pass "(5b) arbitrary whitespace around = is tolerated, the recorded never is honoured"

# (5c) an INDENTED `[repos.<name>]` header. Valid TOML; an exact `$0 == want` block match
#      misses it, so the whole block — policy included — reads as absent.
runtoml polindent manifest '  [repos.%s]\n  status = "active"\n  bump_policy = "never"\n'
[[ $RC -ne 30 ]] || fail "(5c) an indented [repos.<name>] header produced a BUMP handback (exit 30)"
[[ "$(version_of)" == 0.4.0 ]] || fail "(5c) an INDENTED block header hid bump_policy = \"never\" — the manifest was silently bumped to $(version_of)"
pass "(5c) an indented [repos.<name>] header still finds the recorded bump_policy"

# (5d) a NEAR-MISS KEY. `bumppolicy` is inside the repo's block and its intent is
#      unmistakable, so it is PRESENT-BUT-UNPARSED, NOT absent: staying loud is the only
#      outcome that cannot silently contradict what the owner wrote. (Semantic pinned
#      here: near-miss = any key whose normalised form — lowercased, `_`/`-`/space
#      stripped — CONTAINS `bump`. It deliberately does NOT key on `policy`, so a future
#      unrelated `*_policy` key cannot start false-tripping this gate.)
run polnearkey manifest 'bumppolicy = "never"'
[[ $RC -eq 30 ]] || fail "(5d) a near-miss key 'bumppolicy = \"never\"' was treated as ABSENT and defaulted (exit $RC) — a present-but-unparsed line must stay LOUD"
grep -q 'HANDBACK\[bump\]' "$ERRLOG" || fail "(5d) no loud HANDBACK[bump] for a near-miss bump_policy key"
grep -q 'bumppolicy' "$ERRLOG" || fail "(5d) the handback does not quote the offending line, so a human cannot see what was wrong"
[[ "$(git -C "$MAIN_PATH" rev-parse HEAD)" == "$HEAD_BEFORE" ]] \
  || fail "(5d) main MOVED before the bump handback — the trigger must resolve BEFORE any mutation"
[[ -d "$WT_PATH" ]] || fail "(5d) the worktree was retired despite the handback"
pass "(5d) a near-miss key is PRESENT-BUT-UNPARSED — loud handback, main unmoved, never the default"

# (5e) case-differing key. TOML keys are case-sensitive, so `BUMP_POLICY` is NOT the key —
#      but it is just as clearly intended, so it takes the same present-but-unparsed path.
run polupkey manifest 'BUMP_POLICY = "never"'
[[ $RC -eq 30 ]] || fail "(5e) 'BUMP_POLICY = \"never\"' was treated as ABSENT and defaulted (exit $RC)"
grep -q 'HANDBACK\[bump\]' "$ERRLOG" || fail "(5e) no loud HANDBACK[bump] for a case-differing bump_policy key"
pass "(5e) a case-differing key is PRESENT-BUT-UNPARSED, not absent"

# (5f) the canonical key with an EMPTY right-hand side. Present, unparseable, so loud.
run polempty manifest 'bump_policy ='
[[ $RC -eq 30 ]] || fail "(5f) an empty 'bump_policy =' was treated as ABSENT and defaulted (exit $RC)"
grep -q 'HANDBACK\[bump\]' "$ERRLOG" || fail "(5f) no loud HANDBACK[bump] for an empty bump_policy value"
pass "(5f) an empty bump_policy RHS is PRESENT-BUT-UNPARSED — loud, never defaulted"

# (5g) REGRESSION GUARD for the case that already worked: a trailing inline comment must
#      not be swallowed into the value (that would turn `never` into an unrecognised
#      value and — post-id:d51f(b) — a warned bump).
run polcomment manifest 'bump_policy = "never" # standing judgement, 2026-08-22'
[[ $RC -eq 0 ]] || fail "(5g) bump_policy with a trailing comment handed back (exit $RC)"
[[ -z "$(bump_of)" ]] || fail "(5g) a trailing inline comment broke the value parse — bumped '$(bump_of)'"
[[ "$(version_of)" == 0.4.0 ]] || fail "(5g) the manifest was bumped to $(version_of) despite never + comment"
pass "(5g) a trailing inline comment is stripped, the recorded never is honoured"

# =====================================================================================
# (6) id:d51f(b) — a PARSED but UNRECOGNISED VALUE now WARNS AND DEFAULTS, it does not
#     hand back. This REVERSES the id:65ad implementer's original call (which handed
#     back on a typo). Owner decision 2026-08-22: the load-bearing guard is WRITER-side
#     enum validation in relay-state-write.sh (id:d51f(a), NOT implemented here), which
#     makes this reader path near-unreachable defence-in-depth. The warning must NAME the
#     bad value — an unattended --afk pool is exactly where a nameless warning is useless.
#
#     KEEP THE DISTINCTION FROM (5): unparsed/absent-shaped stays LOUD-AND-HANDBACK;
#     parsed-but-unrecognised WARNS AND DEFAULTS. They are different states.
# =====================================================================================

# (6a) the realistic failure — an agent inventing a plausible-but-absent enum member.
run polauto manifest 'bump_policy = "auto"'
[[ $RC -eq 0 ]] || fail "(6a) an unrecognised bump_policy value handed back (exit $RC) — id:d51f(b) says warn and default"
[[ "$(bump_of)" == v0.5.0 ]] || fail "(6a) expected the fleet default v0.5.0 after warning, got '$(bump_of)'"
grep -q 'WARNING' "$ERRLOG" || fail "(6a) an unrecognised bump_policy value defaulted SILENTLY — no WARNING on stderr"
grep -q "auto" "$ERRLOG" || fail "(6a) the warning does not NAME the unrecognised value"
grep -q 'd51f' "$ERRLOG" || fail "(6a) the warning does not cite id:d51f, so a reader cannot find the decision"
pass "(6a) id:d51f(b): bump_policy = \"auto\" warns loudly (naming the value) and takes the fleet default"

# (6b) a CASE-differing VALUE. The key parsed, so this is the value path, not (5e)'s key
#      path: warn and default, NOT a handback. (Pre-id:d51f(b) this was exit 30.)
run polupval manifest 'bump_policy = "NEVER"'
[[ $RC -eq 0 ]] || fail "(6b) bump_policy = \"NEVER\" handed back (exit $RC) — a parsed unrecognised value warns and defaults"
[[ "$(bump_of)" == v0.5.0 ]] || fail "(6b) expected v0.5.0 after warning on \"NEVER\", got '$(bump_of)'"
grep -q 'NEVER' "$ERRLOG" || fail "(6b) the warning does not name the unrecognised value NEVER"
pass "(6b) a case-differing VALUE warns and defaults (values are matched exactly, lowercase)"

# (6c) the plain typo the original id:65ad implementation handed back on.
run poltypo manifest 'bump_policy = "mnior"'
[[ $RC -eq 0 ]] || fail "(6c) bump_policy = \"mnior\" handed back (exit $RC) — id:d51f(b) reversed that"
[[ "$(bump_of)" == v0.5.0 ]] || fail "(6c) expected v0.5.0 after warning on \"mnior\", got '$(bump_of)'"
grep -q 'mnior' "$ERRLOG" || fail "(6c) the warning does not name the typo'd value"
pass "(6c) a typo'd bump_policy value warns and defaults (was exit 30 before id:d51f(b))"

# =====================================================================================
# (7) THE OVERRIDE IS DOCUMENTED AT THE FALLBACK SITE. A future reader must not be able
#     to mistake this for an accidental config default.
# =====================================================================================
: >"$ERRLOG"
grep -q 'id:65ad' "$INT" || fail "(7) the fleet default carries no id:65ad marker in integrate.sh"
grep -q '2026-08-22' "$INT" || fail "(7) the fleet default does not record the owner-ratification date"
grep -q '2026-07-17-1541' "$INT" || fail "(7) the fleet default does not name the ratified rule it overrides"
grep -qi 'over.signal\|under.signal' "$INT" || fail "(7) the fleet default does not record why minor was chosen over patch"
int_step3c="$(awk '/step 3c: BUMP-TRIGGER/{f=1} f&&/step 4: merge/{exit} f' "$INT")"
[[ -n "$int_step3c" ]] || fail "(7) could not extract integrate.sh's step-3c block"
grep -q 'd51f' <<<"$int_step3c" || fail "(7) the warn-and-default path does not cite id:d51f at the site"
grep -q 'relay-state-write' <<<"$int_step3c" \
  || fail "(7) the reader-side fallthrough does not name the WRITER-side primary guard (relay-state-write.sh, id:d51f(a)) it is defence-in-depth for"
pass "(7) the fleet default + the d51f(b) fallthrough are documented AT THE SITE"

# =====================================================================================
# (8) THE STALE PROSE CONTRACTS — both restated the pre-id:65ad behaviour and both were
#     missed by the first pass. A contract doc that asserts the OLD behaviour is worse
#     than no doc: it is read as current.
# =====================================================================================
CONV="$SRC_DIR/relay/references/conventions.md"
LOOP="$SRC_DIR/relay/scripts/relay-loop.js"
[[ -f "$CONV" ]] || fail "(8) conventions.md not found at $CONV"
[[ -f "$LOOP" ]] || fail "(8) relay-loop.js not found at $LOOP"

conv_sec="$(awk '/^## Semver bump trigger at integrate/{f=1} f&&/^## /&&!/^## Semver bump trigger at integrate/{exit} f' "$CONV")"
grep -q 'id:65ad' <<<"$conv_sec" || fail "(8a) conventions.md's Semver bump trigger section never mentions id:65ad — it still documents the pre-change ladder"
grep -qi 'fleet default' <<<"$conv_sec" || fail "(8a) conventions.md does not document the fleet default"
grep -q 'That deferral is the intended behaviour, not a bug' <<<"$conv_sec" \
  && fail "(8a) conventions.md still asserts the pre-change 'will hand back until the owner records bump_policy … intended behaviour, not a bug' claim"
grep -qi 'functionally identical\|functional identity' <<<"$conv_sec" \
  || fail "(8a) conventions.md records the override's OUTCOME but not the owner's REASONING (a refactor asserts a functional identity it cannot guarantee)"
# NB: `grep -qi lean` would be VACUOUS here — "internal-cleanup" contains "lean". Word-anchored.
grep -qE '(^|[^[:alnum:]])Lean([^[:alnum:]]|$)' <<<"$conv_sec" \
  || fail "(8a) conventions.md omits the formally-verified (Lean) carve-out the owner named"
grep -q 'd51f' <<<"$conv_sec" || fail "(8a) conventions.md does not document the warn-and-default value path (id:d51f(b))"
pass "(8a) conventions.md's bump-trigger contract states the CURRENT behaviour and the owner's reasoning"

loop_sec="$(grep 'THE SEMVER BUMP TRIGGER' -A 18 "$LOOP")"
[[ -n "$loop_sec" ]] || fail "(8b) could not locate the bump-trigger comment block in relay-loop.js"
grep -qi 'fleet default\|id:65ad' <<<"$loop_sec" \
  || fail "(8b) relay-loop.js's bump-trigger comment still describes the pre-id:65ad handback-only behaviour"
pass "(8b) relay-loop.js's bump-trigger comment states the current behaviour"

echo "ALL PASS: id:65ad fleet default + id:d51f(b) reader semantics + the prose contracts"

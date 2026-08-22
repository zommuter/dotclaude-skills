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
# Precedence this file pins (first match wins), across the whole resolution ladder:
#   --level > --no-bump > version-less repo > --substantive false > explicit bump_policy
#   > FLEET DEFAULT minor.
# The LOUD handback is NOT deleted — it still fires for an explicit but UNRECOGNISED
# bump_policy value, so a typo'd policy can never be silently defaulted away.
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
for a in "$@"; do case "$a" in --ff-only|-b|-m|-f) ;; *) p="$a" ;; esac; done
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

bump_of() { grep -m1 '^bump=' <<<"$OUT" | cut -d= -f2- ; }

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
run flagnobump manifest "" --no-bump
[[ $RC -eq 0 ]] || fail "(4a) --no-bump handed back (exit $RC)"
[[ -z "$(bump_of)" ]] || fail "(4a) --no-bump produced a bump '$(bump_of)' — the fleet default overrode an explicit caller judgement"
grep -q '^version = "0.4.0"$' "$MAIN_PATH/pyproject.toml" || fail "(4a) --no-bump changed the manifest version"
pass "(4a) --no-bump still overrides the fleet default (refactor-only close, no bump)"

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
# (5) THE LOUD HANDBACK IS NOT DELETED — an explicit but UNRECOGNISED bump_policy value
#     (a typo) must still hand back loudly with exit 30 and NOTHING mutated. Silently
#     defaulting a typo'd policy would make the config unfalsifiable.
# =====================================================================================
run poltypo manifest 'bump_policy = "mnior"'
[[ $RC -ne 0 ]] || fail "(5) an unrecognised bump_policy value was SILENTLY defaulted — a typo must stay loud"
[[ $RC -eq 30 ]] || fail "(5) expected the distinct bump exit code 30 for a bad policy, got $RC"
grep -q 'HANDBACK\[bump\]' "$ERRLOG" || fail "(5) no loud HANDBACK[bump] line for an unrecognised policy value"
[[ "$(git -C "$MAIN_PATH" rev-parse HEAD)" == "$HEAD_BEFORE" ]] \
  || fail "(5) main MOVED before the bump handback — the trigger must resolve BEFORE any mutation"
[[ -d "$WT_PATH" ]] || fail "(5) the worktree was retired despite the handback"
pass "(5) id:e647: an unrecognised bump_policy value still hands back loudly (exit 30), main unmoved"

# =====================================================================================
# (6) THE OVERRIDE IS DOCUMENTED AT THE FALLBACK SITE. A future reader must not be able
#     to mistake this for an accidental config default.
# =====================================================================================
: >"$ERRLOG"
grep -q 'id:65ad' "$INT" || fail "(6) the fleet default carries no id:65ad marker in integrate.sh"
grep -q '2026-08-22' "$INT" || fail "(6) the fleet default does not record the owner-ratification date"
grep -q '2026-07-17-1541' "$INT" || fail "(6) the fleet default does not name the ratified rule it overrides"
grep -qi 'over.signal\|under.signal' "$INT" || fail "(6) the fleet default does not record why minor was chosen over patch"
pass "(6) the fleet default is documented AT THE SITE as a deliberate, dated owner override"

echo "ALL PASS: id:65ad fleet default bump_policy = minor with per-repo + flag override"

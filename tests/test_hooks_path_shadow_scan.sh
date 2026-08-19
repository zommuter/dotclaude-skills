#!/usr/bin/env bash
# roadmap:2bc6 — hooks-path-shadow-scan.sh: mechanical detector for repo-local
# core.hooksPath silently shadowing the global hook dir (pre-push privacy gate,
# pre-commit lane-vocab ratchet) across the relay own-set. Read-only; consumes
# lib-own-repos.sh's own_repos, never a glob or a re-derived repo list.
#
# Fixture: three own repos —
#   repoEmpty      core.hooksPath points at a dir with only *.sample files (or none)
#                  → EMPTY-SHADOW (the gate is hollow, actionable).
#   repoDeliberate core.hooksPath points at a dir with a real (non-.sample) hook file
#                  → DELIBERATE (repo-local hooks genuinely wanted, an owner call).
#   repoClean      no local core.hooksPath at all → no row.
# Asserts all three (a positive-only test would pass against a detector that flags
# everything).

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/relay/scripts/hooks-path-shadow-scan.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SH" ]] || fail "hooks-path-shadow-scan.sh not found at $SH"
[[ -x "$SH" ]] || fail "hooks-path-shadow-scan.sh not executable"
bash -n "$SH" || fail "hooks-path-shadow-scan.sh fails bash -n"
pass "hooks-path-shadow-scan.sh exists, executable, parses"

# (0) Misuse: unknown flag exits nonzero.
rc=0; "$SH" --definitely-not-a-flag >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] || fail "unknown flag must exit nonzero (misuse); got 0"
pass "unknown flag exits nonzero (misuse reject)"

FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT

mk_repo() { # <name>
  local d="$FIX/$1"; mkdir -p "$d"; git -C "$d" init -q
  git -C "$d" config user.email t@e.st; git -C "$d" config user.name t
  printf '# repo\n' > "$d/README.md"
  git -C "$d" add -A; git -C "$d" commit -qm init -q
}

mk_repo repoEmpty
mk_repo repoDeliberate
mk_repo repoClean

# repoEmpty: hooksPath dir exists but only carries the standard *.sample noise.
mkdir -p "$FIX/repoEmpty/.githooks"
: > "$FIX/repoEmpty/.githooks/pre-commit.sample"
git -C "$FIX/repoEmpty" config --local core.hooksPath .githooks

# repoDeliberate: hooksPath dir carries a real (non-.sample) hook file.
mkdir -p "$FIX/repoDeliberate/.githooks"
printf '#!/bin/sh\nexit 0\n' > "$FIX/repoDeliberate/.githooks/pre-commit"
chmod +x "$FIX/repoDeliberate/.githooks/pre-commit"
git -C "$FIX/repoDeliberate" config --local core.hooksPath .githooks

# repoClean: no local core.hooksPath set at all (the correct/default state).

cat > "$FIX/relay.toml" <<EOF
[repos.repoEmpty]
classification = "own"
path = "$FIX/repoEmpty"
[repos.repoDeliberate]
classification = "own"
path = "$FIX/repoDeliberate"
[repos.repoClean]
classification = "own"
path = "$FIX/repoClean"
EOF

run() { RELAY_TOML="$FIX/relay.toml" SRC_DIR="$FIX" HOOKS_PATH_SHADOW_LOG="$FIX/scan.log" "$SH" "$@" 2>"$FIX/stderr"; }

rc=0; out="$(run)" || rc=$?
[[ "$rc" -eq 0 ]] || fail "report-only must exit 0 with findings; got $rc
$out
stderr: $(cat "$FIX/stderr")"
pass "report-only (exit 0 with findings)"

# (1) exactly one EMPTY-SHADOW row, naming repoEmpty.
n_empty="$(grep -c '^EMPTY-SHADOW repoEmpty ' <<<"$out" || true)"
[[ "$n_empty" -eq 1 ]] || fail "(1) expected exactly one EMPTY-SHADOW repoEmpty row, got $n_empty
$out"
pass "(1) repoEmpty classified EMPTY-SHADOW"

# (2) exactly one DELIBERATE row, naming repoDeliberate.
n_delib="$(grep -c '^DELIBERATE repoDeliberate ' <<<"$out" || true)"
[[ "$n_delib" -eq 1 ]] || fail "(2) expected exactly one DELIBERATE repoDeliberate row, got $n_delib
$out"
pass "(2) repoDeliberate classified DELIBERATE"

# (3) repoClean gets NO row at all (neither EMPTY-SHADOW nor DELIBERATE) — a
#     positive-only detector that flags everything must not pass this.
grep -q 'repoClean' <<<"$out" && fail "(3) repoClean must not appear in any finding row:
$out"
pass "(3) repoClean produces no row"

# (4) repoDeliberate must NOT also appear as EMPTY-SHADOW, and vice versa.
grep -q '^EMPTY-SHADOW repoDeliberate ' <<<"$out" && fail "(4) repoDeliberate wrongly also flagged EMPTY-SHADOW:
$out"
grep -q '^DELIBERATE repoEmpty ' <<<"$out" && fail "(4) repoEmpty wrongly also flagged DELIBERATE:
$out"
pass "(4) classifications are mutually exclusive per repo"

# (5) a repo whose `# path:` override relocates it is still enumerated (via
#     own_repos, not a glob) — move repoClean's fixture dir and re-point via the
#     comment override instead of the `path =` key.
RELOC="$FIX/relocated-clean"
mv "$FIX/repoClean" "$RELOC"
cat > "$FIX/relay2.toml" <<EOF
[repos.repoEmpty]
classification = "own"
path = "$FIX/repoEmpty"
[repos.repoDeliberate]
classification = "own"
path = "$FIX/repoDeliberate"
[repos.repoClean]
classification = "own"
# path: $RELOC
EOF
rc=0
out2="$(RELAY_TOML="$FIX/relay2.toml" SRC_DIR="$FIX" HOOKS_PATH_SHADOW_LOG="$FIX/scan2.log" "$SH" 2>"$FIX/stderr2")" || rc=$?
[[ "$rc" -eq 0 ]] || fail "(5) run with # path: override must exit 0; got $rc
stderr: $(cat "$FIX/stderr2")"
grep -q 'SKIP repoClean' <<<"$out2" && fail "(5) repoClean via # path: override must resolve on disk, not SKIP:
$out2
stderr: $(cat "$FIX/stderr2")"
grep -q '3 own repo(s) scanned' <<<"$out2" || fail "(5) expected 3 own repos scanned (path: override honored), got:
$out2"
pass "(5) # path: override repo still enumerated via own_repos"

echo ok

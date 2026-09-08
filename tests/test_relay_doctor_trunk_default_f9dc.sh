#!/usr/bin/env bash
# roadmap:f9dc — relay-doctor's trunk-vs-default check is INFORMATIONAL and silent by default.
#
# The point of this check is what it does NOT say. A trunk that differs from origin/HEAD is a
# SUPPORTED configuration (trunk-branch.sh:12-13 exists because ai-codebench works on
# claude/opusplan while main is frozen), so the failure mode to guard is a check that cries
# wolf -- on a repo with no origin/HEAD, or on one whose divergence is already declared.
#
# Hermetic: builds fixture repos under mktemp, points RELAY_TOML and SRC_DIR at them, and
# never reads the real ~/.config/relay/relay.toml or any repo under ~/src.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR="$ROOT/relay/scripts/relay-doctor.sh"
fails=0
ok()   { echo "ok: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

[ -x "$DOCTOR" ] || { echo "ERROR: relay-doctor.sh not executable at $DOCTOR"; exit 3; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export GIT_CEILING_DIRECTORIES="$TMP"

# mkrepo <name> <trunk-branch> <set-origin-head:yes|no>
mkrepo() {
  # Declared separately on purpose: referencing $name inside the SAME `local` that declares
  # it is unbound under `set -u` (bash binds the whole statement's names after evaluating it).
  local name="$1" trunk="$2" sethead="$3"
  local d="$TMP/src/$name"
  mkdir -p "$d"
  git -C "$d" init -q -b "$trunk" 2>/dev/null
  git -C "$d" config user.email t@example.invalid
  git -C "$d" config user.name  T
  # Point hooksPath at an empty dir: the GLOBAL core.hooksPath would otherwise run the
  # fleet's pre-commit hooks against these fixtures and print no-op noise into the suite.
  mkdir -p "$TMP/nohooks"
  git -C "$d" config core.hooksPath "$TMP/nohooks"
  echo x >"$d/f"; git -C "$d" add f; git -C "$d" commit -qm init
  # A bare "remote" so origin/HEAD can be set meaningfully.
  git init -q --bare "$TMP/remotes/$name.git" 2>/dev/null
  git -C "$d" remote add origin "$TMP/remotes/$name.git"
  git -C "$d" push -q origin "$trunk" 2>/dev/null
  if [ "$sethead" = yes ]; then
    # Declare the remote default to be `main` specifically.
    git -C "$d" branch -q main 2>/dev/null || true
    git -C "$d" push -q origin main 2>/dev/null || true
    git -C "$d" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main 2>/dev/null || true
  fi
}

mkdir -p "$TMP/src" "$TMP/remotes"
mkrepo agree    main            yes   # trunk == origin/HEAD  -> silent
mkrepo diverge  feature/wip     yes   # trunk != origin/HEAD  -> reported
mkrepo nohead   feature/wip     no    # no origin/HEAD        -> SILENT (absence != divergence)

TOML="$TMP/relay.toml"
cat >"$TOML" <<EOF
[repos.agree]
classification = "own"
[repos.diverge]
classification = "own"
[repos.nohead]
classification = "own"
EOF

run_check() { RELAY_TOML="$TOML" SRC_DIR="$TMP/src" bash "$DOCTOR" --only trunk-vs-default 2>/dev/null; }

out="$(run_check)"

# (1) The diverging repo is reported, and the message names BOTH branches -- a bare
#     "branch mismatch" would not tell a reader where their writes actually land.
case "$out" in
  *"TRUNK-OFF-DEFAULT diverge"*) ok "(1) diverging repo is reported" ;;
  *) fail "(1) expected TRUNK-OFF-DEFAULT for 'diverge'; got: $out" ;;
esac
case "$out" in
  *'trunk="feature/wip"'*'origin/HEAD="main"'*) ok "(1) message names both branches" ;;
  *) fail "(1) message did not name both trunk and origin/HEAD" ;;
esac

# (2) The agreeing repo is silent.
case "$out" in
  *"TRUNK-OFF-DEFAULT agree"*) fail "(2) repo whose trunk MATCHES origin/HEAD was reported" ;;
  *) ok "(2) agreeing repo stays silent" ;;
esac

# (3) THE ONE THAT MATTERS: no origin/HEAD => silent. Absence of a declared default is not
#     divergence, and guessing `main` is the id:758a anti-pattern.
case "$out" in
  *"nohead"*) fail "(3) repo with NO origin/HEAD was reported -- absence is not divergence" ;;
  *) ok "(3) repo with no origin/HEAD stays silent" ;;
esac

# (4) A matching declaration suppresses the report.
cat >>"$TOML" <<'EOF'
trunk_intentional = "feature/wip"
EOF
# (appended under [repos.nohead]; move it to diverge properly)
cat >"$TOML" <<EOF
[repos.agree]
classification = "own"
[repos.diverge]
classification = "own"
trunk_intentional = "feature/wip"
[repos.nohead]
classification = "own"
EOF
out="$(run_check)"
case "$out" in
  *"TRUNK-OFF-DEFAULT diverge"*) fail "(4) declared-intentional trunk was still reported" ;;
  *) ok "(4) matching declaration suppresses the report" ;;
esac

# (5) A STALE declaration is reported LOUDER, not silently honoured. An exemption that no
#     longer describes reality is worse than none -- it hides a real divergence forever.
cat >"$TOML" <<EOF
[repos.agree]
classification = "own"
[repos.diverge]
classification = "own"
trunk_intentional = "some/oldbranch"
[repos.nohead]
classification = "own"
EOF
out="$(run_check)"
case "$out" in
  *"STALE-DECLARATION diverge"*) ok "(5) stale declaration is reported as stale" ;;
  *) fail "(5) stale trunk_intentional was not reported; got: $out" ;;
esac

# (6) Report-only: relay-doctor still exits 0 with findings present.
RELAY_TOML="$TOML" SRC_DIR="$TMP/src" bash "$DOCTOR" --only trunk-vs-default >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "(6) report-only: exits 0 despite findings" || fail "(6) expected exit 0, got $rc"

# (7) Wiring: the check name is in the vocabulary AND dispatched (an unwired check is the
#     one failure mode relay-doctor's own coverage rule calls out).
grep -q 'trunk-vs-default' "$DOCTOR" && ok "(7) name present in relay-doctor.sh" \
  || fail "(7) trunk-vs-default missing from relay-doctor.sh"
grep -q 'if want trunk-vs-default;' "$DOCTOR" && ok "(7) dispatched in the once-only block" \
  || fail "(7) trunk-vs-default declared but never dispatched"

[ "$fails" -eq 0 ] && { echo "PASS test_relay_doctor_trunk_default_f9dc"; exit 0; }
echo "$fails assertion(s) failed"; exit 1

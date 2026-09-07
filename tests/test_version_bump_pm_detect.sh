#!/usr/bin/env bash
# Defect-fix test (no `# roadmap:` header — this pins a live incident, not a queued item, so its
# failures ALWAYS count). Specs the node package-manager detection in relay/scripts/version-bump.sh.
#
# INCIDENT (2026-09-07, relay run relay-20260907-100619-27900): version-bump.sh hardcoded
# `package-lock.json` + `npm install --package-lock-only` for EVERY package.json repo. zkWhale is a
# pnpm workspace (pnpm-lock.yaml + pnpm-workspace.yaml), so npm died with "Cannot read properties of
# null (reading 'matches')" AFTER the manifest had already been rewritten. The bump half-applied:
# package.json moved 0.2.1 -> 0.3.0, the lockfile did not, and the tree was left dirty. That dirty
# tree then tripped the id:aa93 clean-tree gate on the next THREE zkWhale integrates and stranded
# four branches carrying real e2e work (id:c14b, id:2147). Had npm instead SUCCEEDED, the damage
# would have been quieter and worse: a second, wrong package-lock.json committed beside the
# authoritative pnpm-lock.yaml.
#
# What is pinned here, and why each half matters:
#   (a) pnpm-lock.yaml present -> the DEFAULT lock command is pnpm's, and pnpm-lock.yaml is the
#       file staged. Asserting only "the bump succeeded" would pass against the pre-fix tree the
#       moment a stubbed npm happened to exit 0, so the test asserts WHICH binary was invoked.
#   (b) npm is NEVER invoked in a pnpm repo. This is the assertion that actually discriminates:
#       (a) alone could be satisfied by a script that runs both.
#   (c) yarn.lock present -> LOUD refusal, exit 1, manifest UNCHANGED. The lockfile-only
#       invocation differs between yarn classic and berry; guessing re-creates this very bug, so
#       refusing is the fix. The manifest-unchanged half is the point — the incident's real harm
#       was a rewritten manifest with no matching lock, so a refusal that still edited
#       package.json would reproduce it under a different name.
#   (d) plain package-lock.json still gets npm — the fix must not regress the common case.
#
# fails-against-mutation: sed -i 's|if \[\[ -f "$repo/pnpm-lock.yaml" \]\]; then|if false; then|' relay/scripts/version-bump.sh
# fails-against-assertion: (b) npm was invoked in a pnpm repo
#   Rationale: under the mutation, detection falls through to the npm branch and THREE assertions
#   fire — (a), (a3) and (b). The convention requires the declaration to match the LAST emitted
#   FAIL line (matching any-of would degrade the guarantee to little more than exit status), so the
#   (a2-a4) block is deliberately ordered BEFORE (b) to make (b) last. (b) is also the assertion
#   that names the actual defect — a wrong command RUN, not merely a wrong filename recorded —
#   which is why it is worth ordering the file around rather than pinning (a3) by accident.
#   Verified both ways on 2026-09-07: green on the fixed tree, and red at (b)-last under the
#   mutation above.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VB="$ROOT/relay/scripts/version-bump.sh"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; FAILED=1; }
FAILED=0

[[ -x "$VB" ]] || { echo "FAIL: version-bump.sh not found/executable at $VB"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── PATH stubs: record which package manager the script actually invokes. ─────────────────
# Each stub appends its name to $TMP/calls and writes the lockfile it owns, so the real
# network-dependent tools are never run and "who was called" is observable.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/pnpm" <<'EOF'
#!/usr/bin/env bash
echo "pnpm $*" >> "$CALLS"
printf 'lockfileVersion: fake\n' > pnpm-lock.yaml
EOF
cat > "$TMP/bin/npm" <<'EOF'
#!/usr/bin/env bash
echo "npm $*" >> "$CALLS"
printf '{"lockfileVersion":0}\n' > package-lock.json
EOF
chmod +x "$TMP/bin/pnpm" "$TMP/bin/npm"
export PATH="$TMP/bin:$PATH"

mkrepo() { # mkrepo <name> <lockfile-name> -> path (git repo, package.json 0.2.1, that lockfile)
  local r="$TMP/$1" lock="$2"
  mkdir -p "$r"
  git -C "$r" init -q
  git -C "$r" config user.email t@e.st
  git -C "$r" config user.name t
  git -C "$r" config commit.gpgsign false
  git -C "$r" config tag.gpgsign false
  printf '{\n  "name": "x",\n  "version": "0.2.1"\n}\n' > "$r/package.json"
  [[ -n "$lock" ]] && printf 'pre-existing\n' > "$r/$lock"
  git -C "$r" add -A; git -C "$r" commit -qm init
  printf '%s' "$r"
}

ver_of() { grep -m1 -oE '"version"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' "$1/package.json" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'; }

# ── (a)/(b) pnpm workspace: pnpm is chosen, npm is never run, pnpm-lock.yaml is committed. ──
R1="$(mkrepo pnpmrepo pnpm-lock.yaml)"
export CALLS="$TMP/calls1"; : > "$CALLS"
out="$(cd "$R1" && "$VB" "$R1" --level minor 2>"$TMP/err1")"; rc=$?

if [[ $rc -ne 0 ]]; then
  fail "(a) pnpm repo: bump exited $rc, expected 0 -- stderr: $(tr '\n' ' ' < "$TMP/err1")"
elif ! grep -q '^pnpm ' "$CALLS"; then
  fail "(a) pnpm was NOT invoked in a pnpm repo (calls: $(tr '\n' ';' < "$CALLS" || true))"
else
  pass "(a) pnpm repo -> pnpm invoked, bump returned '$out'"
fi

# The tree must be CLEAN and the pnpm lockfile must be in the bump commit (bump-includes-lockfile).
# Ordered BEFORE (b) deliberately: see the fails-against-assertion note in the header — the
# declaration must match the LAST FAIL line, and (b) is the one that names the actual defect.
# Captured first, not piped: `producer | grep -q` under `pipefail` is the id:81d5 SIGPIPE shape
# the repo lints against (grep -q exits at the first match and SIGPIPEs the producer).
bump_files="$(git -C "$R1" show --name-only --format= HEAD)"
if [[ -n "$(git -C "$R1" status --porcelain)" ]]; then
  fail "(a2) pnpm repo left DIRTY after bump -- this is what tripped the id:aa93 clean-tree gate"
elif ! grep -qx 'pnpm-lock.yaml' <<<"$bump_files"; then
  fail "(a3) pnpm-lock.yaml not part of the bump commit (files: $(tr '\n' ' ' <<<"$bump_files"))"
elif grep -qx 'package-lock.json' <<<"$bump_files"; then
  fail "(a4) a WRONG package-lock.json was committed beside pnpm-lock.yaml"
else
  pass "(a2-a4) tree clean; pnpm-lock.yaml committed; no stray package-lock.json"
fi

if grep -q '^npm ' "$CALLS"; then
  fail "(b) npm was invoked in a pnpm repo (calls: $(tr '\n' ';' < "$CALLS")) -- this is the 2026-09-07 zkWhale defect"
else
  pass "(b) npm never invoked in a pnpm repo"
fi

# ── (c) yarn: LOUD refusal, exit 1, manifest untouched. ──────────────────────────────────
R2="$(mkrepo yarnrepo yarn.lock)"
export CALLS="$TMP/calls2"; : > "$CALLS"
(cd "$R2" && "$VB" "$R2" --level minor >/dev/null 2>"$TMP/err2"); rc=$?

if [[ $rc -eq 0 ]]; then
  fail "(c) yarn repo: expected a loud refusal (nonzero), got exit 0"
elif ! grep -qi 'yarn' "$TMP/err2"; then
  fail "(c) yarn refusal did not name yarn on stderr: $(tr '\n' ' ' < "$TMP/err2")"
elif [[ "$(ver_of "$R2")" != "0.2.1" ]]; then
  fail "(c) yarn repo: manifest was REWRITTEN to $(ver_of "$R2") despite the refusal -- reproduces the half-applied-bump incident"
else
  pass "(c) yarn repo -> loud refusal, exit $rc, manifest still 0.2.1"
fi

# ── (d) plain npm repo still uses npm (no regression on the common case). ────────────────
R3="$(mkrepo npmrepo package-lock.json)"
export CALLS="$TMP/calls3"; : > "$CALLS"
out3="$(cd "$R3" && "$VB" "$R3" --level patch 2>"$TMP/err3")"; rc=$?

if [[ $rc -ne 0 ]]; then
  fail "(d) npm repo: bump exited $rc, expected 0 -- stderr: $(tr '\n' ' ' < "$TMP/err3")"
elif ! grep -q '^npm ' "$CALLS"; then
  fail "(d) npm was NOT invoked in a package-lock.json repo (calls: $(tr '\n' ';' < "$CALLS" || true))"
elif [[ "$out3" != "v0.2.2" ]]; then
  fail "(d) expected stdout 'v0.2.2' for a patch bump, got '$out3'"
else
  pass "(d) package-lock.json repo -> npm invoked, patch bump '$out3'"
fi

[[ $FAILED -eq 0 ]] || exit 1
echo "ALL PASS: version-bump.sh node package-manager detection"

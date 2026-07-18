#!/usr/bin/env bash
# Specs TODO id:b8fa — the CHANGELOG deriver (`relay/scripts/changelog-append.sh`).
# (No `# roadmap:XXXX` header: b8fa is a TODO/design id, not a ROADMAP queue item; this is a
#  /meeting Class-1 inline impl, so the test must end GREEN — it is not expected-red.)
#
# Design (meeting docs/meeting-notes/2026-07-17-1541-semver-trigger-and-fleet-changelog.md):
#   D2 — the CHANGELOG entry is DERIVED at integrate from existing relay state (summary +
#        worked ids); it must NOT require any new per-item field (that would be authoring).
#   D3 — dotclaude-skills (and any version-less repo) is DATE-bucketed, no version.
#   D4 — semver repos are RELEASE-bucketed; changelog must not fire on them before the bump
#        (e647) works. Enforced here by the OPT-IN gate: the helper is a NO-OP unless the
#        repo already has a CHANGELOG.md, so a semver repo is untouched until e647 bootstraps it.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CL="$ROOT/relay/scripts/changelog-append.sh"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$CL" ]] || fail "changelog-append.sh not found/executable at $CL"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkrepo() { # mkrepo <name> -> path (a git repo, no CHANGELOG.md yet)
  local r="$TMP/$1"
  mkdir -p "$r"
  git -C "$r" init -q
  git -C "$r" config user.email t@e.st
  git -C "$r" config user.name t
  echo x > "$r/f"; git -C "$r" add -A; git -C "$r" commit -qm init
  printf '%s' "$r"
}

# (1) AUTO-ONBOARD on first release (id:7d20 option B): absent CHANGELOG.md + --version
#     (a real bump happened) -> CREATE the release-bucketed file and record the entry. This
#     retires the now-moot D4 opt-in gate FOR THE BUMP CASE ONLY (e647 shipped; the gate's
#     "don't fire before e647" constraint has lapsed).
R1="$(mkrepo semver_firstrelease)"
"$CL" "$R1" --summary "First public release" --ids "aa11" --version v0.1.0 --date 2026-07-18 >/dev/null 2>&1 \
  || fail "(1) helper must succeed (auto-onboard) when CHANGELOG.md is absent but --version is given"
[[ -f "$R1/CHANGELOG.md" ]] \
  || fail "(1) absent CHANGELOG.md + --version must AUTO-CREATE the file (7d20 B: first release self-onboards)"
grep -qxF '## v0.1.0 — 2026-07-18' "$R1/CHANGELOG.md" \
  || fail "(1) auto-created CHANGELOG.md missing the release bucket for the first release"
grep -qF -- '- First public release (id:aa11)' "$R1/CHANGELOG.md" \
  || fail "(1) auto-created CHANGELOG.md missing the first-release bullet"
pass "(1) auto-onboard: absent + --version -> creates release-bucketed CHANGELOG.md (7d20 B)"

# (1b) VERSION-LESS opt-in PRESERVED (D3): absent CHANGELOG.md + NO --version -> still a NO-OP,
#      file NOT created. Manifest-less repos (e.g. dotclaude-skills) stay a DELIBERATE bootstrap;
#      only a real release auto-onboards.
R1b="$(mkrepo versionless_norepo)"
"$CL" "$R1b" --summary "internal refactor, no release" --date 2026-07-18 >/dev/null 2>&1 \
  || fail "(1b) helper must exit 0 (no-op) when CHANGELOG.md is absent and no --version"
[[ ! -e "$R1b/CHANGELOG.md" ]] \
  || fail "(1b) absent + NO --version must stay opt-in (no file) — version-less repos are never auto-created (D3)"
pass "(1b) version-less opt-in preserved: absent + no --version -> no-op, no file (D3)"

# (2) DATE bucket (D3): version-less call appends under a `## YYYY-MM-DD` header, no version.
R2="$(mkrepo daterepo)"
printf '# Changelog\n\n<!-- derived; newest first -->\n' > "$R2/CHANGELOG.md"
"$CL" "$R2" --summary "Add the widget flow" --ids "a1b2,c3d4" --date 2026-07-18 >/dev/null \
  || fail "(2) helper failed on a date-bucketed (version-less) repo"
grep -qxF '## 2026-07-18' "$R2/CHANGELOG.md" \
  || fail "(2) no '## 2026-07-18' date bucket header written"
grep -qF -- '- Add the widget flow (id:a1b2,c3d4)' "$R2/CHANGELOG.md" \
  || fail "(2) bullet with summary + worked ids not written verbatim"
grep -qE '^## v[0-9]' "$R2/CHANGELOG.md" \
  && fail "(2) a version header appeared in a version-less repo (D3 violation)"
pass "(2) date bucket: '## YYYY-MM-DD' + '- <summary> (id:<ids>)', no version (D3)"

# (3) MERGE same-key bucket: a second same-date call adds a bullet to the SAME header (not a 2nd).
"$CL" "$R2" --summary "Fix the frobnicator" --ids "e5f6" --date 2026-07-18 >/dev/null \
  || fail "(3) second same-date append failed"
[[ "$(grep -cxF '## 2026-07-18' "$R2/CHANGELOG.md")" == "1" ]] \
  || fail "(3) same-date append created a DUPLICATE date header (must merge into one bucket)"
grep -qF -- '- Fix the frobnicator (id:e5f6)' "$R2/CHANGELOG.md" \
  || fail "(3) second bullet not present under the merged date bucket"
pass "(3) same-date append merges into one bucket (no duplicate header)"

# (4) NEWEST-FIRST insertion: a new (distinct-key) bucket lands ABOVE an older one.
"$CL" "$R2" --summary "Later change" --date 2026-07-19 >/dev/null \
  || fail "(4) newer-date append failed"
new_ln="$(grep -nxF '## 2026-07-19' "$R2/CHANGELOG.md" | head -1 | cut -d: -f1)"
old_ln="$(grep -nxF '## 2026-07-18' "$R2/CHANGELOG.md" | head -1 | cut -d: -f1)"
[[ -n "$new_ln" && -n "$old_ln" && "$new_ln" -lt "$old_ln" ]] \
  || fail "(4) newest bucket ($new_ln) not inserted above the older one ($old_ln) — newest-first broken"
pass "(4) new bucket inserted newest-first (above older buckets, below the preamble)"

# (5) RELEASE bucket (D4 semver path): --version yields a '## vX.Y.Z — DATE' header.
R5="$(mkrepo semverrepo)"
printf '# Changelog\n' > "$R5/CHANGELOG.md"
"$CL" "$R5" --summary "Ship export" --ids "9999" --version v0.4.0 --date 2026-07-18 >/dev/null \
  || fail "(5) release-bucketed append failed"
grep -qxF '## v0.4.0 — 2026-07-18' "$R5/CHANGELOG.md" \
  || fail "(5) no '## v0.4.0 — YYYY-MM-DD' release bucket header"
grep -qF -- '- Ship export (id:9999)' "$R5/CHANGELOG.md" \
  || fail "(5) release bullet not written"
# a second close under the SAME version merges (release-bucketed by version token, tolerant of date)
"$CL" "$R5" --summary "Another export tweak" --version v0.4.0 --date 2026-07-19 >/dev/null \
  || fail "(5b) same-version second append failed"
[[ "$(grep -cE '^## v0\.4\.0' "$R5/CHANGELOG.md")" == "1" ]] \
  || fail "(5b) same-version append duplicated the version header (must merge by version token)"
grep -qF -- '- Another export tweak' "$R5/CHANGELOG.md" \
  || fail "(5b) second same-version bullet missing"
pass "(5) release bucket: '## vX.Y.Z — DATE', merges by version token (semver path)"

# (6) D2 GUARD — reads ONLY existing state: an empty summary is a loud error, never a fabricated
#     entry (the deriver must not invent content; the summary IS the relay's own report.summary).
R6="$(mkrepo guardrepo)"
printf '# Changelog\n' > "$R6/CHANGELOG.md"
if "$CL" "$R6" --summary "" --date 2026-07-18 >/dev/null 2>&1; then
  fail "(6) empty summary accepted — must fail loudly, never write a fabricated/blank entry (D2)"
fi
grep -qE '^- ' "$R6/CHANGELOG.md" \
  && fail "(6) a bullet was written despite the empty-summary rejection (D2)"
pass "(6) D2 guard: empty summary rejected, nothing fabricated"

# (7) INTEGRATOR wiring: relay-loop.js must invoke changelog-append.sh in the integrate chain,
#     passing the summary + worked ids (D2 derive-at-integrate). Static check (live integration
#     is agent-driven — see the id:83c9 structure-test rationale).
JS="$ROOT/relay/scripts/relay-loop.js"
grep -q 'changelog-append.sh' "$JS" \
  || fail "(7) relay-loop.js integrator never invokes changelog-append.sh (b8fa not wired)"
pass "(7) integrator wiring: relay-loop.js invokes changelog-append.sh"

# (8) node --check still passes after the integrator-prompt edit (guard the template edit).
node --check "$JS" >/dev/null 2>&1 || fail "(8) relay-loop.js fails node --check after wiring edit"
pass "(8) relay-loop.js still parses (node --check) after the integrator edit"

echo "ALL PASS: id:b8fa changelog-append.sh deriver + integrator wiring"

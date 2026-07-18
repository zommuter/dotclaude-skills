#!/usr/bin/env bash
# changelog-append.sh — DERIVE one CHANGELOG entry at relay integrate (id:b8fa).
#
# The relay integrator already knows every close: report.summary + the worked item ids. This
# helper folds that into <repo>/CHANGELOG.md — no new per-item field, no authoring (meeting
# 2026-07-17-1541 D2). Bucketing:
#   • --version vX.Y.Z  → release bucket  `## vX.Y.Z — YYYY-MM-DD`  (semver repos; the version
#                         comes from the e647 bump, decided by the reviewer at integrate).
#   • no --version      → date bucket     `## YYYY-MM-DD`          (version-less repos, e.g.
#                         dotclaude-skills, which has NO version by design — id:8ef3/D3).
#
# OPT-IN by construction (D4 semver safety): if <repo>/CHANGELOG.md does NOT already exist this
# is a logged NO-OP. So the integrator may call it for every repo unconditionally — a repo only
# gets a changelog once it has been deliberately bootstrapped (dotclaude-skills now; each semver
# repo when e647 ships and creates its file). This is why the changelog can never fire on a
# semver repo before the bump trigger exists.
#
# Usage:
#   changelog-append.sh <repo-path> --summary "<text>" [--ids "a1,b2"] [--version vX.Y.Z] [--date YYYY-MM-DD]
#
# Buckets are newest-first (a new bucket lands just below the file preamble, above older
# buckets); a repeat call under the same key merges its bullet into the existing bucket. Writes
# are flock-guarded on <repo>/.changelog.lock (matches the *.lock gitignore) and atomic
# (temp-file rename). Prints the bucket key to stdout; short note to stderr on a no-op.
set -euo pipefail

repo="${1:?Usage: changelog-append.sh <repo-path> --summary <text> [--ids csv] [--version vX.Y.Z] [--date YYYY-MM-DD]}"
shift

summary=""
ids=""
version=""
date=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --summary) summary="${2:?--summary needs a value}"; shift 2 ;;
    --ids)     ids="${2:-}"; shift 2 ;;
    --version) version="${2:-}"; shift 2 ;;
    --date)    date="${2:-}"; shift 2 ;;
    *) echo "changelog-append.sh: unknown arg '$1'" >&2; exit 1 ;;
  esac
done

[[ -n "$summary" ]] || { echo "changelog-append.sh: empty --summary (a derived entry must carry the relay's own report.summary; refusing to fabricate)" >&2; exit 1; }

[[ -n "$date" ]] || date="$(date +%F)"

cl="$repo/CHANGELOG.md"
# OPT-IN gate (id:b8fa) + AUTO-ONBOARD on first release (id:7d20 option B).
# A repo without a CHANGELOG.md normally no-ops (opt-in). EXCEPTION: when --version is supplied
# — a real release just bumped the manifest (id:e647) — auto-CREATE the release-bucketed file so
# a semver repo's FIRST release self-onboards its changelog with no manual bootstrap. This
# retires the D4 opt-in gate FOR THE BUMP CASE ONLY: D4's constraint ("don't fire before e647
# ships") has lapsed now that e647 is live. A version-less close (no --version) KEEPS the opt-in
# no-op — manifest-less repos (e.g. dotclaude-skills, D3) stay a deliberate bootstrap, never
# auto-created on a mere non-release close.
if [[ ! -f "$cl" ]]; then
  if [[ -z "$version" ]]; then
    echo "changelog-append.sh: note: $repo has no CHANGELOG.md — skipping (opt-in; bootstrap the file to enable)" >&2
    exit 0
  fi
  cat > "$cl" <<'HDR'
# Changelog

<!-- DERIVED at relay integrate from existing relay state (report.summary + worked ids) by
     relay/scripts/changelog-append.sh (id:b8fa). Newest release first; never hand-edit or
     reorder past buckets. RELEASE-bucketed by version (## vX.Y.Z — DATE) — the reviewer's bump
     at integrate (id:e647) supplies the version. Auto-onboarded on this repo's first release
     (id:7d20). Started from now; history is NOT backfilled. -->
HDR
  echo "changelog-append.sh: note: $repo — auto-created CHANGELOG.md on first release ($version, id:7d20)" >&2
fi

if [[ -n "$version" ]]; then
  key="$version — $date"        # release bucket header text (after "## ")
  match_prefix="$version"       # merge by version token, tolerant of the " — DATE" suffix
else
  key="$date"                   # date bucket
  match_prefix=""               # exact-key match only
fi

bullet="- $summary"
[[ -n "$ids" ]] && bullet="$bullet (id:$ids)"

lockfile="$repo/.changelog.lock"
(
  flock -x 9
  CL="$cl" KEY="$key" MATCH_PREFIX="$match_prefix" BULLET="$bullet" python3 - <<'PY'
import os, tempfile

path   = os.environ["CL"]
key    = os.environ["KEY"]            # header text after "## "
prefix = os.environ["MATCH_PREFIX"]   # non-empty => version-token merge
bullet = os.environ["BULLET"]

with open(path, "r", encoding="utf-8") as fh:
    lines = fh.read().split("\n")
# Preserve a single trailing blank produced by a file ending in "\n"
trailing_nl = lines and lines[-1] == ""
if trailing_nl:
    lines = lines[:-1]

def is_header(ln):
    return ln.startswith("## ")

def matches(ln):
    if not is_header(ln):
        return False
    body = ln[3:].strip()
    if prefix:                                   # version bucket: match the token, any date
        return body == prefix or body.startswith(prefix + " ")
    return body == key                           # date bucket: exact

# Find an existing bucket with this key.
hdr_idx = next((i for i, ln in enumerate(lines) if matches(ln)), None)

if hdr_idx is not None:
    # Append the bullet as the last entry of that bucket (before the next "## " or EOF),
    # trimming trailing blanks inside the bucket so the bullet list stays contiguous.
    end = next((j for j in range(hdr_idx + 1, len(lines)) if is_header(lines[j])), len(lines))
    ins = end
    while ins > hdr_idx + 1 and lines[ins - 1].strip() == "":
        ins -= 1
    lines[ins:ins] = [bullet]
else:
    # New bucket, newest-first: insert just below the preamble (before the first existing
    # "## " header; if none, after the leading header/comment/blank block at EOF).
    first_hdr = next((i for i, ln in enumerate(lines) if is_header(ln)), None)
    block = ["## " + key, "", bullet]
    if first_hdr is not None:
        lines[first_hdr:first_hdr] = block + [""]
    else:
        # No buckets yet: append after the preamble, guaranteeing one blank separator.
        while lines and lines[-1].strip() == "":
            lines.pop()
        lines += ([""] if lines else []) + block

out = "\n".join(lines) + ("\n" if trailing_nl or lines else "")
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".", prefix=".changelog.")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(out)
    os.replace(tmp, path)
except BaseException:
    os.unlink(tmp)
    raise
PY
) 9>"$lockfile"

echo "$key"

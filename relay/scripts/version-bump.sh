#!/usr/bin/env bash
# version-bump.sh — the reviewer-at-integrate SemVer bump (TODO id:e647).
#
# Standing rule (meeting docs/meeting-notes/2026-07-17-1541-semver-trigger-and-fleet-changelog.md,
# D1): the RELAY REVIEWER bumps a repo's version at integrate, ONCE per user-observable close.
# The executor NEVER bumps — parallel worktrees collide on the manifest + lockfile. So this helper
# is invoked only from the serialized integrator (relay-loop.js), on the main checkout, after the
# child's branch has merged.
#
# The level is an INPUT, not computed: "user-observable" is a JUDGEMENT the reviewer makes (Riku,
# D1) — a refactor-only close must NOT bump at all, so the integrator only calls this for a close
# it has decided is user-observable, and passes --level minor|patch. loose-0.x (global CLAUDE.md
# §Versioning): patch = z+1; minor = y+1, z=0; MAJOR is never touched here.
#
# Usage:
#   version-bump.sh <repo-path> --level minor|patch [--date YYYY-MM-DD]
#     (--date is accepted for symmetry with changelog-append.sh / annotated-tag messages; the
#      bump commit itself uses the repo's own commit timestamp.)
#
# Behaviour:
#   • Manifest detection: pyproject.toml (`version = "X.Y.Z"`) FIRST, then package.json
#     (`"version": "X.Y.Z"`). NO manifest -> logged NO-OP, exit 0. This is how version-less repos
#     (dotclaude-skills et al.) stay exempt BY CONSTRUCTION — no special case (mirrors the opt-in
#     style of changelog-append.sh).
#   • Rewrites ONLY the version line in the manifest (exact-line edit, never a full rewrite).
#   • Regenerates the lockfile IN-REPO via an INJECTABLE command ($VERSION_BUMP_LOCK_CMD — default
#     `uv lock` for pyproject / `npm install --package-lock-only` for package.json) so the test can
#     stub it (a real `uv lock` needs network+deps). If no lockfile exists after regen, staging it
#     is skipped (fine).
#   • zkm cascade (finding c): if <repo>/scripts/relock-plugins.sh exists, INVOKE it — never
#     re-implement the ~18-plugin uv.lock cascade (a hand-rolled loop once relocked but skipped the
#     commits, leaving 17 repos dirty). Its args are injectable via $VERSION_BUMP_CASCADE_ARGS
#     (default: --push). The plugin uv.locks live in SEPARATE sub-repos, so the cascade does not
#     dirty THIS repo's tree.
#   • Commits manifest + lockfile TOGETHER (scoped `git add -- <path>`, never -A/./-u/--all — the
#     id:debf scoped-staging invariant), leaving the tree CLEAN so clean-tree-gate.sh does not
#     defer the repo (the failure D1's dissent named).
#   • Creates an ANNOTATED tag vX.Y.Z on the bump commit. WHY annotated + WHY here: finding (b)
#     records that zkm's autotag hook makes LIGHTWEIGHT tags, which `git describe` silently skips
#     without --tags (it reported v0.2.0 on a HEAD tagged v0.21.0). The bump-and-tag rule wants the
#     tag in the SAME commit; doing it atomically here — annotated, so EVERY reader finds it — keeps
#     bump+tag coupled and hermetically testable rather than leaving a window where the integrator
#     might tag lightweight or not at all.
#
# Prints the new version `vX.Y.Z` to stdout (the integrator captures it and passes it on to
# changelog-append.sh --version for release-bucketing). Details go to stderr. flock-guarded on
# <gitdir>/version-bump.lock (matches the *.lock gitignore convention).
set -euo pipefail

repo="${1:?Usage: version-bump.sh <repo-path> --level minor|patch [--date YYYY-MM-DD]}"
shift

level=""
date=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --level) level="${2:?--level needs minor|patch}"; shift 2 ;;
    --date)  date="${2:-}"; shift 2 ;;
    *) echo "version-bump.sh: unknown arg '$1'" >&2; exit 1 ;;
  esac
done

case "$level" in
  minor|patch) ;;
  *) echo "version-bump.sh: --level must be 'minor' or 'patch' (got '$level'); the reviewer decides it — it is NOT derivable (D1)" >&2; exit 1 ;;
esac

git -C "$repo" rev-parse --git-dir >/dev/null

# ── Manifest detection: pyproject.toml first, then package.json. ──────────────
manifest=""; kind=""; lockfile=""; default_lock_cmd=""
if [[ -f "$repo/pyproject.toml" ]] && grep -qE '^version[[:space:]]*=[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' "$repo/pyproject.toml"; then
  manifest="$repo/pyproject.toml"; kind="pyproject"; lockfile="uv.lock"; default_lock_cmd="uv lock"
elif [[ -f "$repo/package.json" ]] && grep -qE '"version"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' "$repo/package.json"; then
  manifest="$repo/package.json"; kind="package"; lockfile="package-lock.json"; default_lock_cmd="npm install --package-lock-only"
else
  echo "version-bump.sh: note: $repo has no versioned manifest (pyproject.toml/package.json) — skipping (version-less repo, no bump; D3)" >&2
  exit 0
fi

# ── Read the CURRENT version + compute the NEXT per loose-0.x. ────────────────
if [[ "$kind" == "pyproject" ]]; then
  cur="$(grep -m1 -oE '^version[[:space:]]*=[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' "$manifest" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
else
  cur="$(grep -m1 -oE '"version"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' "$manifest" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
fi
[[ -n "$cur" ]] || { echo "version-bump.sh: could not read a X.Y.Z version from $manifest" >&2; exit 1; }

IFS='.' read -r maj min pat <<<"$cur"
case "$level" in
  patch) pat=$((pat + 1)) ;;
  minor) min=$((min + 1)); pat=0 ;;   # MAJOR ($maj) is never touched here (loose-0.x)
esac
new="$maj.$min.$pat"
tag="v$new"

echo "version-bump.sh: $repo $kind $cur -> $new (--level $level)" >&2

lockcmd="${VERSION_BUMP_LOCK_CMD:-$default_lock_cmd}"
cascade_args="${VERSION_BUMP_CASCADE_ARGS:---push}"
gitdir="$(git -C "$repo" rev-parse --absolute-git-dir)"

(
  flock -x 9

  # (1) Rewrite ONLY the version line (exact-line edit; first match). Done in Python to avoid
  #     sed quoting hazards; matches the same anchored patterns used for detection above.
  MANIFEST="$manifest" KIND="$kind" CUR="$cur" NEW="$new" python3 - <<'PY'
import os, re
path = os.environ["MANIFEST"]; kind = os.environ["KIND"]
cur  = re.escape(os.environ["CUR"]); new = os.environ["NEW"]
with open(path, encoding="utf-8") as fh:
    text = fh.read()
if kind == "pyproject":
    pat = re.compile(r'^(version\s*=\s*")' + cur + r'(")', re.M)
else:
    pat = re.compile(r'("version"\s*:\s*")' + cur + r'(")')
new_text, n = pat.subn(r'\g<1>' + new + r'\g<2>', text, count=1)
if n != 1:
    raise SystemExit(f"version-bump.sh: failed to rewrite the version line in {path} (matched {n})")
with open(path, "w", encoding="utf-8") as fh:
    fh.write(new_text)
PY

  # (2) Regenerate the lockfile in-repo (injectable command; stubbed in tests).
  ( cd "$repo" && eval "$lockcmd" ) >&2 \
    || { echo "version-bump.sh: lockfile regen failed ('$lockcmd')" >&2; exit 1; }

  # (3) Stage manifest + lockfile by EXACT path (id:debf — never git add -A/./-u/--all).
  git -C "$repo" add -- "$(basename "$manifest")"
  if [[ -f "$repo/$lockfile" ]]; then
    git -C "$repo" add -- "$lockfile"
  fi

  # (4) Commit the bump (manifest + lockfile TOGETHER so the tree is left clean).
  git -C "$repo" commit -q -m "chore(release): $tag"

  # (5) Annotated tag on the bump commit (finding b — never lightweight).
  git -C "$repo" tag -a "$tag" -m "Release $tag"

  # (6) zkm cascade (finding c): invoke the repo's OWN relock tool if present; never re-implement.
  if [[ -x "$repo/scripts/relock-plugins.sh" ]]; then
    echo "version-bump.sh: cascading plugin lockfiles via scripts/relock-plugins.sh $cascade_args" >&2
    ( cd "$repo" && ./scripts/relock-plugins.sh $cascade_args ) >&2 \
      || echo "version-bump.sh: WARNING: scripts/relock-plugins.sh $cascade_args failed — plugin uv.locks may be stale (tag $tag stands)" >&2
  fi
) 9>"$gitdir/version-bump.lock"

echo "$tag"

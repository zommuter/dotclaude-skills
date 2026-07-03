#!/usr/bin/env bash
# roadmap:fd37 — [MECHANICAL] recipes must write an EXPLICIT success/failure marker
# into the acceptance_artifact (never an empty artifact).
#
# WHY (TODO id:fd37, pilot finding — mechanical-daemon's first real firing on zkWhale
# id:0a7b, 2026-07-03): a recipe whose `cmd` is e.g. `pnpm -s typecheck` writes an EMPTY
# acceptance_artifact on success (tsc is silent-on-clean). An empty artifact is an
# ambiguous acceptance signal — indistinguishable from "never ran / redirect failed".
# The daemon's own success/fail branch is ALREADY correct (exit-code driven: it writes a
# `.error` sibling only when the cmd exits non-zero); this item is purely about the
# ARTIFACT a reviewer inspects.
#
# The doctrine fix (what the executor implements; this RED spec pins it): a [MECHANICAL]
# recipe's `cmd` must append an EXPLICIT terminal success/failure marker to the
# acceptance_artifact AND preserve the real exit code so the daemon's branch still works.
# The canonical safe pattern (executor documents this verbatim as the reference):
#
#   cd <repo> && { <realcmd> > "$ART" 2>&1; rc=$?; echo "MARKER exit=$rc finished=$(date -Is)" >> "$ART"; exit $rc; }
#
# Two enforcement surfaces:
#   (1) DOC — recipe-manifest.md must document the explicit-marker + exit-preservation
#       requirement in its schema/acceptance section.
#   (2) OPTIONAL CODE — recipe-validate.sh emits a NON-FATAL advisory (stderr WARNING,
#       still exit 0) when a recipe's `cmd` redirects into the acceptance_artifact but
#       carries no explicit marker / exit-preservation. The existing 7-field schema
#       hard-fail behavior is UNCHANGED — the marker check is advisory only.
#
# Hermetic: temp recipe files; no ~/.config, no daemon, no network.
# RED until recipe-manifest.md documents the requirement AND recipe-validate.sh grows the
# advisory WARNING.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$ROOT/relay/scripts/recipe-validate.sh"
DOC="$ROOT/relay/references/recipe-manifest.md"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SH" ]] || fail "recipe-validate.sh not found/executable at $SH"
[[ -f "$DOC" ]] || fail "recipe-manifest.md not found at $DOC"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# write_recipe <file> <cmd> <artifact>: a valid 7-field recipe carrying a caller-chosen cmd
# and acceptance_artifact. Only cmd/acceptance_artifact vary between cases here; all other
# fields stay well-formed so the schema hard-fail path never confounds the advisory check.
write_recipe() {
  jq -n \
     --arg id "fd37" \
     --arg repo "zkWhale" \
     --arg cmd "$2" \
     --arg host "$(uname -n)" \
     --argjson est_wall 120 \
     --arg resource "cpu" \
     --arg acceptance_artifact "$3" \
     '{id:$id, repo:$repo, cmd:$cmd, host:$host, est_wall:$est_wall, resource:$resource, acceptance_artifact:$acceptance_artifact}' \
     > "$1"
}

# --- (a) recipe-manifest.md documents the explicit-marker + exit-preservation rule ------
# Not brittle to exact wording: require the doc to (a1) state an EXPLICIT marker requirement
# for the acceptance_artifact, AND (a2) call for preserving the real exit code. Both phrases
# are absent from current doc, so this fails RED until the executor adds the doctrine.
grep -qiE 'explicit[^.]*marker|marker[^.]*explicit' "$DOC" \
  || fail "(a) recipe-manifest.md must document the EXPLICIT-marker requirement for the acceptance_artifact (RED)"
grep -qiE 'exit=|exit \$rc|preserv[a-z]*[^.]*exit|exit[^.]*preserv' "$DOC" \
  || fail "(a) recipe-manifest.md must document preserving the real EXIT code alongside the marker (RED)"
# The requirement should be tied to the acceptance_artifact / [MECHANICAL] recipe, not a
# stray mention — sanity-anchor on the artifact vocabulary already in the doc.
grep -qF 'acceptance_artifact' "$DOC" \
  || fail "(a) marker requirement must be documented in the acceptance_artifact context"
pass "(a) recipe-manifest.md documents the explicit-marker + exit-preservation doctrine"

# --- (b) recipe-validate.sh: advisory WARNING for a redirect-without-marker cmd ----------
# A BARE cmd that redirects into the acceptance_artifact but appends no terminal marker: the
# empty-on-clean footgun. validate must still exit 0 (advisory, non-fatal) BUT warn on stderr.
ART="$tmp/typecheck.log"
bare="$tmp/bare.json"
write_recipe "$bare" "pnpm -s typecheck > $ART 2>&1" "$ART"
if ! err_bare="$("$SH" "$bare" 2>&1 1>/dev/null)"; then
  fail "(b) the marker check must be ADVISORY: a marker-less recipe still exits 0 (schema is valid)"
fi
grep -qiE 'warn' <<<"$err_bare" \
  || fail "(b) a cmd that redirects into the acceptance_artifact with NO explicit marker must emit a WARNING on stderr (got: ${err_bare:-<none>})"
pass "(b) a redirect-without-marker recipe draws a non-fatal WARNING (exit 0)"

# --- (c) recipe-validate.sh: NO warning when the canonical marker pattern is present ------
# The canonical safe pattern: redirect, capture rc, append an explicit "exit=$rc" marker,
# re-exit with the real code. This must NOT warn (no false positive on a correct recipe).
marked="$tmp/marked.json"
write_recipe "$marked" \
  "cd zkWhale && { pnpm -s typecheck > $ART 2>&1; rc=\$?; echo \"MARKER exit=\$rc finished=\$(date -Is)\" >> $ART; exit \$rc; }" \
  "$ART"
if ! err_marked="$("$SH" "$marked" 2>&1 1>/dev/null)"; then
  fail "(c) a well-formed marked recipe must still exit 0"
fi
if grep -qiE 'warn' <<<"$err_marked"; then
  fail "(c) a recipe whose cmd carries the explicit exit=\$rc marker must NOT warn (false positive: $err_marked)"
fi
pass "(c) a recipe with the explicit exit=\$rc marker draws no warning (no false positive)"

echo "ALL PASS: [MECHANICAL] explicit-success-marker doctrine (id:fd37)"

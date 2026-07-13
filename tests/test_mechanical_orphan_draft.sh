#!/usr/bin/env bash
# roadmap:8a6b — mechanical-orphan RESOLUTION loop: auto-draft + LOUD-surface + daemon retry timer.
# relay-doctor check-12 (id:1bd1) DETECTS a [MECHANICAL] ROADMAP item with no recipe; this tests
# the resolution half:
#   (a) mechanical-orphan-draft.sh auto-drafts a recipe SKELETON into drafts/ (NOT pending/) —
#       whitelist-safe: the daemon never consumes drafts/, and the est_wall placeholder makes the
#       draft fail recipe-validate.sh so it is non-executable even if copied into pending/.
#       Idempotent: never overwrites an existing draft.
#   (b) orphans + un-promoted drafts are surfaced in gather-human-backlog.sh and in
#       relay-status-publish.sh's "## Mechanical orphans / drafts" section.
#   (d) mechanical-daemon.timer exists (retry the .path-only trigger) + is wired into the Makefile.
# Hermetic: mktemp -d roots, env overrides, no ~/.claude, no network.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCAN="$SRC_DIR/relay/scripts/mechanical-orphan-scan.sh"
DRAFT="$SRC_DIR/relay/scripts/mechanical-orphan-draft.sh"
VALIDATE="$SRC_DIR/relay/scripts/recipe-validate.sh"
GATHER="$SRC_DIR/relay/scripts/gather-human-backlog.sh"
PUBLISH="$SRC_DIR/relay/scripts/relay-status-publish.sh"
MK="$SRC_DIR/Makefile"
TIMER="$SRC_DIR/tools/mechanical-daemon.timer"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 not found"; exit 1; }

for f in "$SCAN" "$DRAFT" "$VALIDATE" "$GATHER" "$PUBLISH"; do
  [[ -x "$f" ]] || { echo "FAIL: missing/non-exec $f"; exit 1; }
done

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export RELAY_RECIPE_DIR="$TMP/recipes"
mkdir -p "$RELAY_RECIPE_DIR/pending" "$RELAY_RECIPE_DIR/done" "$TMP/repoX"

cat > "$TMP/repoX/ROADMAP.md" <<'EOF'
# ROADMAP
- [ ] [MECHANICAL] [host:zomni] [INTENSIVE — r5-jvm] gen isochrone fields <!-- id:ac14 -->
- [ ] [MECHANICAL] already has a real recipe (should NOT surface) <!-- id:beef -->
- [ ] [MECHANICAL] bare mechanical, no host/intensive tag <!-- id:cafe -->
- [x] [MECHANICAL] closed item — ignored <!-- id:dead -->
- [ ] [HARD] not mechanical — ignored <!-- id:0001 -->
EOF
echo '{"id":"beef","repo":"repoX","cmd":"make x","host":"zomni","est_wall":60,"resource":"cpu","acceptance_artifact":"out.txt"}' \
  > "$RELAY_RECIPE_DIR/pending/beef.json"

REPOARG="repoX=$TMP/repoX"

# --- scanner: orphans before drafting ------------------------------------------------
before="$("$SCAN" "$REPOARG")"
echo "$before" | grep -qP '^orphan\tac14\trepoX\tzomni\tr5-jvm\t' && ok "scanner reports ac14 orphan with host+resource extracted" || bad "ac14 orphan/tags wrong: $before"
echo "$before" | grep -qP '^orphan\tcafe\trepoX\t-\t-\t'           && ok "scanner reports cafe orphan with '-' host/resource placeholders" || bad "cafe orphan row wrong: $before"
echo "$before" | grep -q 'beef' && bad "beef (has a real recipe) must NOT surface" || ok "item with a real recipe is excluded"
echo "$before" | grep -q 'dead' && bad "closed [x] item must NOT surface" || ok "closed item excluded"
echo "$before" | grep -q '0001' && bad "non-[MECHANICAL] item must NOT surface" || ok "non-mechanical item excluded"

# --- (a) auto-draft: writes to drafts/, NOT pending/ ---------------------------------
"$DRAFT" "$REPOARG" >/dev/null
[[ -f "$RELAY_RECIPE_DIR/drafts/ac14.json" ]] && ok "draft skeleton written to drafts/ac14.json" || bad "no draft for ac14"
[[ -f "$RELAY_RECIPE_DIR/drafts/cafe.json" ]] && ok "draft skeleton written to drafts/cafe.json" || bad "no draft for cafe"
[[ ! -f "$RELAY_RECIPE_DIR/pending/ac14.json" ]] && ok "WHITELIST-SAFE: nothing written to pending/ (only drafts/)" || bad "draft leaked into pending/ — whitelist breach"

# prefilled id/repo/host/resource; TODO placeholders for cmd/est_wall/acceptance_artifact
python3 - "$RELAY_RECIPE_DIR/drafts/ac14.json" <<'PY' && ok "draft prefills id/repo/host/resource + TODO placeholders" || bad "draft field content wrong"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["id"] == "ac14", d
assert d["repo"] == "repoX", d
assert d["host"] == "zomni", d
assert d["resource"] == "r5-jvm", d
assert d["cmd"].startswith("TODO:"), d
assert isinstance(d["est_wall"], str) and d["est_wall"].startswith("TODO:"), d
assert d["acceptance_artifact"].startswith("TODO:"), d
PY

# a draft with no host/intensive tag carries TODO host/resource placeholders
python3 - "$RELAY_RECIPE_DIR/drafts/cafe.json" <<'PY' && ok "tagless draft leaves host/resource as TODO placeholders" || bad "tagless draft wrong"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["host"].startswith("TODO:"), d
assert d["resource"].startswith("TODO:"), d
PY

# NON-EXECUTABLE: recipe-validate.sh rejects the draft (est_wall not a positive int)
if "$VALIDATE" "$RELAY_RECIPE_DIR/drafts/ac14.json" >/dev/null 2>&1; then
  bad "recipe-validate.sh ACCEPTED a draft — draft must be non-executable"
else
  ok "recipe-validate.sh REJECTS the draft (non-executable by construction)"
fi

# --- idempotency: re-running does not overwrite, and drafted orphans now report as draft ---
python3 -c "import json;d=json.load(open('$RELAY_RECIPE_DIR/drafts/ac14.json'));d['cmd']='HAND-EDITED';json.dump(d,open('$RELAY_RECIPE_DIR/drafts/ac14.json','w'))"
"$DRAFT" "$REPOARG" >/dev/null
grep -q 'HAND-EDITED' "$RELAY_RECIPE_DIR/drafts/ac14.json" && ok "idempotent: existing draft NOT overwritten on re-run" || bad "re-run clobbered an existing draft"

after="$("$SCAN" "$REPOARG")"
echo "$after" | grep -qP '^draft\tac14\trepoX\t' && ok "after drafting, ac14 reports as an un-promoted DRAFT (not orphan)" || bad "ac14 should be a draft now: $after"
echo "$after" | grep -qP '^orphan\t' && bad "no orphans should remain after drafting all" || ok "all orphans became drafts"

# --- (b) surfacing: gather-human-backlog rows ---------------------------------------
# gather-human-backlog takes repo NAMES (resolved via relay.toml), not name=path; give it a toml.
cat > "$TMP/relay.toml" <<EOF
[repos.repoX]
classification = "own"
# path: $TMP/repoX
EOF
gh_out="$(SRC_DIR="$TMP" RELAY_TOML="$TMP/relay.toml" "$GATHER" repoX 2>/dev/null || true)"
echo "$gh_out" | grep -qP '\tmechanical_draft\t' && ok "gather-human-backlog surfaces mechanical_draft rows" || bad "gather missing mechanical_draft: $gh_out"
# reset drafts to force an orphan for the orphan-row assertion
rm -f "$RELAY_RECIPE_DIR/drafts/"*.json
gh_orph="$(SRC_DIR="$TMP" RELAY_TOML="$TMP/relay.toml" "$GATHER" repoX 2>/dev/null || true)"
echo "$gh_orph" | grep -qP '\tmechanical_orphan\t' && ok "gather-human-backlog surfaces mechanical_orphan rows" || bad "gather missing mechanical_orphan: $gh_orph"

# --- (b) surfacing: relay-status-publish "## Mechanical orphans / drafts" section ----
status_out="$(printf 'BODY\n' | RELAY_TOML="$TMP/relay.toml" SRC_DIR="$TMP" HOME="$TMP" \
  "$PUBLISH" --path "$TMP/RELAY_STATUS.md" --run testrun --events-path "$TMP/events.jsonl" 2>/dev/null || true)"
if [[ -f "$TMP/RELAY_STATUS.md" ]]; then
  grep -q '## Mechanical orphans / drafts' "$TMP/RELAY_STATUS.md" && ok "RELAY_STATUS has the Mechanical orphans / drafts section" || bad "RELAY_STATUS missing the mech section"
  grep -qi 'ORPHAN.*ac14' "$TMP/RELAY_STATUS.md" && ok "RELAY_STATUS lists the ac14 orphan" || bad "RELAY_STATUS did not list the ac14 orphan"
else
  bad "relay-status-publish did not write RELAY_STATUS.md (out: $status_out)"
fi

# --- (d) retry timer exists + wired -------------------------------------------------
[[ -f "$TIMER" ]] && ok "mechanical-daemon.timer unit exists" || bad "mechanical-daemon.timer missing"
grep -q 'OnUnitActiveSec' "$TIMER" && ok "timer has a periodic OnUnitActiveSec cadence" || bad "timer has no periodic cadence"
grep -q 'mechanical-daemon.timer' "$MK" && ok "Makefile install-mechanical-daemon wires the timer" || bad "Makefile does not install the timer"
grep -q 'recipes/drafts' "$MK" && ok "Makefile creates the recipes/drafts dir on install" || bad "Makefile does not mkdir recipes/drafts"

echo "test_mechanical_orphan_draft: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]

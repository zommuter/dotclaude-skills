#!/usr/bin/env bash
# DEFECT-FIX test for routed:96da — deliberately NO `# roadmap:XXXX` header.
# This specs a confirmed defect, not an open roadmap item, so it must NEVER be reported
# EXPECTED-RED: its failures always count (CLAUDE.md §Testing).
#
# DEFECT (observed live 2026-08-12): meeting/append.sh's id:069b personas-extend branch does
#     tmp="$(mktemp)"; awk … > "$tmp"; mv -- "$tmp" "$dest"
# but the installed $dest — ~/.claude/skills/meeting/personas.md — is a SYMLINK to the
# canonical ~/src/dotclaude-skills/meeting/personas.md (per-file symlink install). `mv`
# REPLACES the symlink with a detached regular file: the canonical repo file never receives
# the edit, the registry forks silently, perms drop 0644→0600 (mktemp default) and the file
# crosses filesystems (/tmp → home). Only `git status` showing a ` T` typechange revealed it.
# The plain-append path below the branch is CORRECT (`printf >> "$dest"` follows the link) —
# only the id:069b branch breaks it.
#
# This test reproduces the REAL topology: a skill dir holding per-file symlinks into a
# canonical checkout dir.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPEND="$ROOT/meeting/append.sh"
[[ -x "$APPEND" ]] || { echo "FAIL: meeting/append.sh not found/executable at $APPEND"; exit 1; }

fail() { echo "FAIL: $*"; exit 1; }
pass() { echo "PASS: $*"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"   # hermetic: never touch the real ~/.claude
mkdir -p "$HOME"

CANON="$TMP/canon/meeting"          # stands in for ~/src/dotclaude-skills/meeting
INST="$TMP/home/.claude/skills/meeting"   # stands in for the installed skill dir
mkdir -p "$CANON" "$INST"
cp "$APPEND" "$CANON/append.sh"
cat > "$CANON/personas.md" <<'FIXTURE'
# Ad-hoc persona registry

- 🚚 **Gil** — release engineering. RELEASE-TAG-PUSH-SEMANTICS. Introduced 2026-06-02 (zkm/tags).
FIXTURE
chmod 0644 "$CANON/personas.md"
# Per-file symlinks, exactly as `make install-meeting` creates them.
ln -s "$CANON/append.sh"   "$INST/append.sh"
ln -s "$CANON/personas.md" "$INST/personas.md"

# Invoke through the INSTALLED path — that is how the skill is actually run.
set +e
err="$(bash "$INST/append.sh" -t personas \
  -e "- 🚚 **Gil** — release engineering; now also changelog derivation. Extended 2026-08-12 (dotclaude-skills/changelog)." 2>&1 >/dev/null)"
rc=$?
set -e
(( rc == 0 )) || fail "(0) append.sh exited $rc extending through the installed symlink. stderr: $err"

# 1. The symlink must STILL be a symlink — not replaced by a detached regular file.
[[ -L "$INST/personas.md" ]] \
  || fail "(1) the installed personas.md is NO LONGER A SYMLINK — the id:069b extend branch \`mv\`d a temp file over \$dest, detaching the install from the canonical checkout and forking the registry (routed:96da). It is now: $(ls -l "$INST/personas.md")"
pass "(1) the installed path is still a symlink after an extend"

# 2. …and it still points at the SAME canonical file.
tgt="$(readlink -f -- "$INST/personas.md")"
[[ "$tgt" == "$(readlink -f -- "$CANON/personas.md")" ]] \
  || fail "(2) the installed symlink no longer resolves to the canonical file (now '$tgt') (routed:96da)"
pass "(2) the symlink still resolves to the canonical file"

# 3. The CANONICAL file received the edit — this is the actual harm: a write that lands
#    only under ~/.claude never reaches the repo, and the next reader sees a forked registry.
grep -qF -- 'changelog derivation' "$CANON/personas.md" \
  || fail "(3) the canonical file never received the extension — the write landed in a detached file under the install dir (routed:96da). Canonical file:
$(cat "$CANON/personas.md")"
pass "(3) the canonical file received the extension"

# 4. Permissions preserved — mktemp's 0600 must not leak onto the registry.
mode="$(stat -c '%a' "$CANON/personas.md")"
[[ "$mode" == "644" ]] \
  || fail "(4) canonical personas.md permissions changed to 0$mode (mktemp's 0600 default leaking through the mv) — the write must happen in place (routed:96da)"
pass "(4) file permissions are preserved"

# 5. No temp residue left next to the registry.
resid="$(find "$CANON" "$INST" -maxdepth 1 -name '.personas*' -o -maxdepth 1 -name '*.tmp' | tr '\n' ' ')"
[[ -z "${resid// /}" ]] || fail "(5) temp residue left behind: $resid (routed:96da)"
pass "(5) no temp-file residue"

echo "PASS test_personas_extend_follows_symlink_96da"

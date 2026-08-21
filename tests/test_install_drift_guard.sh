#!/usr/bin/env bash
# roadmap:c5ed — install-drift guard for the per-file-symlink skill install.
#
# WHY (id:c5ed, routed:35eb): skills install as per-file symlinks, so a newly-added
# canonical script needs `make install-<skill>` to appear under
# ~/.claude/skills/<skill>/scripts/. Nothing FAILS when a canonical script has no
# installed counterpart — the failure surfaces only as a runtime "command not found"
# inside an agent (easy to miss), OR — the NASTIER 2026-07-24 recurrence (routed:35eb) —
# as a SILENT death when an installed script `source "$dir/<sibling>.sh"`s a sibling that
# is not installed: under `set -e` the source-not-found kills the script mid-run and a
# caller reading only stdout sees clean (a FALSE-GREEN). The original c5ed instance only
# covered directly-invoked scripts; this guard MUST also cover `source` targets.
#
# INTERFACE UNDER TEST (the spec — the guard does not exist yet, so this is RED):
#   relay/scripts/check-install-drift.sh --canonical <dir> --installed <dir>
#     --canonical <dir>  a directory of canonical scripts (e.g. relay/scripts/)
#     --installed <dir>  the install dir it must be mirrored into
#                        (e.g. ~/.claude/skills/relay/scripts/)
#   Behaviour:
#     (1) DIRECT drift  — every `<canonical>/*.sh` must have a same-named entry (file OR
#         symlink) in <installed>; a missing one is drift.
#     (2) SOURCE drift  — for every `<canonical>/*.sh`, every sibling it pulls in with a
#         `source`/`.` line referencing `$script_dir|$dir/<name>.sh` (or a bare relative
#         `<name>.sh`) must ALSO resolve in <installed>; a missing source target is drift
#         EVEN WHEN the sourcing script itself is installed (the routed:35eb false-green).
#     Any drift  → exit NON-zero, and NAME each missing script (basename) on stdout/stderr.
#     Full parity → exit 0, clean.
#
# Hermetic: bash-only, all fixtures under mktemp -d, no git, no network, never touches the
# real ~/.claude. Roots are passed by ARGS (--canonical/--installed), so no HOME override
# is needed.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GUARD="$SRC_DIR/relay/scripts/check-install-drift.sh"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }

[[ -f "$GUARD" ]] || { echo "FAIL: relay/scripts/check-install-drift.sh does not exist yet (RED spec — id:c5ed)"; exit 1; }
[[ -x "$GUARD" ]] || { echo "FAIL: check-install-drift.sh not executable"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Helper: symlink every file in $1 into $2 (mirrors `make install`'s per-file symlinks).
link_all() { local c="$1" i="$2" f; mkdir -p "$i"; for f in "$c"/*.sh; do [[ -e "$f" ]] && ln -sf "$f" "$i/$(basename "$f")"; done; }

# ---------------------------------------------------------------------------
# (a) NEGATIVE-DIRECT: a canonical script with NO installed symlink → drift,
#     names the missing script. (the original c5ed "command not found" class)
# ---------------------------------------------------------------------------
CA="$TMP/a_can"; IA="$TMP/a_inst"; mkdir -p "$CA"
printf '#!/usr/bin/env bash\necho hi\n'         > "$CA/present.sh"
printf '#!/usr/bin/env bash\necho standalone\n' > "$CA/standalone.sh"   # no source lines
link_all "$CA" "$IA"
rm -f "$IA/standalone.sh"                                                # drift: not installed
if out="$("$GUARD" --canonical "$CA" --installed "$IA" 2>&1)"; then
  bad "(a) direct: a canonical script with no installed symlink must exit non-zero (drift)"
else
  grep -qF 'standalone.sh' < <(echo "$out") \
    && ok "(a) direct: uninstalled canonical script → non-zero + names standalone.sh" \
    || bad "(a) direct: exited non-zero but did not name the missing standalone.sh (got: $out)"
fi

# ---------------------------------------------------------------------------
# (b) NEGATIVE-SOURCE (routed:35eb): canonical a.sh `source`s b.sh; a.sh IS installed
#     but b.sh is NOT → drift naming b.sh, even though a.sh resolves.
#     This is the exact roadmap-lint.sh→lib-state-claim.sh false-green shape.
# ---------------------------------------------------------------------------
CB="$TMP/b_can"; IB="$TMP/b_inst"; mkdir -p "$CB"
cat > "$CB/roadmap-lint.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib-state-claim.sh"
echo linted
EOF
printf '#!/usr/bin/env bash\n: shared lib\n' > "$CB/lib-state-claim.sh"
link_all "$CB" "$IB"
rm -f "$IB/lib-state-claim.sh"                    # drift: the SOURCE target is not installed
if out="$("$GUARD" --canonical "$CB" --installed "$IB" 2>&1)"; then
  bad "(b) source: an installed script whose source-target is not installed must exit non-zero (routed:35eb)"
else
  grep -qF 'lib-state-claim.sh' < <(echo "$out") \
    && ok "(b) source: uninstalled source-target → non-zero + names lib-state-claim.sh" \
    || bad "(b) source: exited non-zero but did not name the missing source-target lib-state-claim.sh (got: $out)"
fi

# ---------------------------------------------------------------------------
# (d) SOURCE-ONLY (forces real source-following, not a blind canonical∖installed diff):
#     every canonical file IS installed (direct enumeration is GREEN), but a.sh sources a
#     sibling `helper.sh` that is absent from the install → still drift. A pure set-diff
#     implementation would MISS this; only parsing the source line catches it.
# ---------------------------------------------------------------------------
CD="$TMP/d_can"; ID="$TMP/d_inst"; mkdir -p "$CD"
cat > "$CD/a.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
dir="$(dirname "$0")"
source "$dir/helper.sh"
echo a
EOF
link_all "$CD" "$ID"                              # only a.sh is canonical → both dirs = {a.sh}
# helper.sh is a required runtime sibling but is NOT installed (and not a canonical *.sh here)
if out="$("$GUARD" --canonical "$CD" --installed "$ID" 2>&1)"; then
  bad "(d) source-only: direct enumeration is green but a dangling source-target must still be drift"
else
  grep -qF 'helper.sh' < <(echo "$out") \
    && ok "(d) source-only: unresolved source-target with green enumeration → non-zero + names helper.sh" \
    || bad "(d) source-only: exited non-zero but did not name the missing source-target helper.sh (got: $out)"
fi

# ---------------------------------------------------------------------------
# (c) POSITIVE: full parity — every canonical script AND every source target installed → exit 0.
# ---------------------------------------------------------------------------
CC="$TMP/c_can"; IC="$TMP/c_inst"; mkdir -p "$CC"
cat > "$CC/main.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib.sh"
echo main
EOF
printf '#!/usr/bin/env bash\n: lib\n'      > "$CC/lib.sh"
printf '#!/usr/bin/env bash\necho other\n' > "$CC/other.sh"
link_all "$CC" "$IC"                              # everything installed, all source targets resolve
if out="$("$GUARD" --canonical "$CC" --installed "$IC" 2>&1)"; then
  ok "(c) positive: full parity (scripts + source targets installed) → exit 0"
else
  bad "(c) positive: full-parity install must exit 0 (got non-zero: $out)"
fi

echo "summary: $pass ok, $fail bad"
[[ "$fail" -eq 0 ]] || exit 1
exit 0

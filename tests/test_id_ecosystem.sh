#!/usr/bin/env bash
# roadmap:de9c — id-token ecosystem extends to ROADMAP.md:
#   1. append.sh scan-ids <root> prints every existing token (sorted unique),
#      and the ledger set includes ROADMAP.md (so new-id/new-ids can't collide
#      with roadmap tokens).
#   2. orphan-scan.sh counts ROADMAP.md as part of the TODO union (forward and
#      reverse): a note item whose token lives in ROADMAP.md is not an orphan.
#   3. classify.sh emits class RELAY for the TODO.md relay mirror line so
#      /meeting no-arg dispatch never proposes a meeting on executor work.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPEND="$ROOT/meeting/append.sh"
ORPHAN="$ROOT/meeting/orphan-scan.sh"
CLASSIFY="$ROOT/meeting/classify.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ── Fixture repo ────────────────────────────────────────────────────────────
fix="$tmp/repo"
mkdir -p "$fix/docs/meeting-notes"
cat > "$fix/TODO.md" <<'EOF'
# TODO

## Relay

- [ ] Relay: 3 open ROADMAP items <!-- id:abcd -->

## work

- [ ] some open task <!-- id:aaaa -->
- [ ] bare task without any signal
EOF
cat > "$fix/TODO.archive.md" <<'EOF'
# TODO Archive
- [x] archived task <!-- id:bbbb -->
EOF
cat > "$fix/ROADMAP.md" <<'EOF'
# Roadmap <!-- relay roadmap v1 -->
- [ ] roadmap-only item [ROUTINE] <!-- id:dddd -->
EOF
cat > "$fix/docs/meeting-notes/2026-06-12-0000-fixture.md" <<'EOF'
# Fixture meeting note
## Action items
- [ ] mirrored to roadmap only <!-- id:dddd -->
- [ ] true orphan, nowhere else <!-- id:eeee -->
- [x] done item known to roadmap <!-- id:dddd -->
- [x] done item known nowhere <!-- id:ffff -->
- [ ] note item also in todo <!-- id:cccc -->
EOF
# give cccc a TODO home so it is never flagged
printf -- '- [ ] todo twin <!-- id:cccc -->\n' >> "$fix/TODO.md"

# ── 1. append.sh scan-ids ───────────────────────────────────────────────────
ids="$("$APPEND" scan-ids "$fix")" \
  || { echo "append.sh scan-ids subcommand missing/failed"; exit 1; }
for t in aaaa bbbb cccc dddd eeee abcd; do
  grep -qx "$t" <<<"$ids" || { echo "scan-ids missing token $t (got: $(tr '\n' ' ' <<<"$ids"))"; exit 1; }
done
[[ "$(sort -u <<<"$ids" | grep -c .)" -eq "$(grep -c . <<<"$ids")" ]] \
  || { echo "scan-ids output must be unique"; exit 1; }
[[ "$(sort <<<"$ids")" == "$ids" ]] || { echo "scan-ids output must be sorted"; exit 1; }

# new-ids still emits well-formed, batch-unique tokens
batch="$("$APPEND" new-ids 5 "$fix")"
[[ "$(grep -cE '^[0-9a-f]{4}$' <<<"$batch")" -eq 5 ]] \
  || { echo "new-ids 5 must emit five 4-hex tokens"; exit 1; }
[[ "$(sort -u <<<"$batch" | grep -c .)" -eq 5 ]] || { echo "new-ids batch not unique"; exit 1; }

# ── 2. orphan-scan union includes ROADMAP.md ────────────────────────────────
fwd="$(HOME="$tmp" "$ORPHAN" "$fix")"
grep -q 'id:eeee' <<<"$fwd" || { echo "forward scan must flag the true orphan eeee"; exit 1; }
if grep -q 'id:dddd' <<<"$fwd"; then
  echo "forward scan flagged dddd although it lives in ROADMAP.md"; exit 1
fi
if grep -q 'id:cccc' <<<"$fwd"; then
  echo "forward scan flagged cccc although it lives in TODO.md"; exit 1
fi

rev="$(HOME="$tmp" "$ORPHAN" --reverse "$fix")"
grep -q 'id:ffff' <<<"$rev" || { echo "reverse scan must flag ffff"; exit 1; }
if grep -q 'id:dddd' <<<"$rev"; then
  echo "reverse scan flagged dddd although it lives in ROADMAP.md"; exit 1
fi

# ── 3. classify.sh RELAY class for the mirror line ─────────────────────────
cls="$("$CLASSIFY" "$fix")"
relay_line="$(grep -P '\tid:abcd\t' <<<"$cls" || true)"
[[ -n "$relay_line" ]] || { echo "classify.sh lost the relay mirror line"; exit 1; }
awk -F'\t' '{exit !($1 == "RELAY")}' <<<"$relay_line" \
  || { echo "relay mirror line must classify as RELAY, got: $relay_line"; exit 1; }
# ordinary items keep their classes
grep -P '^C3\t\tbare task' <<<"$cls" >/dev/null \
  || { echo "ordinary C3 classification regressed"; exit 1; }

echo ok

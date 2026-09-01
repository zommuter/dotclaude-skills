#!/usr/bin/env bash
# DEFECT-FIX test for id:00b1 — deliberately NO `# roadmap:XXXX` header.
# This specs a confirmed defect, not an open roadmap item, so it must NEVER be reported
# EXPECTED-RED: its failures always count (CLAUDE.md §Testing).
#
# DEFECT: 89f6e1c fixed routed:96da by replacing `mktemp` + `mv` (an atomic rename that
# DETACHED the install symlink) with an in-place `Path.write_text()`. Following the symlink
# was correct and necessary — but write_text is open-for-TRUNCATE-then-write, so a concurrent
# reader (or a writer holding the OTHER lock, id:244f) can observe a TRUNCATED registry
# instead of a stale-but-whole one. The failure mode moved from lossy to destructive.
#
# CONTRACT asserted here: the personas write is BOTH symlink-following AND atomic. At no
# instant may the registry be observable in a state other than "wholly the old file" or
# "wholly the new file" — asserted by a reader sampling the size continuously across the
# write, since a torn write necessarily passes through intermediate sizes (0 first).
# Assertions 3-4 re-assert the routed:96da properties the fix must not regress.
# fails-against: rev bcde33a4d333 -- the tree as it stood immediately before the commit that
#   added this test, i.e. the pre-fix meeting/append.sh. Derived + verified by tests/verify-negative-cases.py.
# fails-against-rev: bcde33a4d333 -- meeting/append.sh
# fails-against-assertion: …]. The personas write truncates in place (Path.write_text), so a reader can see a PARTIAL merge=union registry (id:00b1). Write to a temp file in the same directory as the RESOLVED target and os.replace() onto it.

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

CANON="$TMP/canon/meeting"
INST="$TMP/home/.claude/skills/meeting"
mkdir -p "$CANON" "$INST"
cp "$APPEND" "$CANON/append.sh"

# A LARGE fixture: the observation window of a truncate-then-write is proportional to the
# payload, so a realistic-but-small registry would make the tear unobservable by luck rather
# than by correctness. ~7 MB of filler + one real persona entry.
python3 - "$CANON/personas.md" <<'PYEOF'
import sys
filler = ("Filler prose line kept deliberately free of bolded persona names so the "
          "extend targets exactly one entry; padding to widen the write window.\n")
with open(sys.argv[1], "w", encoding="utf-8") as f:
    f.write("# Ad-hoc persona registry\n\n")
    f.write(filler * 50000)
    f.write("- 🚚 **Gil** — release engineering. RELEASE-TAG-PUSH-SEMANTICS. Introduced 2026-06-02 (zkm/tags).\n")
PYEOF
chmod 0644 "$CANON/personas.md"
ln -s "$CANON/append.sh"   "$INST/append.sh"
ln -s "$CANON/personas.md" "$INST/personas.md"

# The sampler: record every distinct size the registry presents while the writer runs.
cat > "$TMP/sampler.py" <<'PYEOF'
import os, sys, time
path, stop = sys.argv[1], sys.argv[2]
seen, deadline = set(), time.time() + 60
while not os.path.exists(stop) and time.time() < deadline:
    try:
        seen.add(os.stat(path).st_size)
    except FileNotFoundError:
        seen.add(-1)
print("\n".join(str(s) for s in sorted(seen)))
PYEOF

old_size="$(stat -c '%s' "$CANON/personas.md")"
rm -f -- "$TMP/stop"
python3 "$TMP/sampler.py" "$INST/personas.md" "$TMP/stop" > "$TMP/sizes.txt" &
sampler=$!
sleep 0.3

set +e
err="$(bash "$INST/append.sh" -t personas \
  -e "- 🚚 **Gil** — release engineering; now also changelog derivation. Extended 2026-08-13 (dotclaude-skills/atomic)." 2>&1 >/dev/null)"
rc=$?
set -e
touch "$TMP/stop"
wait "$sampler" || true

(( rc == 0 )) || fail "(0) append.sh exited $rc extending through the installed symlink. stderr: $err"
new_size="$(stat -c '%s' "$CANON/personas.md")"

# 1. Non-vacuity: the write must actually have changed the file, or "no torn size seen"
#    would be trivially true.
(( new_size != old_size )) \
  || fail "(1) the extend did not change the file size ($old_size) — the atomicity check would be vacuous; the fixture or the write path is wrong"
grep -qF -- 'changelog derivation' "$CANON/personas.md" \
  || fail "(1) the extension never landed in the canonical registry"
pass "(1) the write happened and changed the file (old=$old_size new=$new_size bytes)"

# 2. THE assertion: no intermediate state was ever observable.
torn=""; n_torn=0
while read -r s; do
  [[ -z "$s" ]] && continue
  if [[ "$s" != "$old_size" && "$s" != "$new_size" ]]; then
    (( ++n_torn ))
    (( n_torn <= 8 )) && torn+="$s "
  fi
done < "$TMP/sizes.txt"
(( n_torn == 0 )) \
  || fail "(2) TORN WRITE: a concurrent reader observed the registry in $n_torn state(s) that are neither the old file ($old_size bytes) nor the new one ($new_size bytes) — first few sizes: [${torn}…]. The personas write truncates in place (Path.write_text), so a reader can see a PARTIAL merge=union registry (id:00b1). Write to a temp file in the same directory as the RESOLVED target and os.replace() onto it."
n_samples="$(grep -c . "$TMP/sizes.txt" || true)"
pass "(2) every observed state was wholly-old or wholly-new ($n_samples distinct sizes seen)"

# 3. routed:96da must not regress: the install path is still a symlink onto the canonical file.
[[ -L "$INST/personas.md" ]] \
  || fail "(3) the installed personas.md is no longer a symlink — an atomic write must replace the RESOLVED target, never the link itself (routed:96da/id:00b1). It is now: $(ls -l "$INST/personas.md")"
[[ "$(readlink -f -- "$INST/personas.md")" == "$(readlink -f -- "$CANON/personas.md")" ]] \
  || fail "(3) the installed symlink no longer resolves to the canonical file (routed:96da)"
pass "(3) the symlink survives an atomic write and still resolves to the canonical file"

# 4. …and the mode survives (mktemp's 0600 default was the original routed:96da regression).
mode="$(stat -c '%a' "$CANON/personas.md")"
[[ "$mode" == "644" ]] \
  || fail "(4) canonical personas.md permissions became 0$mode — an atomic-rename write must carry the target's mode onto the temp file (routed:96da/id:00b1)"
pass "(4) file permissions are preserved"

# 5. No temp residue, and no /tmp→home filesystem hop (the temp file must live in the
#    resolved target's own directory, which is why no residue may appear anywhere else).
resid="$(find "$CANON" "$INST" -maxdepth 1 \( -name '.personas*' -o -name '*.tmp' \) | tr '\n' ' ')"
[[ -z "${resid// /}" ]] || fail "(5) temp residue left behind: $resid (routed:96da)"
pass "(5) no temp-file residue"

echo "PASS test_personas_write_atomic_00b1"

#!/usr/bin/env bash
# roadmap:f26d
#
# md-merge.py gains two operations (routed:f88b, narrowed by its own author's
# correction routed:9aaf): (a) insert-relative-to-id — place a NEW item beside an
# existing anchor id, never silently at EOF; (b) an in-lock transform (regex_sub) so
# a whole-line edit no longer needs a TOCTOU-prone out-of-lock read (append already
# covered the append-only case; regex_sub generalises it to an arbitrary in-lock
# substitution).
#
# Hermetic: mktemp -d only. No git, no network, no ~/.claude writes.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MDMERGE="$ROOT/meeting/md-merge.py"

fail=0
note() { echo "FAIL: $*" >&2; fail=1; }
[[ -f "$MDMERGE" ]] || { echo "FAIL: md-merge.py missing at $MDMERGE" >&2; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
F="$tmp/ROADMAP.md"

seed() {
  { printf '# ROADMAP\n'
    printf -- '- [ ] Item A <!-- id:aaaa -->\n'
    printf -- '- [ ] Item B <!-- id:bbbb -->\n'
    printf '## Done\n'
    printf -- '- [x] Item Z <!-- id:9999 -->\n'
  } > "$F"
}

RC=0; ERR=""
run_delta() {
  local json="$1"; shift
  set +e
  ERR="$(printf '%s' "$json" | python3 "$MDMERGE" update-ids --file "$F" "$@" 2>&1 >/dev/null)"
  RC=$?
  set -e
}

# ══ (1) insert_after lands BETWEEN A and B, not at EOF ═════════════════════════════
seed
run_delta '{"updates":[{"id":"aaaa","insert_after":"- [ ] New seam <!-- id:cccc -->"}]}'
(( RC == 0 )) || note "(1) insert_after a valid anchor must succeed; stderr: $ERR"
mapfile -t ids < <(grep -oE '<!-- id:[0-9a-f]{4} -->' "$F" | grep -oE '[0-9a-f]{4}')
[[ "${ids[*]}" == "aaaa cccc bbbb 9999" ]] \
  || note "(1) new item did not land BETWEEN aaaa and bbbb — order is: ${ids[*]}"

# ══ (2) insert_before lands immediately before its anchor ══════════════════════════
seed
run_delta '{"updates":[{"id":"bbbb","insert_before":"- [ ] Earlier seam <!-- id:dddd -->"}]}'
(( RC == 0 )) || note "(2) insert_before a valid anchor must succeed; stderr: $ERR"
mapfile -t ids < <(grep -oE '<!-- id:[0-9a-f]{4} -->' "$F" | grep -oE '[0-9a-f]{4}')
[[ "${ids[*]}" == "aaaa dddd bbbb 9999" ]] \
  || note "(2) new item did not land immediately BEFORE bbbb — order is: ${ids[*]}"

# ══ (3) insert targeting a NONEXISTENT anchor fails LOUD, no EOF fallback ══════════
seed; before="$(cat "$F")"
run_delta '{"updates":[{"id":"9f9f","insert_after":"- [ ] orphan seam <!-- id:eeee -->"}]}'
(( RC != 0 )) \
  || note "(3) an insert against a nonexistent anchor id must fail LOUD, not silently append at EOF"
[[ "$(cat "$F")" == "$before" ]] \
  || note "(3) a refused insert must write NOTHING — the file changed"
grep -q '9f9f' <<<"$ERR" || note "(3) the refusal must name the missing anchor id (9f9f); got: ${ERR:-<empty>}"
grep -qF 'eeee' "$F" \
  && note "(3) the new item's id (eeee) ended up in the file despite the anchor being missing — it must never fall back to EOF"

# ══ (4) two SEQUENTIAL (simulated-concurrent) regex_sub transforms on the SAME id ══
# both survive — the general in-lock-transform property. A naive REPLACE built from a
# pre-lock read would have the second call clobber the first (last-under-lock wins on
# a literal); regex_sub instead composes from whatever is under the lock right now.
seed
run_delta '{"updates":[{"id":"aaaa","regex_sub":{"pattern":"Item A","repl":"Item A [seen-by-1]"}}]}'
(( RC == 0 )) || note "(4a) first regex_sub call must succeed; stderr: $ERR"
run_delta '{"updates":[{"id":"aaaa","regex_sub":{"pattern":"<!-- id:aaaa -->","repl":"[seen-by-2] <!-- id:aaaa -->"}}]}'
(( RC == 0 )) || note "(4b) second regex_sub call must succeed; stderr: $ERR"
line="$(grep -F 'id:aaaa' "$F" || true)"
grep -qF '[seen-by-1]' <<<"$line" || note "(4) the FIRST transform's edit is missing — it was clobbered; line: $line"
grep -qF '[seen-by-2]' <<<"$line" || note "(4) the SECOND transform's edit is missing; line: $line"
grep -qE '^- \[ \] ' <<<"$line" || note "(4) the checkbox prefix was lost by a transform"
grep -qE '<!--[[:space:]]*id:aaaa[[:space:]]*-->' <<<"$line" \
  || note "(4) the line's own id marker was lost — it would be unaddressable by the next call"

# ══ (5) the existing multi-marker (routed:3ad9 / id:6059) refusal still fires for the
#         NEW ops — an insert anchor / regex_sub target on an ambiguous line refuses ══
seed
printf -- '- [ ] Ambiguous line <!-- id:ffff --> refers to <!-- id:1234 -->\n' >> "$F"
before="$(cat "$F")"
run_delta '{"updates":[{"id":"ffff","insert_after":"- [ ] should not land <!-- id:5678 -->"}]}'
(( RC != 0 )) || note "(5a) insert_after an anchor id that appears on a multi-marker line must be REFUSED (id:6059 regression)"
[[ "$(cat "$F")" == "$before" ]] || note "(5a) the refused insert wrote something"
run_delta '{"updates":[{"id":"ffff","regex_sub":{"pattern":"Ambiguous","repl":"Changed"}}]}'
(( RC != 0 )) || note "(5b) regex_sub against an id on a multi-marker line must be REFUSED (id:6059 regression)"
[[ "$(cat "$F")" == "$before" ]] || note "(5b) the refused regex_sub wrote something"

[[ $fail -eq 0 ]] || { echo "FAILED: md-merge insert-relative-to-id / in-lock transform (id:f26d)" >&2; exit 1; }
echo "ALL PASS: md-merge supports insert-relative-to-id and an in-lock regex_sub transform (id:f26d)"

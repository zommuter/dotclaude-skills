#!/usr/bin/env bash
# tests/test_repo_section_quoting_02fe.sh (id:02fe)
#
# A repo name that is not a TOML bare key must survive the relay registry end to end.
# `zom.fi` is the first such name in the fleet; before this fix it failed in two directions,
# both of which this file pins:
#
#   unquoted `[repos.zom.fi]`  -> tomllib nests it (repos/zom/fi), lib-own-repos.sh yields
#                                 NOTHING for the repo, and the own-set reads clean while the
#                                 repo is invisible. SILENT.
#   quoted `[repos."zom.fi"]`  -> tomllib is right, but every writer/matcher that built its
#                                 header as `[repos.$name]` missed the block.
#
# Hermetic: every case runs against a temp $FABLES_CONFIG / $RELAY_TOML. Nothing reads or
# writes the real ~/.config/relay.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$HERE/../relay/scripts"
FAIL=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n     %s\n' "$1" "${2-}" >&2; FAIL=1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── the library itself ──────────────────────────────────────────────────────────────────
# shellcheck source=../relay/scripts/lib-repo-section.sh
. "$SCRIPTS/lib-repo-section.sh"

got="$(repo_section_header zkm)"
[ "$got" = "[repos.zkm]" ] \
  && pass "bare-key name renders bare (no churn for the 63 existing entries)" \
  || fail "bare-key name renders bare" "got: $got"

got="$(repo_section_header zom.fi)"
[ "$got" = '[repos."zom.fi"]' ] \
  && pass "dotted name renders double-quoted" \
  || fail "dotted name renders double-quoted" "got: $got"

# The canonical spelling of a dotted name must be the one tomllib reads back as that name.
got="$(RELAY_HDR="$(repo_section_header zom.fi)" python3 -c '
import os, tomllib
d = tomllib.loads(os.environ["RELAY_HDR"] + chr(10) + "classification = " + chr(34) + "own" + chr(34))
print(",".join(d["repos"].keys()))
')"
[ "$got" = "zom.fi" ] \
  && pass "canonical dotted header round-trips through tomllib as one key" \
  || fail "canonical dotted header round-trips through tomllib" "keys: $got"

# The three spellings TOML considers equivalent are all accepted.
got="$(repo_section_headers zkm | tr '\n' ' ')"
case "$got" in
  *"[repos.zkm]"*) : ;;
  *) fail "accepted set contains the bare form" "got: $got" ;;
esac
case "$got" in
  *'[repos."zkm"]'*) pass "accepted set contains bare and quoted forms for a bare-key name" ;;
  *) fail "accepted set contains the quoted form" "got: $got" ;;
esac

# A dotted name has no bare form, so the set must NOT offer one (it would be a nested table).
grep -qxF "[repos.zom.fi]" < <(repo_section_headers zom.fi) \
  && fail "accepted set must not offer the nested-table spelling for a dotted name" \
  || pass "accepted set omits the nested-table spelling for a dotted name"

# ── relay-state-write.sh toml-set ───────────────────────────────────────────────────────
mk_toml() { mkdir -p "$TMP/cfg"; printf '%s\n' "$@" > "$TMP/cfg/relay.toml"; }

mk_toml '[repos."zom.fi"]' 'classification = "own"' 'status = "pending"'
out="$(FABLES_CONFIG="$TMP/cfg" "$SCRIPTS/relay-state-write.sh" toml-set zom.fi status '"active"' 2>&1)"; rc=$?
if [ $rc -eq 0 ] && grep -qxF 'status = "active"' "$TMP/cfg/relay.toml"; then
  pass "toml-set writes into a quoted section"
else
  fail "toml-set writes into a quoted section" "rc=$rc out=$out file=$(cat "$TMP/cfg/relay.toml")"
fi

# The key must land INSIDE the block, not appended after it. This is the specific way a
# header resolved to the canonical spelling (rather than to the one present in the file)
# would fail: the pre-check passes, then awk never matches and the END rule appends at EOF.
mk_toml '[repos."zom.fi"]' 'classification = "own"' '' '[repos.zkm]' 'classification = "own"'
FABLES_CONFIG="$TMP/cfg" "$SCRIPTS/relay-state-write.sh" toml-set zom.fi last_ckpt '"t1"' >/dev/null 2>&1
if [ "$(awk '/^\[/{n++} n==1 && /^last_ckpt/{print "in"}' "$TMP/cfg/relay.toml")" = "in" ]; then
  pass "toml-set places the key inside the block, not at EOF"
else
  fail "toml-set places the key inside the block" "file: $(cat "$TMP/cfg/relay.toml")"
fi

# A genuinely absent repo must still be REFUSED, loudly. The widened matcher must not have
# turned the pre-check into a no-op.
mk_toml '[repos.zkm]' 'classification = "own"'
out="$(FABLES_CONFIG="$TMP/cfg" "$SCRIPTS/relay-state-write.sh" toml-set nosuch status '"active"' 2>&1)"; rc=$?
if [ $rc -ne 0 ] && grep -q "nosuch" <<<"$out"; then
  pass "toml-set still refuses an absent repo, naming it"
else
  fail "toml-set still refuses an absent repo" "rc=$rc out=$out"
fi

# ── lib-own-repos.sh enumeration ────────────────────────────────────────────────────────
mk_toml '[repos."zom.fi"]' 'classification = "own"' 'path = "/srv/zom.fi"' \
        '' '[repos.zkm]' 'classification = "own"'
# shellcheck source=../relay/scripts/lib-own-repos.sh
RELAY_TOML="$TMP/cfg/relay.toml" SRC_DIR="/src" . "$SCRIPTS/lib-own-repos.sh"
got="$(RELAY_TOML="$TMP/cfg/relay.toml" SRC_DIR="/src" own_repos)"
if grep -qP '^zom\.fi\t/srv/zom\.fi$' <<<"$got"; then
  pass "own_repos enumerates a quoted dotted repo with its explicit path"
else
  fail "own_repos enumerates a quoted dotted repo" "got: $got"
fi

# The `# path:` COMMENT override must apply to a quoted section too. tomllib drops comments,
# so this is the second pass, and it is the one that needed the unquoting fix: the captured
# name carried its delimiters and never matched tomllib's unquoted key.
mk_toml '[repos."zom.fi"]' '# path: /srv/elsewhere' 'classification = "own"'
got="$(RELAY_TOML="$TMP/cfg/relay.toml" SRC_DIR="/src" own_repos)"
if grep -qP '^zom\.fi\t/srv/elsewhere$' <<<"$got"; then
  pass "the # path: comment override applies to a quoted section"
else
  fail "the # path: comment override applies to a quoted section" "got: $got"
fi

# Guard the SILENT direction explicitly: the unquoted spelling must not enumerate the repo.
# If this ever starts passing as `zom.fi`, tomllib changed and the whole premise moved.
mk_toml '[repos.zom.fi]' 'classification = "own"'
got="$(RELAY_TOML="$TMP/cfg/relay.toml" SRC_DIR="/src" own_repos)"
if [ -z "$got" ]; then
  pass "the unquoted dotted spelling still enumerates nothing (the trap this fix routes around)"
else
  fail "the unquoted dotted spelling enumerates nothing" "got: $got"
fi

# ── discover-sig.sh block extraction ────────────────────────────────────────────────────
mk_toml '[repos."zom.fi"]' 'classification = "own"' 'status = "active"' \
        '' '[repos.zkm]' 'classification = "own"'
got="$(RELAY_TOML="$TMP/cfg/relay.toml" bash -c '
  . "$1/lib-repo-section.sh"
  RELAY_TOML="$2"
  wants="$(repo_section_headers zom.fi)"
  awk -v wants="$wants" "BEGIN{hay=\"\n\" wants \"\n\"} index(hay, \"\n\" \$0 \"\n\"){inb=1;print;next} inb && /^[[:space:]]*\[/{inb=0} inb{print}" "$RELAY_TOML"
' _ "$SCRIPTS" "$TMP/cfg/relay.toml")"
if grep -q 'status = "active"' <<<"$got" && ! grep -q 'repos.zkm' <<<"$got"; then
  pass "the block extractor reads a quoted section and stops at the next header"
else
  fail "the block extractor reads a quoted section" "got: $got"
fi

# ── ckpt-tag.sh managed-repo gate ───────────────────────────────────────────────────────
mk_toml '[repos."zom.fi"]' 'classification = "own"'
if ( . "$SCRIPTS/lib-repo-section.sh"; repo_section_grep_file zom.fi "$TMP/cfg/relay.toml" ); then
  pass "the managed-repo gate sees a quoted section (watermark sync no longer skipped)"
else
  fail "the managed-repo gate sees a quoted section"
fi
if ( . "$SCRIPTS/lib-repo-section.sh"; repo_section_grep_file nosuch "$TMP/cfg/relay.toml" ); then
  fail "the managed-repo gate must still reject an unregistered repo"
else
  pass "the managed-repo gate still rejects an unregistered repo"
fi

exit $FAIL

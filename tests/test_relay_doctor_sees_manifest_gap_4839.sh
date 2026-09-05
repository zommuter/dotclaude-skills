#!/usr/bin/env bash
# roadmap:4839
#
# RED SPEC for the TWO AGGRAVATIONS of id:4839 -- the pair that explains why dimension (a)
# went unnoticed for as long as it did.
#
# AGGRAVATION 1: relay-doctor.sh:298 invokes todo-conformance.sh as
#   tc="$(bash "$TODO_CONFORMANCE" "$path/TODO.md" 2>>"$LOG" || true)"
# so BOTH `ratchet INERT -- no baseline` warnings go to ~/.claude/logs/relay-doctor.log and
# never reach the reviewer reading relay-doctor's output. The tool announced its own
# disablement, loudly, to a file nobody was reading.
#
# AGGRAVATION 2: install_drift_check (relay-doctor.sh:589-635) walks the relay_FILES manifest
# but its case arm is `scripts/*|references/*)`, with `*)` an explicit no-op. So the check
# STRUCTURALLY CANNOT see a manifest gap in a non-script file -- it is blind to precisely the
# class of gap that disabled the ratchets. That is not a missed instance, it is a missing
# dimension of the guard, which is why fixing dimension (a) alone leaves the guard just as
# blind to the next one.
#
# TRIANGULATION (id:108e): the fixture declares TWO non-script manifest entries, one present
# and one absent, so a fix that simply reports every non-script entry as missing fails just as
# loudly as one that reports none.
#
# HERMETICITY: a synthetic repo root with its own Makefile and a synthetic install root, both
# under mktemp -d; RELAY_INSTALL_ROOT and RELAY_DOCTOR_LOG are redirected. Never touches
# ~/.claude.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR="$ROOT/relay/scripts/relay-doctor.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
report() { echo "FAIL: $1"; fail=1; }

# relay-doctor sources sibling libraries out of its own scripts dir and resolves the repo root
# by walking up from its own REAL path (readlink -f) to the nearest Makefile. So a fixture repo
# needs: every sibling script reachable (symlinks are fine -- they are only sourced), and
# relay-doctor.sh itself present as a REAL FILE so the walk lands on the FIXTURE's Makefile
# rather than this repo's. Getting this wrong makes the script die at its first `source` and
# every assertion below go red for the wrong reason -- an unreached fixture, not a finding.
stage_scripts() { # <fixture repo root>  [<name of a script to leave out>]
  local dest="$1/relay/scripts" skip="${2:-}" f b
  mkdir -p "$dest"
  for f in "$ROOT"/relay/scripts/*; do
    b="$(basename "$f")"
    [[ -n "$skip" && "$b" == "$skip" ]] && continue
    ln -sfn "$f" "$dest/$b"
  done
  rm -f "$dest/relay-doctor.sh"
  cp "$ROOT/relay/scripts/relay-doctor.sh" "$dest/relay-doctor.sh"
  chmod +x "$dest/relay-doctor.sh"
}

# A fixture whose relay-doctor dies before reaching the check under test is not evidence of
# anything. Every invocation below is screened through this.
assert_ran() { # <label> <output>
  if grep -qE 'No such file or directory|command not found|unbound variable|syntax error' <<<"$2"; then
    report "fixture sanity ($1): relay-doctor died before reaching the check under test -- $(grep -m1 -E 'No such file or directory|command not found|unbound variable|syntax error' <<<"$2"). Every assertion in this section would be red for the wrong reason."
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Aggravation 2 -- install-drift must see a NON-script manifest gap.
# ---------------------------------------------------------------------------
FAKE_REPO="$tmp/repo"
mkdir -p "$FAKE_REPO/relay/scripts" "$FAKE_REPO/relay/references"
cat > "$FAKE_REPO/Makefile" <<'MK'
relay_FILES := SKILL.md \
               references/handoff.md \
               scripts/relay-doctor.sh \
               head-length-baseline.txt \
               shape-prose-baseline.txt
MK
: > "$FAKE_REPO/relay/head-length-baseline.txt"
: > "$FAKE_REPO/relay/shape-prose-baseline.txt"

FAKE_INSTALL="$tmp/skills"
mkdir -p "$FAKE_INSTALL/relay/scripts" "$FAKE_INSTALL/relay/references"
: > "$FAKE_INSTALL/relay/SKILL.md"
: > "$FAKE_INSTALL/relay/references/handoff.md"
: > "$FAKE_INSTALL/relay/scripts/relay-doctor.sh"
# PRESENT non-script entry -- must NOT be reported.
: > "$FAKE_INSTALL/relay/head-length-baseline.txt"
# ABSENT non-script entry -- MUST be reported. This is the live shape.
# (shape-prose-baseline.txt is deliberately not created.)

stage_scripts "$FAKE_REPO"

drift="$(RELAY_INSTALL_ROOT="$FAKE_INSTALL" RELAY_DOCTOR_LOG="$tmp/doctor.log" \
  bash "$FAKE_REPO/relay/scripts/relay-doctor.sh" --only install-drift 2>&1 || true)"

if assert_ran "install-drift" "$drift"; then
  # Matched WITHOUT the dash: relay-doctor spells these with an em dash today and the fleet is
  # mid-migration to `--`, so anchoring on the delimiter would silently stop matching.
  if grep -qE '^SKIP .*no relay install' <<<"$drift" || grep -qE '^WARN .*could not find' <<<"$drift"; then
    report "fixture sanity: install-drift declined to run against the fixture (output: $(head -3 <<<"$drift" | tr '\n' ' ')) -- assertions (a) and (b) would be vacuous"
  elif ! grep -q 'install-drift' <<<"$drift"; then
    report "fixture sanity: the install-drift section did not run at all (output: $(head -3 <<<"$drift" | tr '\n' ' '))"
  else
    # (a) the ABSENT non-script entry must be reported.
    if ! grep -q 'shape-prose-baseline.txt' <<<"$drift"; then
      report "(a) install-drift did not report the missing NON-script manifest entry relay/shape-prose-baseline.txt -- its walk is scoped to scripts/*|references/* and structurally cannot see this class of gap (id:4839 aggravation 2)"
    fi
    # (b) the PRESENT non-script entry must NOT be reported -- a fix that flags every
    # non-script entry regardless of presence is no fix.
    if grep -q 'head-length-baseline.txt' <<<"$drift"; then
      report "(b) install-drift reported relay/head-length-baseline.txt as missing although it IS present in the install tree -- the widened walk does not actually check existence (id:4839 aggravation 2)"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Aggravation 1 -- the INERT warnings must reach relay-doctor's OWN output.
#
# Last in the file on purpose: it is the quietest of the three failures (nothing is wrong with
# the verdict, only with who gets to see it), and it is the one that let the other two survive.
# ---------------------------------------------------------------------------
STUB_REPO="$tmp/stubrepo"
mkdir -p "$STUB_REPO/relay/scripts"
cat > "$STUB_REPO/Makefile" <<'MK'
relay_FILES := SKILL.md
MK
stage_scripts "$STUB_REPO" todo-conformance.sh
# A stand-in todo-conformance that emits ONLY the warning we care about, on stderr, exactly as
# the real one does when it cannot resolve a baseline. This isolates the plumbing question
# (does relay-doctor forward it?) from the baseline question tested elsewhere.
cat > "$STUB_REPO/relay/scripts/todo-conformance.sh" <<'STUB'
#!/usr/bin/env bash
echo "head-length ratchet INERT -- no baseline at /nowhere/head-length-baseline.txt" >&2
echo "shape ratchet INERT -- no baseline at /nowhere/shape-prose-baseline.txt" >&2
exit 0
STUB
chmod +x "$STUB_REPO/relay/scripts/todo-conformance.sh"

# relay-doctor's per-repo scope refuses a path that is not a git repo, so the target is a real
# (empty) one.
TARGET="$tmp/target"
mkdir -p "$TARGET"
git -C "$TARGET" init -q
git -C "$TARGET" config user.email t@example.invalid
git -C "$TARGET" config user.name t
printf -- '- [ ] [ROUTINE] **A well-formed item.** <!-- id:cd34 -->\n' > "$TARGET/TODO.md"
git -C "$TARGET" add -A >/dev/null 2>&1 || true
git -C "$TARGET" commit -qm fixture >/dev/null 2>&1 || true

out="$(RELAY_DOCTOR_LOG="$tmp/doctor2.log" RELAY_INSTALL_ROOT="$FAKE_INSTALL" \
  bash "$STUB_REPO/relay/scripts/relay-doctor.sh" "$TARGET" 2>&1 || true)"

if assert_ran "todo-conformance stderr" "$out"; then
  if ! grep -q 'TODO grammar conformance' <<<"$out"; then
    report "fixture sanity: relay-doctor never reached its TODO-grammar-conformance section for $TARGET (output: $(head -5 <<<"$out" | tr '\n' ' ')) -- assertion (c) would be red for the wrong reason"
  elif ! grep -q 'ratchet INERT' <<<"$out"; then
    extra=" (and it is not in the log either -- check the stub was invoked)"
    grep -q 'ratchet INERT' "$tmp/doctor2.log" 2>/dev/null && extra=" (it went to the log at $tmp/doctor2.log instead)"
    report "(c) relay-doctor's own output does not carry todo-conformance's 'ratchet INERT' warning$extra -- relay-doctor.sh:298 sends that stderr to \$LOG, so the tool's announcement of its own disablement never reaches the reviewer (id:4839 aggravation 1)"
  fi
fi

if [[ "$fail" -eq 0 ]]; then
  echo "PASS: install-drift sees non-script manifest gaps and relay-doctor surfaces todo-conformance stderr (id:4839 aggravations 1+2)"
fi
exit "$fail"

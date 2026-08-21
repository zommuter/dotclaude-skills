#!/usr/bin/env bash
# ckpt-tag.sh — atomic relay checkpoint: RELAY_LOG.md entry + annotated tag.
#
# Usage:
#   ckpt-tag.sh <repo-path> -m "summary paragraph" [-l "reviewer (claude-opus-5)"] [-c <commit>]
#   echo "summary paragraph" | ckpt-tag.sh <repo-path> [-l label]
#
# LABEL FORMAT (id:1a34) — `<role> (<full claude-* model id>[, <extra tokens>])`.
#   The model id MUST be the FULL string, e.g. `reviewer (claude-opus-5)` or
#   `reviewer (claude-opus-4-8, fable-standin, relay-loop)`. A BARE tier name
#   (`reviewer (opus)`, `reviewer (fable)`) does NOT match the detector at the bottom of
#   this script, so it silently fails to advance `last_strong_ckpt` — that mismatch between
#   this usage line and the code is precisely id:1a34. A label with no `claude-*` id is
#   still accepted (it is the correct form for a deliberately non-strong checkpoint such as
#   a reconcile-integrate), but it now WARNS on stderr naming the label.
#
# -c <commit> (id:8e3e): place the annotated tag on <commit> instead of the RELAY_LOG
#   commit / HEAD. Used by the integrator for a ZERO-COMMIT review branch: the checkpoint
#   must anchor on the tip the child actually AUDITED, never on a main HEAD that may have
#   advanced since dispatch (tagging current HEAD would falsely mark unseen commits audited).
#   The RELAY_LOG entry still lands on the current branch as usual.
#
# Under flock (.git/relay-ckpt.lock):
#   1. Ensure .gitattributes has `RELAY_LOG.md merge=union` (created before any
#      executor ever touches the log).
#   2. Append `## YYYY-MM-DD HH:MM — <label>` + the summary to RELAY_LOG.md.
#   3. Commit ONLY those two paths (safe in a dirty tree).
#   4. Annotated tag relay-ckpt-YYYYMMDD-HHMM on that commit, summary as tag
#      message; same-minute collision appends -2, -3, ...
#      (Old `fable-ckpt-*` tags are historical and are NEVER rewritten; readers
#      match both prefixes — see relay-loop.js dual-prefix detection.)
# Prints the tag name on stdout. Pushing is the caller's job (git-lock-push.sh).
set -euo pipefail

repo="${1:?Usage: ckpt-tag.sh <repo-path> [-m summary] [-l label]}"
shift

label="reviewer"
summary=""
tag_commit=""
while getopts "m:l:c:" opt; do
  case "$opt" in
    m) summary="$OPTARG" ;;
    l) label="$OPTARG" ;;
    c) tag_commit="$OPTARG" ;;
    *) echo "Usage: ckpt-tag.sh <repo-path> [-m summary] [-l label] [-c commit]" >&2; exit 1 ;;
  esac
done
[[ -z "$summary" ]] && summary="$(cat)"
[[ -n "$summary" ]] || { echo "ckpt-tag.sh: empty summary" >&2; exit 1; }

git -C "$repo" rev-parse --git-dir >/dev/null

# -c target must resolve to a commit BEFORE we take the lock / write the log (loud reject).
if [[ -n "$tag_commit" ]]; then
  git -C "$repo" rev-parse --verify -q "$tag_commit^{commit}" >/dev/null \
    || { echo "ckpt-tag.sh: -c '$tag_commit' does not resolve to a commit in $repo" >&2; exit 1; }
fi

gitdir="$(git -C "$repo" rev-parse --absolute-git-dir)"
stamp_min="$(date +%Y%m%d-%H%M)"
stamp_human="$(date '+%Y-%m-%d %H:%M')"

(
  flock -x 9

  attrs="$repo/.gitattributes"
  if ! grep -qsE '^RELAY_LOG\.md[[:space:]]+merge=union' "$attrs" 2>/dev/null; then
    printf 'RELAY_LOG.md merge=union\n' >> "$attrs"
  fi

  log="$repo/RELAY_LOG.md"
  if [[ ! -f "$log" ]]; then
    printf '# Relay log <!-- merge=union; append-only — never edit or reorder past entries -->\n' > "$log"
  fi
  printf '\n## %s — %s\n\n%s\n' "$stamp_human" "$label" "$summary" >> "$log"

  # Stage .gitattributes tolerantly: warn on failure (e.g. swallowed by .gitignore)
  # but do NOT abort — the merge=union attr is a nicety, not essential to a checkpoint.
  if ! git -C "$repo" add -- .gitattributes 2>/dev/null; then
    echo "ckpt-tag.sh: WARNING: .gitattributes could not be staged (ignored?); skipping attr — checkpoint will proceed without it" >&2
  fi
  git -C "$repo" add -- RELAY_LOG.md
  if ! git -C "$repo" diff --cached --quiet; then
    git -C "$repo" commit -q -m "relay: checkpoint $stamp_min ($label)"
  fi

  tag="relay-ckpt-$stamp_min"
  n=2
  while git -C "$repo" rev-parse -q --verify "refs/tags/$tag" >/dev/null; do
    tag="relay-ckpt-$stamp_min-$n"
    (( n++ ))
  done
  git -C "$repo" tag -a "$tag" -m "$summary

$label" ${tag_commit:+"$tag_commit"}

  # id:0a3b — sync the relay.toml checkpoint watermark at the choke-point. The 2026-07-01
  # incident: supervised sessions minted tags 1948/2019/2110 via this script while relay.toml
  # stayed at last_ckpt=1635 (only the pool integrator ever wrote it), so the id:e030
  # Fable-recheck queue missed out-of-pool strong checkpoints and relay-doctor check 11
  # validated a stale value. Sync via the flock'd single-writer (relay-state-write.sh,
  # FABLES_CONFIG-overridable): managed repo → last_ckpt, plus last_strong_ckpt/strong_model
  # when the label records a strong model (claude-* that is not sonnet/haiku). NEVER touches
  # fable_rechecked (the integrator owns the id:e030 consume side). Unmanaged repo / missing
  # relay.toml → logged no-op. A sync failure warns loudly but never voids the minted tag.
  cfg="${FABLES_CONFIG:-$HOME/.config/relay}"
  name="$(basename "$(cd "$repo" && pwd)")"
  sw="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/relay-state-write.sh"
  if [[ -f "$cfg/relay.toml" ]] && grep -qxF "[repos.$name]" "$cfg/relay.toml"; then
    "$sw" toml-set "$name" last_ckpt "\"$tag\"" >&2 \
      || echo "ckpt-tag.sh: WARNING: relay.toml last_ckpt sync failed for $name (tag $tag stands)" >&2
    # id:ecce — an INTEGRATE checkpoint (`-l "integrate (<model>)"`) must NEVER advance the
    # strong-audit watermark, even though its label DOES carry a full `claude-*` model id
    # (unlike `executor (sonnet, relay-loop)`/`reconcile (auto/human)`, which are caught by
    # the empty-model branch below). An integrate verifies contract_met and merges, but runs
    # no test-integrity audit, no spec-drift check, no roadmap re-derivation — advancing
    # last_strong_ckpt for it would mark unreviewed work AUDITED (the exact hole observed
    # 2026-07-31: three integrate checkpoints left a 42-commit unreviewed window reading as
    # 0 commits to `/relay review`). So this role-prefix check runs BEFORE model detection,
    # not folded into the "no model id" case.
    if [[ "$label" == integrate* ]]; then
      echo "ckpt-tag.sh: note: label '$label' is a non-strong role (integrate) — strong-watermark sync skipped by design for $name (an integrate performs no audit)." >&2
    else
    # Strong-model detection requires a FULL `claude-*` id in the label (e.g.
    # `reviewer (claude-opus-5)`); a bare tier name like `reviewer (opus)` does NOT match.
    # id:1a34/id:c500 — the three outcomes below are each announced on stderr, because the
    # silent variant is exactly the defect these items exist to kill: before this, a label
    # that produced no match was indistinguishable from a successful sync, so supervised
    # strong checkpoints left last_strong_ckpt stale for days ([[no-swallow-stderr]]).
    model="$(head -n1 < <(grep -oE 'claude-[a-z0-9.-]+' <<<"$label") || true)"
    if [[ -z "$model" ]]; then
      # A model-less label is CORRECT for a deliberately non-strong checkpoint and a DEFECT
      # for a strong one whose label omitted the model id. The label's ROLE PREFIX tells the
      # two apart, so this does NOT need operator judgement in the common case:
      #   `executor (…)`  — the pool's own execute-unit label (`relay-loop.js:2241` emits
      #                     `executor (sonnet, relay-loop)`, a bare tier name by design).
      #                     NEVER strong: id:e030's direction is that an executor checkpoint
      #                     must not advance the strong-audit anchor.
      #   `reconcile (…)` — owner-ratified 2026-07-31 (id:c500 part 1): a reconcile-integrate
      #                     deliberately does NOT count as strong.
      # Both are expected-and-correct, so they get a `note:`. Warning on them would fire on
      # EVERY pool execute integrate — the single most common path in the fleet — and noise on
      # the happy path is how real warnings get ignored (regression introduced 2026-07-31 by
      # id:1a34's loudness fix, caught the same day before it reached a live pool run).
      # Anything else (reviewer / strong-execute / unknown) IS a defect: warn and name it.
      if [[ "$label" == executor* || "$label" == reconcile* ]]; then
        echo "ckpt-tag.sh: note: label '$label' is a non-strong role (executor/reconcile) — strong-watermark sync skipped by design for $name." >&2
      else
        echo "ckpt-tag.sh: WARNING: label '$label' contains no full claude-* model id — strong-watermark sync SKIPPED for $name (last_strong_ckpt/strong_model unchanged; tag $tag stands). A DEFECT if this was a strong review — the label must carry the full id, e.g. -l 'reviewer (claude-opus-5)', not a bare tier name." >&2
      fi
    elif [[ "$model" == *sonnet* || "$model" == *haiku* ]]; then
      # Weak model: skipping is unambiguous (the label names the model), so this is a
      # `note:` like the unmanaged-repo case, not a WARNING — nothing here needs judging.
      echo "ckpt-tag.sh: note: label '$label' names a weak model ($model) — strong-watermark sync skipped by design for $name." >&2
    else
      "$sw" toml-set "$name" last_strong_ckpt "\"$tag\"" >&2 \
        || echo "ckpt-tag.sh: WARNING: relay.toml last_strong_ckpt sync failed for $name" >&2
      "$sw" toml-set "$name" strong_model "\"$model\"" >&2 \
        || echo "ckpt-tag.sh: WARNING: relay.toml strong_model sync failed for $name" >&2
    fi
    fi
  else
    echo "ckpt-tag.sh: note: no [repos.$name] block in $cfg/relay.toml — watermark sync skipped (unmanaged repo)" >&2
  fi

  echo "$tag"
) 9>"$gitdir/relay-ckpt.lock"

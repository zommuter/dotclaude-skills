#!/usr/bin/env bash
# PreToolUse(Bash) guard — owner directive (2026-07): DENY a command that STARTS with `rm`
# (optionally `sudo rm`) invoked with a force flag (-f, -rf, -fr, --force, and flag variants
# a fixed prefix rule would miss, e.g. `rm -vf`, `rm  -f`). Anchored to command START (^) so a
# force flag merely MENTIONED inside a commit message, echo, quoted argument, or embedded
# `&& rm -f` is NOT matched here — those are covered by the permissions `deny` rules and, in
# auto mode, the soft_deny classifier (which parses quoting). Allows `rm --`, `rm -r`, `rm -i`,
# `git rm`. Reads the hook JSON on stdin; emits a PreToolUse deny on a match, else stays silent.
cmd=$(jq -r '.tool_input.command // empty')
if printf '%s' "$cmd" | grep -Eq '^[[:space:]]*(sudo[[:space:]]+)?rm[[:space:]]+([^;&|]*[[:space:]])?(-[A-Za-z]*f|--force)'; then
  printf '%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"rm with a force flag is blocked by owner directive. Use plain rm with the -- separator for a known file, the guarded existence-check idiom for a maybe-absent one, or rm -r -- <dir> for a directory you created."}}'
fi

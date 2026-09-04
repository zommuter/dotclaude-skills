# id:d4ca

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

**EDITED ON RELOCATION (2026-09-02, `id:40c0`) -- the verbatim claim above is amended
for the PROSE THIS PASS APPENDED to `## From ROADMAP`, and for nothing else. Any
prose already in that section arrived by an earlier pass and is untouched here.** Fleet-rule violations found in the relocated
prose were FIXED here rather than parked: 2 punctuation em dashes became `--`. Nothing else changed: no word, figure, marker or line break was
altered, and the appended text is otherwise the ROADMAP.md block verbatim, indentation
included.

## From ROADMAP

🚧 GATED (DEP: id:33b2 — needs the stdin channel BUILT; the decision itself is settled, id:a05c option B — AND id:93ac, the command-fence precedence boundary: converting this hop is exactly what makes 93ac live, since this payload is cross-repo ledger prose) <!-- children-of:6b35 -->  **GATE RE-TARGETED 2026-08-13**: the `gated-on:33b2`/`gated-on:93ac` markers were STALE — both targets are `[x]` DONE and archived to `ROADMAP.archive.md`, which `resolve-gates.sh:36` does NOT include in its resolution set (`ROADMAP.md ∪ TODO.md ∪ TODO.archive.md`), so they read as dangling and the item was blocked by accident rather than on purpose — the `id:47f7`(b) archived-gate class, live. NOT cleared: the 2026-08-12 strong-model audit (`ROADMAP.md:1128`) explicitly declined naive clearing because it would unblock this into dispatch ahead of the unresolved `id:09e4` payload-misdirection while the `id:6b35` cluster is owner-gated on `id:b0b1`. Re-targeted to those two REAL gates, both open and both in `TODO.md` (hence resolvable). This keeps the item blocked — it does NOT make it actionable. <!-- gated-on:09e4 --> <!-- gated-on:b0b1 --> <!-- id:d4ca -->

  - **Why it qualifies**: id:0d31 already collapsed this hop to "pipe one blob to one command" -- `relay-status-publish.sh` does all deterministic work (path resolve + c34a guard, claims peek, burnup render, atomic flock'd write, event append). The Haiku agent contributes nothing but latency, cost, and drift risk on a **write path**, and it fires every round.
  - **Why it is BLOCKED today (verified 2026-07-28, not theorised)**: the payload rides in the command string as a heredoc, and `_command_allowed()` refuses it three independent ways -- `_has_unquoted_sequence_operator` (payload is multi-line), `_has_unquoted_redirection` (`<<'RELAY_STATUS_EOF'`), and the backtick/`$(` substring scan. Those scans are **quote-blind**, so even a safely single-quoted payload is refused; measured against the live predicate: `echo 'a; b; c' | relay-status-publish.sh` → False, `echo 'see \`foo.sh\`' | …` → False, `echo 'run $(date)' | …` → False. A bare `relay-status-publish.sh --path … --run …` with no payload → **True** (the script is already allowlisted), so it is purely the payload transport that fails.
  - **Do NOT "fix" this by flipping the model**: a refused command fail-opens to the real model, and `"bash"` is not a real model → 404. Because status content embeds repo/item prose (the queued / blocked / REVIEW_ME sections routinely carry code spans), this would break the status write on essentially every substantive round. Fail-CLOSED is the property to preserve (id:6b35).
  - **Unblocks when** id:33b2 lands; then the change is: fence carries the bare one-liner, payload moves to the stdin channel, `model: 'bash'`.
  - **Done-check**: `_command_allowed()` accepts the emitted command; a round-trip test writes a status body containing backticks, `$(`, `;` and newlines and asserts the file content is byte-identical to the payload.


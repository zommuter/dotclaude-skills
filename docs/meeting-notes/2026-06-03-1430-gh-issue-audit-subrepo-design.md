# 2026-06-03 — GH-issue audit + sub-repo discovery in orphan check

**Started:** 2026-06-03 14:30
**Session:** 2d930c23-e25f-466e-80c5-59791c538af0
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime, project-standing)
**Topic:** Design F1/F2/F3 — should the orphan-audit read GitHub issues and walk sub-repos, and if so, how?

## Surfaced discoveries
- [2026-05-10 .claude] Bash allowlist glob `*` swallows trailing flags (`gh api gists/*` matched `-X POST`) — read-only enforcement needs a discriminating flag or a known-readonly subresource.
- [2026-05-21 dotclaude-skills] find glob-in-args rejected class-wide; wrapper-script + allowlist-the-path is the pattern (find-todos.sh, broker-curl.sh).
- [2026-05-13 zkm] Central TODO.md is the single ledger; GH-Issues switch is gated on first outside PR/issue (whole-topology trigger).

## Agenda
1. Warrant & timing — is the read side (F1+F2) worth building now? Real N=2 consumers? Does F3 stay gated?
2. Mechanism & placement — extend orphan-scan.sh, or a new sibling script? Reuse find-todos.sh?
3. "Sensibly associated repos" (F2) — concrete discovery + same-namespace rule.
4. Allowlist & read-only safety — gh invocation shape that can't mutate.
5. Correlation — do GH issues map to `<!-- id:XXXX -->` tokens, or is the audit purely informational?

## Discussion

### Agenda 1 — Warrant & timing

🏗️ **Archie:** Live-state check first. Queried all six plugin repos (zkm-{eml,ner,notmuch,pdf,photo,scan}): **zero open issues, zero outside PRs.** So (a) the F3 write-trigger has not fired; (b) F1 — reading `gh issue list` during the audit — would iterate six repos and surface nothing. We would be building a reader for an empty set.

😈 **Riku:** Close to dispositive. The forward-flag was logged 2026-05-13 as a *future* enhancement bundled into the Option-3 topology session that fires on first outside contributor. That contributor still does not exist. Building now is the "observe before preventing" anti-pattern — there is nothing to observe. Minimum evidence that would change the call: one real open issue on one repo. We have none.

✂️ **Petra:** N=2 audit. Consumer 1: zkm (6 repos). Consumer 2: meeting-rpg's `wt/` are worktrees of the *same* repo — no independent issues. dotclaude-skills has no sub-repos. So N=1 (zkm), and that one consumer has zero data. Fails N=2 twice.

⚙️ **Sage:** Cheap-and-durable vs premature: F1/F2 mechanics are non-trivial (new gh-calling script, six allowlist forms, the `.git`-walker, correlation) against an empty input. Near-zero cost and durable: writing the *trigger* and the *design sketch* so the future session is a lookup.

🏗️ **Archie:** Proposed shape: do not build; sharpen the forward-flag with the verified trigger; record the design sketch; record the reuse-pointer.

😈 **Riku:** No probe either — a probe that always returns empty is still surface for zero signal. Design recorded, trigger sharpened, nothing shipped. The trigger *is* the re-check; a date-based re-check on a maybe-never contributor is also waste.

✂️ **Petra:** Capture the reuse: `find-todos.sh` already IS the `.git`-walker F2 wants. When built, F2 is "extend find-todos.sh's walker to emit `git remote` owners," not new infra.

**Decision 1 (Zommuter, ratified via renderer):** Defer build; sharpen trigger + record design sketch + reuse-pointer.

### Agenda 2–5 (consolidated) — The design sketch to record

🏗️ **Archie (placement):** New sibling `gh-orphan-scan.sh` in `meeting/`, NOT a `--gh` flag on `orphan-scan.sh`. orphan-scan is hot, filesystem-only, sub-second, offline; folding network `gh` into it makes every audit network-bound. Separate script keeps orphan-scan fast/offline; the gh audit is opt-in and fails independently. Mirrors find-todos.sh shape (short stdout, allowlisted by path).

⚙️ **Sage (F2 discovery):** Extend the `find-todos.sh` `.git`-pruned walker: for each git dir, `git -C <dir> remote get-url origin`, parse the GitHub owner, keep those matching the root repo's owner. "Sensibly associated" = same `<user>/*` namespace. Origin only; no fork-tracing.

✂️ **Petra (scope fence):** Same-namespace owner-match is the *whole* F2 rule — no language/topic heuristics, no transitive association. Keeps F2 a ~3-line addition.

😈 **Riku (allowlist/read-only):** gists/* lesson: glob `*` swallows trailing flags. Mitigation: call `gh` only from inside `gh-orphan-scan.sh` with a fixed read-only invocation `gh issue list --repo <r> --state open --json number,title,body`; allowlist the script path only (8-form generator entry), never `gh`. Same containment as broker-curl.sh.

🏗️ **Archie (correlation):** (i) Informational: list open issues per repo, no correlation. (ii) Correlated: match `<!-- id:XXXX -->` tokens in issue bodies. Sketch recommendation: **informational-only for v1**; correlation + emitting ids fold into F3 when writing issues is on the table. Reading is useful without correlation.

😈 **Riku (trigger wording):** Open `/meeting gh-issue-audit-impl` on the first open GH issue OR outside PR in the root's `<user>/*` namespace. No date re-check. Verified-empty baseline (6 repos, 0 issues, 0 outside PRs, 2026-06-03) goes in the note.

**Decision 2 (Zommuter, ratified via renderer):** Adopt sketch as described.

## Decisions

- **Defer the build.** No F1/F2/F3 code this session. Baseline: 6 zkm plugin repos, 0 open issues, 0 outside PRs (verified 2026-06-03). *Out of scope:* any shipped code, gh allowlist entries.
- **Design sketch recorded** (placement / F2 walker / allowlist / correlation), as above. *Out of scope:* id-correlation on read (folds into F3).
- **Trigger sharpened:** first open GH issue OR outside PR in the root owner namespace → open `/meeting gh-issue-audit-impl`. *Out of scope:* date-based re-check.
- **Reuse-pointer:** `find-todos.sh` is the F2 `.git`-walker primitive.

**Decision provenance:** ratified by Zommuter (interactive, via renderer decision buttons).

## Action items

- [ ] (deferred — trigger-gated) Build `gh-orphan-scan.sh` per the recorded sketch when the trigger fires. Contract: a sibling script that, given a root, discovers same-owner-namespace associated repos via the find-todos.sh `.git`-walker + `git remote`, lists their open issues read-only (`gh` invoked only inside the script), and emits a short candidate list to stdout; allowlisted by script path; orphan-scan.sh left untouched. Session: 2d930c23 / note: this file. <!-- id:0e3a -->

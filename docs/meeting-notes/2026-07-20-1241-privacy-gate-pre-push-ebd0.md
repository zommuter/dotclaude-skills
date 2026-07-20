# 2026-07-20 — Privacy gate before every public-remote push (ebd0)

**Started:** 2026-07-20 12:41
**Session:** 12ef72b5-5fa2-4b2d-961e-285689eef5ed
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 🛡️ Bastian (leak-boundary), 🔩 Gil (git pre-push plumbing)
**Topic:** Design the pre-push privacy/leak gate — substrate, scanner engine, enforcement posture, remote classification, pattern/allowlist home.

## Surfaced context
- ebd0 was reconciled 2026-07-19 (`docs/meeting-notes/2026-07-19-1212-git-hook-enforcement-substrate-reconciliation.md`) onto the **id:7a05** git-hook framework: "build the framework once there; ebd0 = the privacy pre-push check registering into it."
- `routed:bce3`/id:ce10 (from zelegator): pre-push PII hook importing `scan_pii()`, warn-mode first → calibrate FP → block-with-override.
- Leak specifics + the one **functional author-name match** (must be externalized, not deleted) live in PRIVATE memory `privacy-scan-findings-2026-06-19` — kept OUT of this (public) file by design.
- Motivating recurrence: 2026-06-30 a session committed portfolio-specific terms into this public repo while *filing privacy items*, with no leak check.

## Agenda
1. Ship a standalone pre-push hook now, or gate ebd0 on the unbuilt 7a05 substrate?
2. Scanner engine: reuse zelegator `scan_pii()`, new pattern set, or hybrid — and how to couple?
3. Enforcement posture: warn-first vs block-with-override.
4. Remote classification + where patterns/allowlist live.

## Discussion
**🏗️ Archie:** Two independent concerns hide in ebd0 — the *engine* (a pure function: diff text → leak findings) and the *install substrate*. The substrate the reconcile note names, global `core.hooksPath`, is exactly what a standalone `pre-push` hook installs into *and* what 7a05 will later own. A `pre-push` hook receives `<local-ref> <local-sha> <remote-ref> <remote-sha>` on stdin + the remote name/URL as argv, so it can compute the outgoing diff per ref and decide publicness at hook time.

**🔩 Gil:** A raw `git push` or a background agent bypasses `git-lock-push.sh`, so wiring the check there under-covers. Only a real `core.hooksPath` pre-push hook covers *all* pushes. Diff-scope: `git diff <remote-sha>..<local-sha>` per ref (whole range when `remote-sha` is `000…` for a new branch), scan **added lines only**. The standalone-now install and the 7a05 endgame are the *same surface* — 7a05 later becomes a multiplexer under that hooksPath. Shipping now is not throwaway.

**✂️ Petra:** That dissolves the sequencing tension, and N=2 fails for gating-on-7a05: 7a05's other children (07dc box-hygiene, ledger invariants) are pre-**commit** ledger checks; ebd0 is a pre-**push** leak check keyed on remote publicness — different trigger, different data. Don't couple a HIGH-PRIORITY security fix to an unbuilt design-heavy substrate. Migration later = "move script under 7a05's hook dir + register," not a rewrite.

**🛡️ Bastian:** The leak *classes* dominate the engine choice. The 2026-06-19 scan found the portfolio-name / project-alias vector and a **functional author-name match** — none of which a generic PII detector (emails/phones/SSNs) catches. So `scan_pii()` covers at most the PII overlap; the fleet-specific classes (project names, home paths, hostnames, the author name) are bespoke and must be sourced from a **private** file, never hardcoded in a public hook. The allowlist lives in that same private source: the functional author-name gets an allowlist entry so it doesn't fire — externalized, not deleted.

**😈 Riku (pre-emption, profile high-confidence "identity-resolution conservatism / loud-but-report-only"):** (1) A hook that **blocks** on a false positive halts a real push — contradicts the documented preference for loud-but-report-only detectors that never auto-block real work (orphan-scan ADVISORY, health detectors). Ship **warn-mode first**; and because most pushes here are non-interactive (agents, background `git-lock-push`), a printed-only warning is *silent* — warn-mode must **log** hits (ref + timestamp + finding) so FP calibration data accrues (build the logger first). (2) A hard `import scan_pii` makes **every push in every repo depend on zelegator being present + import-stable** — move it or change the signature and the whole fleet's push path breaks. Best-effort **shell-out if present**, never a hard cross-repo import.

**🏗️ Archie (synthesis):** `hooks/pre-push-privacy-gate.sh` — reads patterns+allowlist from a private source, classifies the remote from its URL (public forge → gate; private host e.g. fievel → skip), scans added diff lines, in warn-mode **appends findings to a log + prints loudly, exit 0**; a `RELAY_PRIVACY_GATE=block` flip makes it blocking-with-loud-override after calibration. Public repo ships mechanism + a generic `~/.claude/CLAUDE.md` rule only.

## Decisions
- **D1 — Ship standalone now; 7a05 adopts later.** Build `hooks/pre-push-privacy-gate.sh` + a global `core.hooksPath` install (make target) NOW. It installs into the same hooksPath surface id:7a05 will later own, so 7a05 adoption is "move under its hook dir + register," not a rewrite. **Out of scope:** building 7a05 itself; ebd0 does NOT gate on it.
- **D2 — Bespoke fleet-specific pattern set is the engine core; zelegator `scan_pii()` is best-effort augmentation only.** The fleet-specific classes (project/portfolio names, home-dir paths, hostnames, the functional author-name, session UUIDs, secret/token patterns) are the bespoke core, sourced from a PRIVATE file. `scan_pii()` is shelled out to **iff present** for the PII overlap — never a hard import (no cross-repo dependency in the push path). **Out of scope:** vendoring/copying scan_pii.
- **D3 — Warn+log first, flip to block-with-override after FP calibration.** Warn-mode prints loudly AND appends findings (ref+timestamp+finding) to a log, `exit 0` — never auto-blocks (works for non-interactive/agent pushes). Accrue FP data from the log, then flip to block-with-loud-override once the FP rate is known-low (observe-before-preventing; build the logger first). **Out of scope:** blocking on day one.
- **D4 — Patterns + allowlist live in a NEW private `~/.config/` file; public repo ships mechanism only.** The hook reads leak patterns + the allowlist (incl. the functional author-name allowlist entry) from a git-untracked private file under `~/.config/`. Independent of id:2a3d's glossary schema (the hook just reads a private file). Public repo ships the mechanism + a generic `~/.claude/CLAUDE.md` rule; **no leak specifics in any public file.** **Out of scope:** deciding the id:2a3d glossary schema, or folding the pattern source into relay.toml.

## Action items
- [ ] Build `hooks/pre-push-privacy-gate.sh` (warn+log engine; remote-URL public/private classification; added-diff-lines scan; reads private pattern/allowlist file; best-effort `scan_pii` shell-out) + a `make install-privacy-gate` target wiring global `core.hooksPath`; ship warn+log mode (exit 0). Contract: a test fixture with a seeded leak pattern in an added line → hook logs+prints the finding, exits 0, and SKIPs when the remote URL is a known private host. Public repo carries mechanism + a generic `~/.claude/CLAUDE.md` rule only. (2026-07-20 meeting, reuses id:ebd0) <!-- id:ebd0 -->
- [ ] Create + populate the PRIVATE `~/.config/` pattern+allowlist file from `privacy-scan-findings-2026-06-19` (incl. the functional author-name allowlist entry) — manual/hands, sources private memory, never committed to any repo. Gated on the ebd0 hook reading a private-file path. (2026-07-20 meeting) <!-- id:7fff -->
- [ ] Flip the gate from warn+log to block-with-loud-override once the warn-mode log shows a known-low FP rate — calibration-gated follow-up (observe-first; pre-register the FP threshold before flipping). Gated on ebd0 warn-mode shipping + accruing a calibration window. (2026-07-20 meeting) <!-- id:df87 -->
- Forward-flag (no new id): when id:7a05 lands, adopt ebd0's pre-push hook as a registered check under 7a05's hooksPath multiplexer — recorded in 7a05's item, not minted here.

## Decision provenance
Ratified by Zommuter via `AskUserQuestion` on 2026-07-20: D1 "Ship standalone now", D2 "Bespoke set + optional scan_pii", D3 "Warn+log first, block later", D4 "New private ~/.config file"; closure "Wrap up and record".

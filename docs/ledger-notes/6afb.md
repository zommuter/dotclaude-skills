# id:6afb

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

## From TODO

(owner 2026-07-20 — "for now I only added little additional info") — top up `~/.config/dotclaude-skills/privacy-patterns.txt` over time with additional identity/leak patterns + `allow:` entries as false-positives or new leak vectors appear in `~/.claude/logs/privacy-gate.log`. NOT a blocker for anything (the gate + core patterns are live); pure incremental curation, hands-only, private file never committed. Feeds the id:df87 FP-calibration window. **GATED ON LOG VOLUME 2026-08-14 (`/relay human .`, OWNER-DECIDED: "Gate it on log volume").** The item had no done-state and no evidence to curate from — `~/.claude/logs/privacy-gate.log` holds **4 lines** (2 fixture-remote + 2 real, from one `zkm-whatsapp` push on 2026-08-11). Curating patterns from that is guessing, not calibration. **Blocked until the gate log reaches ≥50 entries**; check with `wc -l ~/.claude/logs/privacy-gate.log`. This makes "not yet actionable" mechanically visible instead of a judgment call re-made every `/relay human` pass, and it keeps the item off the you-run-these list until it can actually be done. Still non-gating for everything else; still feeds the `id:df87` FP-calibration window. NOTE: deliberately NO `gated-on:` marker — that edge type takes a 4-hex id, and this gate is a measured threshold, not another item; a fake token there would break `lib-typed-edges.sh` and draw a DEAD-GATE from `roadmap-lint`. <!-- id:6afb -->

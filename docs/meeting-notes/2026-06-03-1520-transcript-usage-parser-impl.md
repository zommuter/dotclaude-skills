# 2026-06-03 — Transcript-usage parser implementation

**Started:** 2026-06-03 15:20
**Session:** d627d30b-27d7-4feb-b4cf-29467285f1dc
**Mode:** Class 2 planning record (no meeting was held — Class 1 impl dispatch)
**Topic:** Implement transcript-usage parser: replace SIZE_KB/4 approximation in cost-of.sh and meeting-cost-logger.sh with real jq-parsed usage fields.

## Context

TODO item `<!-- id:d0ed -->` from `docs/meeting-notes/2026-06-03-1452-llm-proxy-token-ctx-and-persona-split.md`. Decisions in that meeting specified the exact implementation: parse `.message.usage` objects from each `type == "assistant"` line in the session `.jsonl`, summing `input_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`, and `output_tokens`. The meeting note confirmed that `meeting-cost-logger.sh` already receives and greps `transcript_path` (`:27-28`) — wiring existed, just needed a jq pass.

## Plan

1. Probe actual jsonl structure to confirm field paths (`jq -c 'select(.message.usage != null)'`).
2. Rewrite `cost-of.sh` usage section with `jq -rs` slurp pass over `.jsonl`.
3. Extend `meeting-cost-logger.sh` with the same jq pass; append four new CSV columns; update format comment.
4. Test both scripts against a real session.

## Implementation findings

- Usage lives at `.message.usage` (not top-level); filtered by `.type == "assistant"` — snapshot updates (`type == "file-history-snapshot"`) carry no usage and are cleanly excluded.
- `jq -s` without `-r` wraps the interpolated string in JSON quotes, causing arithmetic parse errors in bash `read`. Fix: `jq -rs` (raw + slurp).
- Real session test (3f1c211c, 144 turns, 368 KB): `input=92  cache_read=2560432  cache_create=424804  output=75034` — confirmed realistic numbers (high cache_read expected for a long session).
- `meeting-cost-logger.sh` Stop-hook test: new log line format verified (`...,92,2560432,424804,75034`).

## Decisions

- `cost-of.sh` now prints `Input tokens: TOTAL (uncached=N cache_read=N cache_create=N)` + `Output tokens: N`, replacing `Approx tokens: ~Nk`. Size field retained for reference.
- `meeting-cost-logger.sh` log format extended to 10 columns: `iso_ts,session_id,project_dir,turns,kb,was_meeting,input_tok,cache_read_tok,cache_create_tok,output_tok`. Pre-existing log rows have 6 columns; old and new rows coexist (readers can handle both widths via `awk -F,` field count check or `NF==10`).

## Action items

- [x] Rewrite `meeting/cost-of.sh` to sum real usage fields via jq. <!-- id:d0ed -->

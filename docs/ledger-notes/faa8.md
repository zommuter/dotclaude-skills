# id:faa8

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

## From TODO

(observed 2026-08-23). Invoked as `git-lock-push.sh --remote github --ff-only`, it hit a diverged `origin`, printed `WARNING: ff-only pull failed (remote diverged). Commit saved locally, not pushed.` — and returned **rc=0**. `git ls-remote github refs/heads/main` proved the public mirror was untouched. A caller that checks the exit code (every automated caller, including the `git-diary-workflow` SOP that runs after EVERY prompt in EVERY session) concludes the push succeeded. **This is the silent-failure class `id:4347` bans**, in the one script the whole fleet routes pushes through. **Fix:** return non-zero when the push did not happen. Distinguish the three outcomes — pushed / nothing-to-push (legitimately 0) / could-not-push (non-zero) — because collapsing the last two into 0 is exactly the bug. RED spec: stub a diverged remote, assert rc != 0 while stderr still carries the WARNING. Relates `id:f5d9`(a), `id:b4dd`, `id:4347`, `id:475d` (the sibling defect that triggered this instance). <!-- id:faa8 -->

<!-- dotclaude-skills:lane-vocab-ratchet-rule -->
## Old-vocab lane-tag ratchet pre-commit gate

A global `pre-commit` hook (git `core.hooksPath` → dotclaude-skills
`hooks/pre-commit-lane-vocab.sh`) BLOCKS a commit whose staged diff ADDS a lane-tag
line using the old venue-keyed vocabulary (`[HARD — pool|meeting|hands|decision gate]`)
— exit nonzero, naming the new capability-keyed replacement (`relay/scripts/lane-convert.sh`'s
mapping). Pre-existing old-vocab tags in unchanged/context lines are grandfathered
(warn only, never block); new-vocab tags never fire. Self-gated to relay-onboarded
repos (relay.toml own-set) — a no-op elsewhere. `git commit --no-verify` is the
escape hatch. Managed by dotclaude-skills: `make install-lane-ratchet` installs the
hook and appends this rule.

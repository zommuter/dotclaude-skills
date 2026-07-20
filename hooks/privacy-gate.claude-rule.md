<!-- dotclaude-skills:privacy-gate-rule -->
## Privacy pre-push gate

A global `pre-push` hook (git `core.hooksPath` → dotclaude-skills
`hooks/pre-push-privacy-gate.sh`) scans every push to a **public** remote for
personal-identity leaks — names, emails, phone, address, home-dir paths, secrets,
session UUIDs — using patterns from the **private, never-committed**
`~/.config/dotclaude-skills/privacy-patterns.txt`. It runs **warn+LOG only** (appends
to `~/.claude/logs/privacy-gate.log`, exit 0, never blocks; block mode is tracked as
dotclaude-skills id:df87), and skips private/LAN remotes. **Do not treat it as a safety
net** — never put personal identity strings in a public-repo commit in the first place;
check the diff before publishing to a public remote. Managed by dotclaude-skills:
`make install-privacy-gate` installs the hook and appends this rule.

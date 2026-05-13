# TODO — git-diary-workflow

## Current
- [ ] git-lock-push.sh fails with `fatal: couldn't find remote ref claude` when the current branch has no upstream yet (first push on a new branch). Workaround: fall back to plain `git push` or `git push --set-upstream origin <branch>`. Fix: detect "no upstream" exit code in git-lock-push.sh and run `git push --set-upstream origin $(git rev-parse --abbrev-ref HEAD)` instead.

## Done

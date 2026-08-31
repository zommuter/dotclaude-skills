#!/usr/bin/env bash
# tests/lib/hermetic-git-env.sh — neutralize the DEVELOPER's global git hooksPath
# for every git invocation this process spawns (id:4d1c).
#
# Sourceable bash library, `set -euo pipefail`-compatible. Sourcing has exactly
# one side effect: it exports the three GIT_CONFIG_COUNT/KEY_0/VALUE_0 vars
# below into the CURRENT shell (and everything it execs).
#
# Why this exists: a test that builds a throwaway git fixture repo and then
# `git init`/`git commit`s into it inherits the developer's REAL global
# `core.hooksPath` (e.g. this repo's own hooks/pre-commit-lane-vocab.sh /
# pre-push-privacy-gate.sh, installed via `make install-lane-ratchet` /
# `make install-privacy-gate`) unless that config is overridden. If the
# fixture's own relay.toml happens to mark the throwaway repo as "own" (some
# fixtures do this on purpose, to exercise the hook's own logic directly), the
# REAL installed hook fires on the test's OWN fixture commits and can block
# them — a test-harness leak, not a defect in the code under test. Running the
# same test file through `tests/run-tests.sh` was silently immune to this
# because run-tests.sh sets this override for the whole suite; running the
# file DIRECTLY (`bash tests/test_foo.sh`) was not, which made "run the one
# test" an unreliable verification method (MEASURED 2026-08-31, id:4d1c).
#
# `GIT_CONFIG_COUNT`/`_KEY_N`/`_VALUE_N` (git >= 2.31) OVERRIDES, never
# mutates, the developer's actual global config, and is scoped to this
# process's environment only — no `~/.gitconfig`/`~/.config/git/*` write.
#
# Usage: source this file near the top of any test that builds a fixture git
# repo, right after `set -euo pipefail`:
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/hermetic-git-env.sh"

export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=core.hooksPath
export GIT_CONFIG_VALUE_0=/dev/null

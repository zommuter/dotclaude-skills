#!/usr/bin/env bash
# Defect-fix test (no roadmap item — failures always count).
#
# BUG (observed 2026-08-10 on fievel, ~/src/yinyang-puzzle): git-lock-push.sh gated the
# ENTIRE push on `ssh-add -l` succeeding, before it looked at any remote. fievel's repos
# push to LOCAL BARE PATHS (/home/tobias/src/<repo>.git) and fievel runs no ssh-agent at
# all, so the guard fired on 100% of runs — every push skipped with "no SSH key loaded in
# agent", commits accumulating locally forever, while a plain `git push origin main`
# succeeded instantly.
#
# CONTRACT:
#   1. local (non-SSH) remote + no ssh-agent  → PUSHES (the regression)
#   2. SSH remote + no ssh-agent              → skipped, exit 0, work stays committed
#   3. mixed local + SSH, no agent            → local pushes, SSH skipped, exit 0
#   4. `no_push` pushurl                      → still skipped (unchanged)
#   5. agent WITH a key                       → SSH remote pushes (unchanged behaviour)
#   6. URL matcher tested DIRECTLY: scp-style git@host:path is SSH; https://user@host/…
#      and /abs/paths containing '@' are NOT (a false positive silently stops pushing).
#   7. remote-touching git calls carry GIT_SSH_COMMAND — `git ls-remote` used to run
#      without it, which is the real interactive-prompt/hang hole the blanket guard was
#      papering over.
#
# Hermetic: no network. "no ssh-agent" is simulated with an `ssh-add` shim that exits 2
# (the "could not open a connection to your authentication agent" case); the SSH transport
# uses an `ssh` shim serving `git shell` locally.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/git-diary-workflow/git-lock-push.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
export GIT_LOCK_PUSH_TIMEOUT=20

bin="$tmp/bin"
mkdir -p "$bin"
# Fake ssh: serve the requested git command locally, so ssh:// URLs work with no network.
cat > "$bin/ssh" <<'EOF'
#!/usr/bin/env bash
cmd="${!#}"
exec git shell -c "$cmd"
EOF
# Fake ssh-add: honours SSH_ADD_RC so a test can present "no agent" (2) or "key loaded" (0).
cat > "$bin/ssh-add" <<'EOF'
#!/usr/bin/env bash
exit "${SSH_ADD_RC:-2}"
EOF
chmod +x "$bin/ssh" "$bin/ssh-add"
export PATH="$bin:$PATH"

fails=0

# make_repo <name> — repo cloned from a local bare remote, with one unpushed commit.
make_repo() {
  local name="$1" bare="$tmp/$1.git" repo="$tmp/$1"
  git init -q --bare "$bare"
  git clone -q "$bare" "$repo" 2>/dev/null
  printf 'base\n' > "$repo/f.txt"
  git -C "$repo" add f.txt
  git -C "$repo" commit -q -m seed
  git -C "$repo" push -q origin HEAD 2>/dev/null
  git -C "$repo" branch --set-upstream-to="origin/$(git -C "$repo" rev-parse --abbrev-ref HEAD)" >/dev/null 2>&1
  printf 'base\nlocal\n' > "$repo/f.txt"
  git -C "$repo" add f.txt
  git -C "$repo" commit -q -m "local change to push"
}

# pushed <repo> <remote> — did <remote> receive the local tip?
pushed() {
  local repo="$1" remote="$2" branch
  branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD)"
  [[ "$(git -C "$repo" rev-parse HEAD)" == "$(git -C "$repo" ls-remote "$remote" "refs/heads/$branch" | cut -f1)" ]]
}

# --- 1. local bare remote, NO agent → must PUSH (the regression) ---
make_repo local_only
SSH_ADD_RC=2 bash "$SCRIPT" "$tmp/local_only" >"$tmp/out1" 2>"$tmp/err1"
rc=$?
if ! pushed "$tmp/local_only" origin; then
  echo "FAIL(1): local bare remote + no ssh-agent did NOT push (rc=$rc)."
  echo "         The SSH-key guard must be per-remote, not per-run — a path remote needs no SSH."
  sed -n '1,10p' "$tmp/err1"
  fails=1
fi

# --- 2. SSH remote, NO agent → skipped, exit 0, work stays committed ---
make_repo ssh_only
git -C "$tmp/ssh_only" remote set-url --push origin "ssh://fakehost$tmp/ssh_only.git"
head_before="$(git -C "$tmp/ssh_only" rev-parse HEAD)"
SSH_ADD_RC=2 bash "$SCRIPT" "$tmp/ssh_only" >"$tmp/out2" 2>"$tmp/err2"
rc=$?
if [[ $rc -ne 0 ]]; then
  echo "FAIL(2): SSH remote with no agent must exit 0 (non-fatal), got rc=$rc."
  fails=1
fi
if [[ "$(git -C "$tmp/ssh_only" rev-parse HEAD)" != "$head_before" ]]; then
  echo "FAIL(2): the local commit did not survive the skipped push."
  fails=1
fi
if ! grep -qi 'skipping remote' "$tmp/err2"; then
  echo "FAIL(2): skipping an SSH remote must say so on stderr; got:"
  sed -n '1,10p' "$tmp/err2"
  fails=1
fi

# --- 3. mixed local + SSH, no agent → local pushes, SSH skipped, exit 0 ---
make_repo mixed
git init -q --bare "$tmp/mixed_ssh.git"
git -C "$tmp/mixed" remote add sshr "ssh://fakehost$tmp/mixed_ssh.git"
# 'sshr' has no branch yet → the script takes its --set-upstream path; it must still be skipped.
SSH_ADD_RC=2 bash "$SCRIPT" "$tmp/mixed" >"$tmp/out3" 2>"$tmp/err3"
rc=$?
if [[ $rc -ne 0 ]]; then
  echo "FAIL(3): mixed remotes with no agent must exit 0, got rc=$rc."
  fails=1
fi
if ! pushed "$tmp/mixed" origin; then
  echo "FAIL(3): the LOCAL remote must still be pushed when a sibling SSH remote is skipped."
  sed -n '1,10p' "$tmp/err3"
  fails=1
fi
if [[ -n "$(git -C "$tmp/mixed" ls-remote sshr 2>/dev/null)" ]]; then
  echo "FAIL(3): the SSH remote was pushed despite no key in the agent."
  fails=1
fi

# --- 4. no_push pushurl → still skipped ---
make_repo nopush
git -C "$tmp/nopush" remote add guard /dev/null
git -C "$tmp/nopush" config remote.guard.pushurl no_push
SSH_ADD_RC=2 bash "$SCRIPT" "$tmp/nopush" >"$tmp/out4" 2>"$tmp/err4"
rc=$?
if [[ $rc -ne 0 ]]; then
  echo "FAIL(4): a no_push remote must not break the run (rc=$rc)."
  sed -n '1,10p' "$tmp/err4"
  fails=1
fi
if grep -q "remote 'guard'" "$tmp/err4"; then
  echo "FAIL(4): no_push remote must be skipped BEFORE the SSH gate, silently."
  fails=1
fi

# --- 5. agent WITH a key → SSH remote pushes (unchanged behaviour) ---
make_repo ssh_keyed
git -C "$tmp/ssh_keyed" remote set-url --push origin "ssh://fakehost$tmp/ssh_keyed.git"
SSH_ADD_RC=0 bash "$SCRIPT" "$tmp/ssh_keyed" >"$tmp/out5" 2>"$tmp/err5"
rc=$?
if ! pushed "$tmp/ssh_keyed" origin; then
  echo "FAIL(5): SSH remote with a loaded key must push as before (rc=$rc)."
  sed -n '1,10p' "$tmp/err5"
  fails=1
fi

# --- 6. the URL matcher, tested DIRECTLY ---
# Source just the matcher out of the script (it is a self-contained function).
sed -n '/^is_ssh_url()/,/^}/p' "$SCRIPT" > "$tmp/matcher.sh"
if [[ ! -s "$tmp/matcher.sh" ]]; then
  echo "FAIL(6): no is_ssh_url() function found in $SCRIPT to test directly."
  fails=1
else
  # shellcheck disable=SC1090
  . "$tmp/matcher.sh"
  check_url() { # <url> <expect: ssh|not>
    local url="$1" expect="$2" got=not
    is_ssh_url "$url" && got=ssh
    if [[ "$got" != "$expect" ]]; then
      echo "FAIL(6): is_ssh_url '$url' → $got, expected $expect"
      fails=1
    fi
  }
  check_url "ssh://git@github.com/u/r.git"        ssh
  check_url "git@github.com:u/r.git"              ssh
  check_url "github.com:u/r.git"                  ssh
  check_url "https://github.com/u/r.git"          not
  check_url "https://user@github.com/u/r.git"     not   # must NOT be read as scp-style
  check_url "http://host/u/r.git"                 not
  check_url "git://host/u/r.git"                  not
  check_url "file:///home/t/src/r.git"            not
  check_url "/home/t/src/r.git"                   not
  check_url "/home/t/src/weird@name/r.git"        not   # local path containing '@'
  check_url "./rel/r.git"                         not
  check_url "../r.git"                            not
fi

# --- 7. remote-touching git calls carry GIT_SSH_COMMAND (structural) ---
# The pull path's ls-remote/fetch and the push loop's pre-push ls-remote must inherit it;
# a per-`git push` assignment leaves those calls able to prompt or hang unbounded.
if ! grep -qE '^export GIT_SSH_COMMAND=' "$SCRIPT"; then
  echo "FAIL(7): GIT_SSH_COMMAND must be EXPORTED (not set per-push) so ls-remote/fetch"
  echo "         inherit BatchMode/ConnectTimeout instead of being able to prompt or hang."
  fails=1
fi
if ! grep -qE '^export GIT_TERMINAL_PROMPT=0' "$SCRIPT"; then
  echo "FAIL(7): GIT_TERMINAL_PROMPT=0 must be exported (BatchMode does not cover HTTPS)."
  fails=1
fi

[[ $fails -eq 0 ]] && echo ok
exit $fails

#!/usr/bin/env bash
# roadmap:3273 — git-lock-push.sh push path bounds ONLY the TCP connect
# (`-o ConnectTimeout=10`). An ESTABLISHED ssh whose network dies mid-push
# (observed 2026-07-12 on zomni: a dock-ethernet flap; the push hung 40+ min while
# holding the per-repo flock, starving every other lock user). ConnectTimeout does
# NOT bound an already-connected transfer, so the push hangs indefinitely.
#
# Contract (mirrors the same-day sessions-backup.sh hardening):
#   1. Behavioral — a push whose transport stalls AFTER connecting must NOT hang
#      the script indefinitely: the script self-terminates within a bounded wall
#      time (a hard `timeout` around `git push`). The load-bearing property is
#      "returns", not the exact exit code.
#   2. Structural — the push ssh command carries ServerAliveInterval +
#      ServerAliveCountMax so a dead ESTABLISHED connection is torn down (the
#      belt to the `timeout` suspenders; not exercisable against a local fake ssh,
#      so asserted by inspecting the built command).
#
# Hermetic: no network. A fake `ssh` on PATH serves git-upload-pack (ls-remote /
# fetch / pull) LOCALLY via `git shell`, but SLEEPS on git-receive-pack (push) —
# i.e. the connect + ref advertisement succeed, then the push transfer stalls,
# exactly the observed failure. A fake `ssh-add` satisfies the key-loaded gate.
# The fix reads a `GIT_LOCK_PUSH_TIMEOUT` seam so the test can pick a short bound.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/git-diary-workflow/git-lock-push.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com

# --- PATH shims: hanging ssh (push) + no-op ssh-add ---
bin="$tmp/bin"
mkdir -p "$bin"
cat > "$bin/ssh" <<'EOF'
#!/usr/bin/env bash
# Fake ssh: the remote command is the LAST argument. Serve upload-pack locally
# (so ls-remote/fetch/pull work), but hang on receive-pack (simulate an
# ESTABLISHED connection dying mid-push — connect succeeded, transfer stalls).
cmd="${!#}"
case "$cmd" in
  *git-receive-pack*) sleep 3600 ;;
  *) exec git shell -c "$cmd" ;;
esac
EOF
cat > "$bin/ssh-add" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$bin/ssh" "$bin/ssh-add"
export PATH="$bin:$PATH"

# --- Repo + bare remote reached over the fake ssh transport ---
bare="$tmp/remote.git"
git init -q --bare "$bare"

repo="$tmp/repo"
git clone -q "$bare" "$repo"
printf '# file\nbase\n' > "$repo/f.txt"
git -C "$repo" add f.txt
git -C "$repo" commit -q -m seed
git -C "$repo" push -q origin HEAD:master 2>/dev/null || git -C "$repo" push -q origin HEAD:main
branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD)"
git -C "$repo" branch --set-upstream-to="origin/$branch" >/dev/null 2>&1 || true
# Point origin at an ssh:// URL so the transport goes through the fake ssh.
git -C "$repo" remote set-url origin "ssh://fakehost$bare"

# A local commit to push (legacy mode: commit already made, only pull+push run).
printf '# file\nbase\nlocal change\n' > "$repo/f.txt"
git -C "$repo" add f.txt
git -C "$repo" commit -q -m "local change to push"

fails=0

# --- 1. Behavioral: the script must SELF-TERMINATE, not hang ---
# The fix bounds the push via a `timeout` reading the GIT_LOCK_PUSH_TIMEOUT seam;
# the test picks 3s and an outer safety net of 20s. Buggy code ignores the seam and
# hangs at push (fake sleep 3600) → the outer 20s net fires; the fix returns in ~3s.
start=$(date +%s)
GIT_LOCK_PUSH_TIMEOUT=3 timeout 20 bash "$SCRIPT" "$repo" --ff-only >"$tmp/out" 2>"$tmp/err"
rc=$?
end=$(date +%s)
elapsed=$((end - start))

if [[ $elapsed -ge 12 ]]; then
  echo "FAIL: git-lock-push did NOT self-bound a stalled push — ran ${elapsed}s (rc=$rc)."
  echo "      A push whose ESTABLISHED transport dies must be killed by a hard timeout,"
  echo "      not hang while holding the flock (roadmap:3273)."
  echo "--- stderr ---"; sed -n '1,20p' "$tmp/err"
  fails=1
fi

# --- 2. Structural: ServerAlive keepalives on the push ssh command ---
if ! grep -q 'ServerAliveInterval' "$SCRIPT" || ! grep -q 'ServerAliveCountMax' "$SCRIPT"; then
  echo "FAIL: push ssh command lacks ServerAliveInterval/ServerAliveCountMax — a dead"
  echo "      ESTABLISHED connection is never torn down by ssh itself (roadmap:3273)."
  fails=1
fi

[[ $fails -eq 0 ]] && echo ok
exit $fails

set -euo pipefail
R="$1"; mkdir -p "$R"; cd "$R"
git init -q
git config user.email canary@test; git config user.name canary
git config commit.gpgsign false
co() { git add -A; git commit -q --no-gpg-sign -m "$1"; }
ck() { git tag -a "relay-ckpt-$1" -m "checkpoint $1"; }   # annotated relay checkpoint
printf '# ROADMAP\n\n- [ ] [ROUTINE] do the thing <!-- id:0002 -->\n' > ROADMAP.md
co "init"; ck "20260617-1200"
printf 'uncommitted edit\n' >> ROADMAP.md   # leave dirty

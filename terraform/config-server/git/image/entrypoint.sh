#!/bin/sh
# Create + seed the bare repo, then serve it over smart HTTP. Idempotent: on an emptyDir the
# repo is created fresh each start; on a persistent volume an existing repo is left alone.
set -eu

GIT_ROOT="${GIT_ROOT:-/srv/git}"
REPO_NAME="${REPO_NAME:-config.git}"
REPO="${GIT_ROOT}/${REPO_NAME}"

mkdir -p "$GIT_ROOT"

if [ ! -d "$REPO" ]; then
  git init --bare "$REPO" >/dev/null
  # Anonymous PUSH: git-http-backend only serves receive-pack for repos that opt in.
  git -C "$REPO" config http.receivepack true
  # A bare repo rejects pushes to the checked-out branch by default; there is no work tree
  # here, but be explicit so a push to the default branch is always accepted.
  git -C "$REPO" config receive.denyCurrentBranch ignore
  # Seed one empty commit so `git clone` on a spoke succeeds before terraform's first push
  # (an empty repo clones to a branchless work tree and the poller's `git -C pull` errors).
  work="$(mktemp -d)"
  git clone -q "$REPO" "$work"
  git -C "$work" -c user.email=git@demo -c user.name=git commit -q --allow-empty -m "seed"
  git -C "$work" push -q origin HEAD:refs/heads/main
  git -C "$REPO" symbolic-ref HEAD refs/heads/main
  rm -rf "$work"
fi

# git-http-backend runs as the `apache` uid (Apache's User directive drops privileges). It must
# OWN the repo for two reasons: git refuses a differently-owned repo ("dubious ownership", which
# cgid then unhelpfully reports as "script not found"), and anonymous PUSH (receive-pack) needs
# write. safe.directory=* is a belt-and-suspenders for any bind-mounted repo it can't chown.
chown -R apache:apache "$GIT_ROOT"
git config --system --add safe.directory '*'

exec httpd -D FOREGROUND -f /etc/apache2/conf.d/git.conf

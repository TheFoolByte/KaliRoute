#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR=${KR_ROOT:-/root}
STAGE=${KR_STAGE:-/root/src-apps}
TOKEN=${GITHUB_TOKEN:-}
REPO=${APPS_REPO:-}
[[ -n "$TOKEN" ]] || { echo 'app-sync: set GITHUB_TOKEN' >&2; exit 1; }
[[ -n "$REPO" ]] || { echo 'app-sync: set APPS_REPO=owner/repo' >&2; exit 1; }
REPO=${REPO#https://github.com/}; REPO=${REPO%.git}
[[ "$REPO" == */* ]] || { echo 'app-sync: APPS_REPO must be owner/repo' >&2; exit 1; }
clean_remote=${KR_CLEAN_REMOTE_URL:-"https://github.com/${REPO}.git"}
remote=${KR_REMOTE_URL:-"$clean_remote"}
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper
export GIT_CONFIG_VALUE_0='!f() { echo username=x-access-token; echo password=$GITHUB_TOKEN; }; f'
mkdir -p "$STAGE"
if [[ ! -d "$STAGE/.git" ]]; then
  git -C "$STAGE" init -q -b main
  git -C "$STAGE" remote add origin "$clean_remote"
else
  git -C "$STAGE" remote set-url origin "$clean_remote"
fi

write_ignore() {
  cat > "$STAGE/.gitignore" <<'EOF'
**/.git/
.sync.lock
.env
*.env
*.env.*
api-key-secret
logs/
*.pem
*.key
EOF
}

snapshot() {
  mkdir -p "$STAGE/9router"
  if [[ -d "$ROOT_DIR/.9router" ]]; then
    rsync -a --delete \
      --exclude='logs/' --exclude='*.env' --exclude='.env' --exclude='api-key-secret' \
      --exclude='db/data.sqlite-wal' --exclude='db/data.sqlite-shm' \
      "$ROOT_DIR/.9router/" "$STAGE/9router/"
  fi
  if [[ -f "$ROOT_DIR/.9router/db/data.sqlite" ]] && command -v sqlite3 >/dev/null 2>&1; then
    mkdir -p "$STAGE/9router/db"
    sqlite3 "$ROOT_DIR/.9router/db/data.sqlite" ".backup '$STAGE/9router/db/data.sqlite'"
  fi
  write_ignore
}

remote_has_main() {
  local refs rc
  if refs=$(git -C "$STAGE" ls-remote --exit-code --heads "$remote" main 2>&1); then
    return 0
  else
    rc=$?
    [[ $rc -eq 2 ]] && return 1
    printf 'app-sync: cannot inspect remote: %s\n' "$refs" >&2
    return "$rc"
  fi
}

locked() ( local lock_fd; exec {lock_fd}>"$STAGE/.sync.lock"; flock "$lock_fd"; "$@"; )

restore() {
  if remote_has_main; then
    git -C "$STAGE" fetch "$remote" main
    git -C "$STAGE" checkout -q -B main FETCH_HEAD
  else
    echo 'app-sync: remote has no main branch yet — nothing to restore'
    return 0
  fi
  if [[ -d "$STAGE/9router" ]]; then
    mkdir -p "$ROOT_DIR/.9router"
    rsync -a "$STAGE/9router/" "$ROOT_DIR/.9router/"
  fi
}

push() {
  write_ignore
  snapshot
  git -C "$STAGE" config user.name "${GITHUB_SYNC_NAME:-KaliRoute Sync}"
  git -C "$STAGE" config user.email "${GITHUB_SYNC_EMAIL:-kaliroute-sync@local}"
  git -C "$STAGE" add -A
  if git -C "$STAGE" diff --cached --quiet; then
    echo 'app-sync: nothing changed'
    return 0
  fi
  git -C "$STAGE" commit -qm "app backup $(date -u +%FT%TZ)"
  if remote_has_main; then
    git -C "$STAGE" pull --rebase --autostash "$remote" main
  fi
  git -C "$STAGE" push -u "$remote" HEAD:main
}

case "${1:-backup}" in
  backup|push) locked push;;
  restore) locked restore;;
  watch) while true; do locked push || echo 'app-sync: backup failed' >&2; sleep "${SYNC_INTERVAL:-300}"; done;;
  status) echo "Repo: $REPO"; echo "Stage: $STAGE"; git -C "$STAGE" log -1 --oneline 2>/dev/null || true;;
  *) echo 'usage: app-sync [backup|restore|watch|status]' >&2; exit 2;;
esac

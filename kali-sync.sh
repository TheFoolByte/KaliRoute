#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR=${KR_ROOT:-/root}
STAGE=${KR_STAGE:-/root/src-kali}
CONFIG=${CONFIG_FILE:-/etc/kaliroute/config.json}
TOKEN_FILE=${KR_TOKEN_FILE:-/var/lib/kaliroute/github-token}
cfg() { jq -r "$1 // empty" "$CONFIG" 2>/dev/null || true; }
# Fall back to the token the entrypoint already saved, and to /etc/kaliroute/config.json,
# so manual `kali-sync ...` runs work from an SSH shell (which does not inherit the
# entrypoint's environment).
TOKEN=${GITHUB_TOKEN:-$(cat "$TOKEN_FILE" 2>/dev/null || true)}
REPO=${KALI_REPO:-$(cfg .kali_repo)}
REPO=${REPO#https://github.com/}; REPO=${REPO%.git}
clean_remote=${KR_CLEAN_REMOTE_URL:-"https://github.com/${REPO}.git"}
remote=${KR_REMOTE_URL:-"$clean_remote"}

need_creds() {
  [[ -n "$TOKEN" ]] || { echo "kali-sync: set GITHUB_TOKEN (or write it to $TOKEN_FILE)" >&2; exit 1; }
  [[ -n "$REPO" ]] || { echo 'kali-sync: set KALI_REPO=owner/repo (or set .kali_repo in the config)' >&2; exit 1; }
  [[ "$REPO" == */* ]] || { echo 'kali-sync: KALI_REPO must be owner/repo' >&2; exit 1; }
}
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
*.pem
*.key
EOF
}

snapshot() {
  mkdir -p "$STAGE/root"
  for d in tools wordlists labs; do
    mkdir -p "$ROOT_DIR/$d"
    rsync -a --delete \
      --exclude='*.env' --exclude='.env' --exclude='*.key' --exclude='*.pem' \
      "$ROOT_DIR/$d/" "$STAGE/root/$d/"
  done
  for f in .zshrc .bashrc .vimrc .tmux.conf; do
    if [[ -f "$ROOT_DIR/$f" ]]; then
      cp -f "$ROOT_DIR/$f" "$STAGE/root/$f"
    else
      rm -f "$STAGE/root/$f"
    fi
  done
  write_ignore
}

remote_has_main() {
  local refs rc
  if refs=$(git -C "$STAGE" ls-remote --exit-code --heads "$remote" main 2>&1); then
    return 0
  else
    rc=$?
    [[ $rc -eq 2 ]] && return 1
    printf 'kali-sync: cannot inspect remote: %s\n' "$refs" >&2
    return "$rc"
  fi
}

locked() ( local lock_fd; exec {lock_fd}>"$STAGE/.sync.lock"; flock "$lock_fd"; "$@"; )

restore() {
  if remote_has_main; then
    git -C "$STAGE" fetch "$remote" main
    git -C "$STAGE" checkout -q -B main FETCH_HEAD
  else
    echo 'kali-sync: remote has no main branch yet — nothing to restore'
    return 0
  fi
  for d in tools wordlists labs; do
    if [[ -d "$STAGE/root/$d" ]]; then
      mkdir -p "$ROOT_DIR/$d"
      rsync -a "$STAGE/root/$d/" "$ROOT_DIR/$d/"
    fi
  done
  for f in .zshrc .bashrc .vimrc .tmux.conf; do
    if [[ -f "$STAGE/root/$f" ]]; then
      cp -f "$STAGE/root/$f" "$ROOT_DIR/$f"
    fi
  done
}

push() {
  snapshot
  git -C "$STAGE" config user.name "${GITHUB_SYNC_NAME:-KaliRoute Sync}"
  git -C "$STAGE" config user.email "${GITHUB_SYNC_EMAIL:-kaliroute-sync@local}"
  git -C "$STAGE" add -A
  if git -C "$STAGE" diff --cached --quiet; then
    echo 'kali-sync: nothing changed'
    return 0
  fi
  git -C "$STAGE" commit -qm "Kali workspace backup $(date -u +%FT%TZ)"
  if remote_has_main; then
    git -C "$STAGE" pull --rebase --autostash "$remote" main
  fi
  git -C "$STAGE" push -u "$remote" HEAD:main
}

case "${1:-backup}" in
  backup|push) need_creds; locked push;;
  restore) need_creds; locked restore;;
  watch) need_creds; while true; do locked push || echo 'kali-sync: backup failed' >&2; sleep "${SYNC_INTERVAL:-300}"; done;;
  status)
    echo "Repo: ${REPO:-<not set>}"
    echo "Stage: $STAGE"
    echo "Token: $([[ -n "$TOKEN" ]] && echo available || echo 'MISSING')"
    git -C "$STAGE" log -1 --oneline 2>/dev/null || true;;
  *) echo 'usage: kali-sync [backup|restore|watch|status]' >&2; exit 2;;
esac

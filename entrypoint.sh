#!/usr/bin/env bash
set -Eeuo pipefail
CONFIG=${CONFIG_FILE:-/etc/kaliforge/config.json}
get() { jq -r "$1 | if . == null then empty else tostring end" "$CONFIG" 2>/dev/null || true; }
pick() { local v=${!1:-}; if [[ -n "$v" ]]; then printf '%s' "$v"; else get "$2"; fi; }
ROOT_PASSWORD=$(pick ROOT_PASSWORD .root_password)
[[ -n "$ROOT_PASSWORD" ]] || { echo 'ROOT_PASSWORD is required; refusing to start public services without terminal authentication.' >&2; exit 1; }
TOKEN=$(pick GITHUB_TOKEN .github_token)
APPS_REPO=$(pick APPS_REPO .apps_repo)
KALI_REPO=$(pick KALI_REPO .kali_repo)
INTERVAL=$(pick SYNC_INTERVAL .sync_interval); INTERVAL=${INTERVAL:-300}
export GITHUB_TOKEN="$TOKEN" APPS_REPO KALI_REPO SYNC_INTERVAL="$INTERVAL"

if [[ -n "$ROOT_PASSWORD" ]]; then echo "root:$ROOT_PASSWORD" | chpasswd; fi
if [[ -n "${AUTHORIZED_KEYS:-}" ]]; then
  install -d -m 0700 /root/.ssh
  printf '%s\n' "$AUTHORIZED_KEYS" > /root/.ssh/authorized_keys
  chmod 0600 /root/.ssh/authorized_keys
fi
ssh-keygen -A
/usr/sbin/sshd

mkdir -p /root/src-apps /root/src-kali /root/tools /root/wordlists /root/labs /var/lib/kaliforge
if [[ -n "$TOKEN" ]]; then
  printf '%s' "$TOKEN" > /var/lib/kaliforge/github-token; chmod 0600 /var/lib/kaliforge/github-token
  if [[ -n "$APPS_REPO" ]]; then APPS_REPO="$APPS_REPO" /usr/local/bin/app-sync restore || echo 'app-sync restore failed; inspect logs and repo' >&2; fi
  if [[ -n "$KALI_REPO" ]]; then KALI_REPO="$KALI_REPO" /usr/local/bin/kali-sync restore || echo 'kali-sync restore failed; inspect logs and repo' >&2; fi
fi

if [[ "$(get '.ninerouter.enabled')" != false ]]; then
  ROUTER_DATA=$(get '.ninerouter.data_dir'); mkdir -p "$ROUTER_DATA"
  if [[ ! -s "$ROUTER_DATA/api-key-secret" ]]; then openssl rand -hex 32 > "$ROUTER_DATA/api-key-secret"; chmod 0600 "$ROUTER_DATA/api-key-secret"; fi
  env -u PORT DATA_DIR="$ROUTER_DATA" PORT="$(get '.ninerouter.port')" API_KEY_SECRET="$(<"$ROUTER_DATA/api-key-secret")" INITIAL_PASSWORD="$ROOT_PASSWORD" HOSTNAME=0.0.0.0 NODE_ENV=production nohup 9router --no-browser --skip-update >/var/log/9router.log 2>&1 &
fi
if [[ -n "$TOKEN" ]]; then
  [[ -n "$APPS_REPO" ]] && nohup /usr/local/bin/app-sync watch >/var/log/app-sync.log 2>&1 &
  [[ -n "$KALI_REPO" ]] && nohup /usr/local/bin/kali-sync watch >/var/log/kali-sync.log 2>&1 &
fi

: "${TTYD_PORT:=7681}"
: "${USERNAME:=root}"
if [[ -n "$ROOT_PASSWORD" ]]; then exec /usr/local/bin/ttyd -p "$TTYD_PORT" -c "$USERNAME:$ROOT_PASSWORD" /bin/bash -l 2> >(sed -E 's/(credential:).*/\1 [REDACTED]/' >&2); fi
echo 'Set ROOT_PASSWORD Railway variable before starting ttyd.' >&2
exec /usr/local/bin/ttyd -p "$TTYD_PORT" /bin/bash -l 2> >(sed -E 's/(credential:).*/\1 [REDACTED]/' >&2)

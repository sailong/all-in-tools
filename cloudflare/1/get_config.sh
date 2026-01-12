#!/usr/bin/env bash
set -euo pipefail

if ! command -v curl >/dev/null 2>&1; then
  echo "curl not found; please install curl"
  exit 1
fi

# 自动加载同目录下的 vars.sh（如果存在）以注入默认变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/vars.sh" ]; then
  # shellcheck disable=SC1090
  source "$SCRIPT_DIR/vars.sh"
fi

: "${ACCOUNT_ID:?Need ACCOUNT_ID}"
: "${TUNNEL_ID:?Need TUNNEL_ID}"
: "${ACCOUNT_EMAIL:?Need ACCOUNT_EMAIL}"
: "${ACCOUNT_KEY:?Need ACCOUNT_KEY}"

URL="https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations"

http_status=$(curl -sS -o get.log -w "%{http_code}" \
  -H "X-Auth-Email: ${ACCOUNT_EMAIL}" \
  -H "X-Auth-Key: ${ACCOUNT_KEY}" \
  -H "Content-Type: application/json" \
  "${URL}")

if [ "$http_status" -ge 200 ] && [ "$http_status" -lt 300 ]; then
  echo "GET succeeded, response saved to get.log"
  exit 0
else
  echo "GET failed, HTTP status: $http_status"
  cat get.log
  exit 2
fi

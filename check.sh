#!/usr/bin/env bash
set -Eeuo pipefail
NAME="${ATRUST_CONTAINER:-atrust}"
docker ps --filter "name=^/${NAME}$"
docker exec "$NAME" sh -c 'ps -ef | grep -E "[a]TrustAgent|[a]TrustTray" || true'
docker exec "$NAME" sh -c 'ip -br addr; ip rule; ip route show table 2'
for p in 5901 1080 8888 54631; do
  timeout 2 bash -c "</dev/tcp/127.0.0.1/$p" 2>/dev/null &&
    echo "port $p: reachable" || echo "port $p: not reachable"
done
if [[ -n "${1:-}" ]]; then
  curl --fail --include --max-time 20 --socks5-hostname 127.0.0.1:1080 "$1"
else
  echo "Pass an authorized intranet HTTPS URL to test the VPN data path."
fi

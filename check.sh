#!/usr/bin/env bash
# Read-only diagnostics. Optional URL tests the native VPN path inside container.
set -Eeuo pipefail
NAME="${ATRUST_CONTAINER:-atrust}"
docker ps --filter "name=^/${NAME}$"
# Enforce the single-directory mount contract at runtime.
mount_count="$(docker inspect --format '{{len .Mounts}}' "$NAME")"
mount_type_target="$(docker inspect --format '{{range .Mounts}}{{.Type}}:{{.Destination}}{{end}}' "$NAME")"
if [[ "$mount_count" != 1 || "$mount_type_target" != 'bind:/opt/atrust' ]]; then
  echo "Expected exactly one bind mount at /opt/atrust; found: $mount_count ($mount_type_target)" >&2
  exit 1
fi
echo "Single bind mount: /opt/atrust OK"
# Do not print environment values, since old container configurations may contain secrets.
if docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$NAME" | grep -Eq '^(PASSWORD|VNC_PASSWORD)='; then
  echo "Unsafe plaintext VNC password in Docker container environment; recreate with runtime/vnc-password" >&2
  exit 1
fi
echo "No plaintext VNC password in container environment"
docker exec "$NAME" sh -c '
  echo "=== Installed aTrust ==="
  test -x /usr/share/sangfor/aTrust/aTrustTray && echo "aTrustTray installed" || echo "aTrustTray not installed"
  echo "=== Processes ==="
  ps -ef | grep -E "[a]TrustAgent|[a]TrustTray|[X]tigervnc" || true
  echo "=== Interfaces ==="
  ip -br addr
  echo "=== Routing ==="
  ip route
  ip rule
  echo "=== Listening ports ==="
  ss -lnt | grep -E ":(5901|54631|8080)[[:space:]]" || true
'
for p in 5901 54631; do
  if timeout 2 bash -c "</dev/tcp/127.0.0.1/$p" 2>/dev/null; then
    echo "host port $p: reachable"
  else
    echo "host port $p: unavailable"
  fi
done
if [[ -n "${1:-}" ]]; then
  echo "Testing direct network access from aTrust container (no proxy): $1"
  docker exec "$NAME" curl -Iv --connect-timeout 10 --max-time 20 "$1"
fi

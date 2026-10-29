#!/usr/bin/env bash
# Set a runtime-only VNC password under the sole host bind mount.
# No Docker build args, Compose variables or command-line password arguments.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "$0")" && pwd)"
RUNTIME="$ROOT/runtime"
mkdir -p "$RUNTIME"
umask 077
if [[ ! -t 0 ]]; then
    echo 'Run this script in an interactive terminal to set the VNC password.' >&2
    exit 1
fi
vnc_password=''
confirm=''
IFS= read -r -s -p 'Enter VNC password (only the first 8 characters count): ' vnc_password
printf '\n'
[[ -n "$vnc_password" ]] || { echo 'VNC password cannot be empty.' >&2; exit 1; }
IFS= read -r -s -p 'Confirm VNC password: ' confirm
printf '\n'
[[ "$vnc_password" == "$confirm" ]] || { echo 'Passwords do not match.' >&2; exit 1; }
unset confirm
tmp="$(mktemp "$RUNTIME/.vnc-password.XXXXXXXX")"
trap 'rm -f -- "$tmp"' EXIT
printf '%s\n' "$vnc_password" > "$tmp"
unset vnc_password
chmod 600 "$tmp"
mv -f -- "$tmp" "$RUNTIME/vnc-password"
trap - EXIT
echo 'VNC password configured in runtime/vnc-password (mode 0600).'
echo 'Recreate the container to apply: docker compose up -d --force-recreate'

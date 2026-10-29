#!/usr/bin/env bash
# Host-mounted container entrypoint: aTrust only (no SOCKS/HTTP proxy).
set -Eeuo pipefail
export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

log() { printf '[atrust] %s\n' "$*"; }
die() { printf '[atrust] ERROR: %s\n' "$*" >&2; exit 1; }

# Installation is part of starting a new container, never Docker image build.
bash /opt/atrust/scripts/install-atrust.sh "${ATRUST_DEB:-/opt/atrust/aTrustInstaller_amd64.deb}"

[[ -c /dev/net/tun ]] || die '/dev/net/tun is missing; check Docker device mapping'
[[ -n "${PASSWORD:-}" ]] || die 'VNC_PASSWORD must be configured in .env'
eval "$(vpn-config.sh)"
[[ "${_VPN_TYPE:-}" == ATRUST ]] || die 'aTrust installation has not initialized /etc/vpn-type'

# Keep aTrust vendor iptables compatibility hooks; this is NOT a proxy service.
eval "$(detect-iptables.sh)"
# Preserve pre-VPN return routes for VNC and authentication callbacks.
eval "$(detect-route.sh)"

# The upstream Dante service used to precreate utun7. Without Dante, the VPN
# needs that virtual interface created explicitly.
if ! ip link show "$VPN_TUN" >/dev/null 2>&1; then
    ip tuntap add dev "$VPN_TUN" mode tun || die "Cannot create $VPN_TUN"
    ip addr add 10.0.0.1/32 dev "$VPN_TUN" || true
fi

# /tmp is 1777, but Sangfor core runs as UID 1234 and must be able to update
# this particular file. Do not globally relax filesystem permissions.
if [[ -e /tmp/aTrustShell.conf && ! -L /tmp/aTrustShell.conf ]]; then
    chown sangfor:sangfor /tmp/aTrustShell.conf || true
elif [[ ! -e /tmp/aTrustShell.conf && ! -L /tmp/aTrustShell.conf ]]; then
    install -o sangfor -g sangfor -m 0600 /dev/null /tmp/aTrustShell.conf
fi

open_port 5901
open_port 54631
open_port 20000
if [[ -n "${USE_NOVNC:-}" ]]; then
    open_port 8080
fi

# The vendor auth callback binds 127.0.0.1:54631 inside the container.
# Docker publishing needs this separate TCP relay, not a general-purpose proxy.
iptables -t nat -A PREROUTING -p tcp --dport 54631 \
    -m addrtype --dst-type LOCAL -j REDIRECT --to-ports 20000
socat TCP-LISTEN:20000,bind=0.0.0.0,reuseaddr,fork TCP:127.0.0.1:54631 &
auth_relay_pid=$!

mkdir -p /root/.vnc
printf '%s' "$PASSWORD" | tigervncpasswd -f > /root/.vnc/passwd
chmod 0600 /root/.vnc/passwd
export DISPLAY=:1
tigervncserver :1 -geometry "${VNC_SIZE:-1110x620}" -localhost no \
    -passwd /root/.vnc/passwd -xstartup flwm
stalonetray -f 0 >/dev/null 2>&1 &
tray_pid=$!

if [[ -n "${CLIP_TEXT:-}" ]]; then
    printf '%s' "$CLIP_TEXT" | xclip -display :1 -selection c || true
fi
if [[ -n "${USE_NOVNC:-}" ]]; then
    novnc &
    novnc_pid=$!
fi
if [[ "${CHROMIUM:-0}" == 1 ]]; then
    command -v chromium >/dev/null || die 'Chromium not installed: rebuild with BUILD_CHROMIUM=1'
    chromium --no-sandbox --display=:1 >/dev/null 2>&1 &
    chromium_pid=$!
fi

cleanup() {
    local p
    for p in "${vpn_pid:-}" "${auth_relay_pid:-}" "${tray_pid:-}" "${novnc_pid:-}" "${chromium_pid:-}"; do
        [[ -z "$p" ]] || kill "$p" 2>/dev/null || true
    done
}
trap cleanup EXIT
trap 'exit 0' SIGINT SIGTERM

log 'Installed client ready; VNC on :5901, auth callback :54631 (no proxy listeners)'
start-sangfor.sh &
vpn_pid=$!
wait "$vpn_pid"

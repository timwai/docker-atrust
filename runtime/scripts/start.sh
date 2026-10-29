#!/usr/bin/env bash
# Host-mounted container entrypoint: aTrust only (no SOCKS/HTTP proxy).
set -Eeuo pipefail
export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

log() { printf '[atrust] %s\n' "$*"; }
die() { printf '[atrust] ERROR: %s\n' "$*" >&2; exit 1; }

# The image links /root to the sole bind mount: /opt/atrust/data/root.
# Sangfor looks up root's home directory via passwd, so HOME alone is insufficient.
[[ -L /root && "$(readlink /root)" == "/opt/atrust/data/root" ]] ||
    die 'Image /root persistence symlink missing; rebuild the runtime image'
[[ -f /opt/atrust/scripts/install-atrust.sh ]] ||
    die 'Missing runtime/scripts/install-atrust.sh in the single mounted directory'
mkdir -p /opt/atrust/data/root
chmod 700 /opt/atrust/data/root
if [[ -d /root.image ]]; then
    cp -an /root.image/. /opt/atrust/data/root/
fi
export HOME=/root
cd /root

# Installation is part of starting a new container, never Docker image build.
bash /opt/atrust/scripts/install-atrust.sh "${ATRUST_DEB:-/opt/atrust/aTrustInstaller_amd64.deb}"

[[ -c /dev/net/tun ]] || die '/dev/net/tun is missing; check Docker device mapping'
# Read the secret only at container startup; it must not appear in Compose
# environment variables, Docker image layers or docker inspect output.
vnc_password_file="${VNC_PASSWORD_FILE:-/opt/atrust/vnc-password}"
[[ -f "$vnc_password_file" && ! -L "$vnc_password_file" ]] ||
    die 'Missing VNC password file: create runtime/vnc-password with ./set-vnc-password.sh on the host'
vnc_secret=''
IFS= read -r vnc_secret < "$vnc_password_file" || [[ -n "$vnc_secret" ]] ||
    die 'VNC password file is empty'
[[ -n "$vnc_secret" ]] || die 'VNC password file is empty'
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
printf '%s' "$vnc_secret" | tigervncpasswd -f > /root/.vnc/passwd
unset vnc_secret
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
    # Ubuntu's chromium-browser is Snap-only; BUILD_CHROMIUM=1 installs the
    # official Chrome DEB instead. Allow Chromium in custom images.
    if command -v google-chrome-stable >/dev/null 2>&1; then
        browser=google-chrome-stable
    elif command -v chromium >/dev/null 2>&1; then
        browser=chromium
    else
        die 'Browser missing: rebuild with BUILD_CHROMIUM=1'
    fi
    "$browser" --no-sandbox --disable-dev-shm-usage --disable-gpu \
        --no-first-run --no-default-browser-check >/dev/null 2>&1 &
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

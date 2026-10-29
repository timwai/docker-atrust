#!/usr/bin/env bash
# Called by the bind-mounted startup script each time the container is started.
# On the same container, identical DEB is installed once. Recreating a container
# reinstalls it because the image does not contain the proprietary client.
set -Eeuo pipefail
deb="${1:-/opt/atrust/aTrustInstaller_amd64.deb}"
[[ -f "$deb" && -s "$deb" ]] || {
    echo "[atrust] Missing aTrust DEB at $deb; put runtime/aTrustInstaller_amd64.deb in the single bind-mounted directory" >&2
    exit 1
}
pkg="$(dpkg-deb -f "$deb" Package)"
arch="$(dpkg-deb -f "$deb" Architecture)"
ver="$(dpkg-deb -f "$deb" Version)"
[[ "$arch" == amd64 && "$pkg" == *[Aa][Tt]rust* ]] || {
    echo "[atrust] Not an AMD64 aTrust package: $pkg / $arch" >&2
    exit 1
}
hash="$(sha256sum "$deb" | awk '{print $1}')"
marker=/usr/share/sangfor/.aTrust/.docker-install-sha256
if [[ -f "$marker" && -x /usr/share/sangfor/aTrust/aTrustTray ]]; then
    old="$(cat "$marker")"
    if [[ "$old" == "$hash" ]]; then
        echo "[atrust] Already installed: $pkg $ver; skipping"
        exit 0
    fi
    echo "[atrust] Package changed. Recreate container: docker compose up -d --force-recreate" >&2
    exit 1
fi

echo "[atrust] Installing $pkg $ver at container startup (SHA256 $hash)"
# The original vendored installer requires /tmp/VPN.deb and invokes Sangfor's
# preinst/postinst scripts, matching upstream's installation behavior.
install -m 0644 "$deb" /tmp/VPN.deb
bash /tmp/build-scripts/install-vpn-gui.sh
[[ -x /usr/share/sangfor/aTrust/aTrustTray ]] || {
    echo "[atrust] Installation completed without aTrustTray" >&2
    exit 1
}
mkdir -p "$(dirname "$marker")"
printf '%s\n' "$hash" > "$marker"
echo "[atrust] Installed successfully"

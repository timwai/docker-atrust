#!/usr/bin/env bash
# Adapted from docker-easyconnect's aTrust-only DEB installer.
# Executed by scripts/install-atrust.sh at CONTAINER START, not at image build.
set -Eeuo pipefail
[[ "${VPN_TYPE:-}" == ATRUST ]] || { echo "Only VPN_TYPE=ATRUST is supported" >&2; exit 1; }
[[ -s /tmp/VPN.deb ]] || { echo "Missing staged aTrust /tmp/VPN.deb" >&2; exit 1; }
if [[ ! -e /usr/sbin/sysctl.real ]]; then
    mv /usr/sbin/sysctl /usr/sbin/sysctl.real
    ln -s /usr/sbin/sysctl-hook /usr/sbin/sysctl
fi
printf '%s\n' ATRUST > /etc/vpn-type
cd /tmp
dpkg-deb -R VPN.deb /
pkg="$(sed -n 's/^Package:[[:space:]]*//p' /DEBIAN/control | head -n 1)"
[[ -n "$pkg" ]] || { echo "Invalid aTrust control: no Package" >&2; exit 1; }
if [[ -f /DEBIAN/preinst ]]; then
    /DEBIAN/preinst || true
fi
mkdir -p /var/lib/dpkg/info
for file in /DEBIAN/*; do
    [[ -f "$file" ]] || continue
    cp "$file" "/var/lib/dpkg/info/$pkg.$(basename "$file")"
    # aTrust's proprietary postinst expects unprefixed maintenance scripts.
    cp "$file" "/var/lib/dpkg/info/$(basename "$file")"
done
[[ -f "/var/lib/dpkg/info/$pkg.postinst" ]] || {
    echo "Package has no postinst; validate installer format" >&2
    exit 1
}
"/var/lib/dpkg/info/$pkg.postinst"
for file in /DEBIAN/*; do
    [[ -f "$file" ]] || continue
    rm -f "/var/lib/dpkg/info/$(basename "$file")"
done
rm -rf /DEBIAN
rm -f /tmp/VPN.deb
[[ ! -d /home/sangfor ]] || chown -R sangfor:sangfor /home/sangfor

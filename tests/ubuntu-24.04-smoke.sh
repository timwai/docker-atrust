#!/usr/bin/env bash
# Lightweight runtime image checks. Does NOT install proprietary aTrust.
set -Eeuo pipefail
IMAGE="${1:-local/atrust:latest}"
docker image inspect "$IMAGE" >/dev/null
docker run --rm --pull=never --network=none --entrypoint=/bin/bash "$IMAGE" -ec '
    . /etc/os-release
    test "$ID" = ubuntu
    test "$VERSION_ID" = 24.04
    test "$(readlink /root)" = /opt/atrust/data/root
    test ! -e /usr/share/sangfor/aTrust
    command -v tigervncserver
    command -v tigervncpasswd
    command -v websockify
    command -v socat
    command -v ip
    command -v iptables
    command -v dpkg-deb
    command -v flwm
    command -v stalonetray
    ! dpkg-query -W -f="${Status}" libssl1.1 2>/dev/null | grep -q "install ok installed"
    ! dpkg-query -W -f="${Status}" libldap-2.4-2 2>/dev/null | grep -q "install ok installed"
    ! dpkg-query -W -f="${Status}" libqt5core5t64 2>/dev/null | grep -q "install ok installed"
    echo "Ubuntu 24.04 runtime smoke checks passed (without installing aTrust)"
'
docker image inspect "$IMAGE" --format 'Image bytes={{.Size}}'

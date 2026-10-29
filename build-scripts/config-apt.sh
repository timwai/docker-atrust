#!/bin/sh
# Debian 12 runtime with pinned Debian 11 compatibility libraries.
# Snapshot disables Release expiry only, never GPG signature verification.
set -eu
. /etc/os-release
cat >/etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian ${VERSION_CODENAME} main
deb http://deb.debian.org/debian-security ${VERSION_CODENAME}-security main
deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/20260903T220410Z bullseye main
deb [check-valid-until=no] http://snapshot.debian.org/archive/debian-security/20260903T220410Z bullseye-security main
EOF
cat >/etc/apt/preferences.d/bullseye <<EOF
Package: *
Pin: release n=bullseye
Pin-Priority: 100

Package: *
Pin: release n=bullseye-security
Pin-Priority: 100
EOF
rm -f /etc/apt/sources.list.d/debian.sources

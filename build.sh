#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "$0")" && pwd)"
cd "$ROOT"
IMAGE_REPO="${IMAGE_REPO:-local/atrust}"
ATRUST_VERSION="${ATRUST_VERSION:-2.5.16.30}"
CHROMIUM=0
SOURCE=""
SOURCE_VALUE=""
VENDOR="$ROOT/vendor/aTrustInstaller_amd64.deb"
REMOVE_VENDOR=0
cleanup() {
  if [[ "$REMOVE_VENDOR" = 1 ]]; then
    rm -f -- "$VENDOR"
  fi
}
trap cleanup EXIT

usage() {
  cat <<'HELP'
Usage:
  ./build.sh --deb /path/to/aTrustInstaller_amd64.deb [--chromium]
  ./build.sh --official [--chromium]
  ./build.sh --local [--chromium]
No git clone or downloads of other GitHub repositories.
--official downloads the Sangfor public DEB; --deb accepts your authorized local package.
System packages and base image still come from Debian/Docker registries.
HELP
}
while (( $# )); do
  case "$1" in
    --deb)
      [[ $# -gt 1 && -z "$SOURCE" ]] || { usage; exit 2; }
      SOURCE=deb; SOURCE_VALUE="$2"; shift 2 ;;
    --official)
      [[ -z "$SOURCE" ]] || { usage; exit 2; }
      SOURCE=official; shift ;;
    --local)
      [[ -z "$SOURCE" ]] || { usage; exit 2; }
      SOURCE=local; shift ;;
    --chromium) CHROMIUM=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Invalid argument: $1" >&2; usage; exit 2 ;;
  esac
done
[[ -n "$SOURCE" ]] || { usage; exit 2; }
for cmd in docker dpkg-deb sha256sum; do
  command -v "$cmd" >/dev/null || { echo "Missing: $cmd" >&2; exit 1; }
done
[[ "$(uname -m)" == x86_64 ]] || { echo "Only linux/amd64 is supported." >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker daemon unavailable." >&2; exit 1; }
mkdir -p "$ROOT/vendor"
if [[ "$SOURCE" == deb ]]; then
  [[ -f "$SOURCE_VALUE" ]] || { echo "DEB not found: $SOURCE_VALUE" >&2; exit 1; }
  source_abs="$(realpath "$SOURCE_VALUE")"
  if [[ "$source_abs" != "$VENDOR" ]]; then
    cp -- "$SOURCE_VALUE" "$VENDOR"
    REMOVE_VENDOR=1
  fi
elif [[ "$SOURCE" == official ]]; then
  command -v curl >/dev/null || { echo "Missing: curl" >&2; exit 1; }
  url="https://atrustcdn.sangfor.com/standard/linux/$ATRUST_VERSION/uos/amd64/aTrustInstaller_amd64.deb"
  echo "Fetching official aTrust DEB from $url"
  curl -fL --retry 2 --connect-timeout 15 "$url" -o "$VENDOR"
  REMOVE_VENDOR=1
fi
[[ -s "$VENDOR" ]] || { echo "Missing local aTrust DEB: $VENDOR" >&2; exit 1; }
pkg="$(dpkg-deb -f "$VENDOR" Package)"
ver="$(dpkg-deb -f "$VENDOR" Version)"
arch="$(dpkg-deb -f "$VENDOR" Architecture)"
[[ "$arch" == amd64 && "$pkg" == *[Aa][Tt]rust* ]] || {
  echo "Unexpected package: $pkg / $arch" >&2; exit 1;
}
tag="$(printf '%s' "$ver" | sed -E 's/[^a-zA-Z0-9_.-]+/-/g')"
hash="$(sha256sum "$VENDOR" | awk '{print $1}')"
echo "Building: $pkg $ver ($arch)"
echo "Installer SHA256: $hash"
docker build --progress=plain \
  --build-arg "CHROMIUM=$CHROMIUM" \
  --label "org.opencontainers.image.source=https://github.com/timwai/docker-atrust" \
  --label "org.opencontainers.image.version=$ver" \
  --label "local.atrust.package.sha256=$hash" \
  -t "$IMAGE_REPO:latest" -t "$IMAGE_REPO:$tag-amd64" \
  -f Dockerfile .
echo "Built $IMAGE_REPO:latest and $IMAGE_REPO:$tag-amd64"

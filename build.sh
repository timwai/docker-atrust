#!/usr/bin/env bash
# Build a reusable runtime image; install aTrust ONLY when a container starts.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "$0")" && pwd)"
cd "$ROOT"
IMAGE_REPO="${IMAGE_REPO:-local/atrust}"
ATRUST_VERSION="${ATRUST_VERSION:-2.5.16.30}"
CHROMIUM=0
DEB_SOURCE=""
DEB_VALUE=""

usage() {
  cat <<'USAGE'
Usage:
  ./build.sh [--chromium]                           # image only; no aTrust DEB required
  ./build.sh --deb /path/to/aTrustInstaller_amd64.deb [--chromium]
  ./build.sh --official [--chromium]                # fetch official public DEB to runtime/
  ./build.sh --local [--chromium]                   # validate runtime/ DEB then build

The DEB remains on the HOST and is mounted at container creation.
Image build never includes or installs the proprietary package, and never clones GitHub.
USAGE
}
while (( $# )); do
  case "$1" in
    --deb)
      [[ $# -gt 1 && -z "$DEB_SOURCE" ]] || { usage; exit 2; }
      DEB_SOURCE=deb; DEB_VALUE="$2"; shift 2 ;;
    --official)
      [[ -z "$DEB_SOURCE" ]] || { usage; exit 2; }
      DEB_SOURCE=official; shift ;;
    --local)
      [[ -z "$DEB_SOURCE" ]] || { usage; exit 2; }
      DEB_SOURCE=local; shift ;;
    --chromium) CHROMIUM=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Invalid argument: $1" >&2; usage; exit 2 ;;
  esac
done
command -v docker >/dev/null || { echo "Docker CLI not installed" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker daemon not available" >&2; exit 1; }
[[ "$(uname -m)" == x86_64 ]] || { echo "Only linux/amd64 supported" >&2; exit 1; }
mkdir -p runtime
DEST="$ROOT/runtime/aTrustInstaller_amd64.deb"
if [[ "$DEB_SOURCE" == deb ]]; then
  [[ -f "$DEB_VALUE" ]] || { echo "Package not found: $DEB_VALUE" >&2; exit 1; }
  source="$(realpath "$DEB_VALUE")"
  [[ "$source" == "$DEST" ]] || cp "$source" "$DEST"
elif [[ "$DEB_SOURCE" == official ]]; then
  command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }
  url="https://atrustcdn.sangfor.com/standard/linux/$ATRUST_VERSION/uos/amd64/aTrustInstaller_amd64.deb"
  curl -fL --retry 2 --connect-timeout 15 "$url" -o "$DEST"
fi
if [[ -n "$DEB_SOURCE" ]]; then
  command -v dpkg-deb >/dev/null || { echo "dpkg-deb is required to validate the package" >&2; exit 1; }
  [[ -s "$DEST" ]] || { echo "Missing: $DEST" >&2; exit 1; }
  pkg="$(dpkg-deb -f "$DEST" Package)"
  ver="$(dpkg-deb -f "$DEST" Version)"
  arch="$(dpkg-deb -f "$DEST" Architecture)"
  [[ "$arch" == amd64 && "$pkg" == *[Aa][Tt]rust* ]] || { echo "Unexpected DEB: $pkg / $arch" >&2; exit 1; }
  echo "Staged official installer $pkg $ver (SHA256 $(sha256sum "$DEST" | awk '{print $1}'))"
fi
docker build --progress=plain --build-arg "CHROMIUM=$CHROMIUM" \
    --label "org.opencontainers.image.source=https://github.com/timwai/docker-atrust" \
    -t "$IMAGE_REPO:latest" -f Dockerfile .
echo "Runtime image built: $IMAGE_REPO:latest"
echo "aTrust will be installed when docker compose creates/starts the container."

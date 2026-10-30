#!/bin/bash
#
# Build a patched kwin .deb inside a Debian container.
#
# Pipeline: fetch the Debian source package, overlay the anland backend
# sources and the backend patch, then build binary packages with the
# distribution's own version so the result reinstalls over the stock package.
#
set -euo pipefail

SUITE="${SUITE:-trixie}"
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
WORKDIR="${WORKDIR:-/work/build}"
SRC_PKG="${SRC_PKG:-kwin}"

log() { printf '\n== %s\n' "$*"; }

log "repo root: $REPO_ROOT"
log "suite: $SUITE"
log "source package: $SRC_PKG"

# deb-src is required by apt-get source.
log "enabling deb-src"
if [ -f /etc/apt/sources.list.d/debian.sources ]; then
    sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/debian.sources
else
    sed -i 's/^deb \(.*\)$/deb \1\ndeb-src \1/' /etc/apt/sources.list
fi
apt-get update

log "installing build dependencies for $SRC_PKG"
apt-get install -y --no-install-recommends \
    build-essential devscripts equivs dpkg-dev patch fakeroot
apt-get build-dep -y "$SRC_PKG"

log "fetching source"
mkdir -p "$WORKDIR"
cd "$WORKDIR"
rm -rf "$SRC_PKG"
mkdir -p "$SRC_PKG"
cd "$SRC_PKG"
apt-get source "$SRC_PKG"

TREE="$(find "$WORKDIR/$SRC_PKG" -maxdepth 1 -type d -name "${SRC_PKG}-*" | head -1)"
[ -n "$TREE" ] || { echo "no source tree unpacked"; exit 1; }
log "source tree: $TREE"

if [ -d "$REPO_ROOT/overlay" ]; then
    log "overlaying backend sources"
    cp -a "$REPO_ROOT/overlay/." "$TREE/"
fi

PATCH="$REPO_ROOT/patches/$SRC_PKG.patch"
if [ -f "$PATCH" ]; then
    log "applying $PATCH"
    ( cd "$TREE" && patch --batch -p1 --forward --reject-file=- < "$PATCH" )
else
    echo "no patch at $PATCH"
    exit 1
fi

log "building"
cd "$TREE"
DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" \
    dpkg-buildpackage -b -uc -us -d

log "artifacts"
find "$WORKDIR/$SRC_PKG" -maxdepth 1 -name '*.deb' -type f -printf '%p %s\n'

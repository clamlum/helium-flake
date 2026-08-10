#!/usr/bin/env bash

set -euo pipefail

LINUX_REPO="imputnet/helium-linux"
MACOS_REPO="imputnet/helium-macos"

RELEASE_FILE="helium-release.nix"

if [[ ! -f "$RELEASE_FILE" ]]; then
    echo "error: $RELEASE_FILE not found" >&2
    echo "Run this script from the root of the Helium flake." >&2
    exit 1
fi

command -v curl >/dev/null || {
    echo "error: curl is required" >&2
    exit 1
}

command -v sed >/dev/null || {
    echo "error: sed is required" >&2
    exit 1
}

command -v nix >/dev/null || {
    echo "error: nix is required" >&2
    exit 1
}

echo "Checking latest Helium release..."

version="$(
    curl -fsSL \
        "https://api.github.com/repos/${LINUX_REPO}/releases/latest" |
        sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' |
        head -n1
)"

if [[ -z "$version" ]]; then
    echo "error: failed to determine latest Helium version" >&2
    exit 1
fi

echo "Latest version: $version"

current_version="$(
    sed -n 's/^[[:space:]]*version = "\([^"]*\)";/\1/p' \
        "$RELEASE_FILE"
)"

if [[ "$version" == "$current_version" ]]; then
    echo "Already up to date ($version)"
    exit 0
fi

echo "Updating $current_version -> $version"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT


get_hash() {
    local url="$1"
    local output="$2"

    echo "Downloading $url" >&2

    curl -fL \
        --retry 3 \
        --retry-delay 2 \
        "$url" \
        -o "$output"

    nix hash file --type sha256 --sri "$output"
}


linux_x86_url="https://github.com/${LINUX_REPO}/releases/download/${version}/helium-${version}-x86_64_linux.tar.xz"

linux_aarch64_url="https://github.com/${LINUX_REPO}/releases/download/${version}/helium-${version}-arm64_linux.tar.xz"

darwin_aarch64_url="https://github.com/${MACOS_REPO}/releases/download/${version}/helium_${version}_arm64-macos.dmg"


echo
echo "Fetching Linux x86_64..."
linux_x86_hash="$(
    get_hash \
        "$linux_x86_url" \
        "$tmpdir/linux-x86_64.tar.xz"
)"

echo
echo "Fetching Linux aarch64..."
linux_aarch64_hash="$(
    get_hash \
        "$linux_aarch64_url" \
        "$tmpdir/linux-aarch64.tar.xz"
)"

echo
echo "Fetching macOS aarch64..."
darwin_aarch64_hash="$(
    get_hash \
        "$darwin_aarch64_url" \
        "$tmpdir/darwin-aarch64.dmg"
)"


echo
echo "New release information:"
echo "  version:          $version"
echo "  Linux x86_64:     $linux_x86_hash"
echo "  Linux aarch64:    $linux_aarch64_hash"
echo "  macOS aarch64:    $darwin_aarch64_hash"


echo
echo "Updating $RELEASE_FILE..."

sed -i \
    -e "s|^[[:space:]]*version = \".*\";|  version = \"$version\";|" \
    -e "s|^[[:space:]]*linux_x86_64_hash = \".*\";|  linux_x86_64_hash = \"$linux_x86_hash\";|" \
    -e "s|^[[:space:]]*linux_aarch64_hash = \".*\";|  linux_aarch64_hash = \"$linux_aarch64_hash\";|" \
    -e "s|^[[:space:]]*darwin_aarch64_hash = \".*\";|  darwin_aarch64_hash = \"$darwin_aarch64_hash\";|" \
    "$RELEASE_FILE"


echo
echo "Running nix flake check..."

nix flake check --all-systems


echo
echo "Checking that the package evaluates..."

system="$(nix eval --raw --impure --expr 'builtins.currentSystem')"

nix eval \
    ".#packages.${system}.default.drvPath" \
    >/dev/null


echo
echo "Successfully updated Helium to $version."

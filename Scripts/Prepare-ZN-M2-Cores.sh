#!/usr/bin/env bash
set -euo pipefail

FILES_ROOT=${1:?Usage: Prepare-ZN-M2-Cores.sh <files-root>}

MIHOMO_VERSION=v1.19.34
MIHOMO_SHA256=daaf78a6240a282cdfd75bcbf98fe321f6bd52765cc29e79f344191198f0b50f
TAILSCALE_VERSION=1.104.7
TAILSCALE_SHA256=d6bed2720310b328b861f943d7b4016c5358a9bad60575eb51e8143b79068484

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

verify_sha256() {
	local expected=$1
	local file=$2

	printf '%s  %s\n' "$expected" "$file" | sha256sum --check --status || {
		echo "SHA-256 verification failed: $file" >&2
		exit 1
	}
}

OPENCLASH_CORE="$FILES_ROOT/etc/openclash/core"
TAILSCALE_BIN="$FILES_ROOT/usr/sbin"
mkdir -p "$OPENCLASH_CORE" "$TAILSCALE_BIN"

MIHOMO_ARCHIVE="$TMP_DIR/mihomo-linux-arm64.gz"
curl --fail --location --silent --show-error --retry 3 \
	"https://github.com/MetaCubeX/mihomo/releases/download/$MIHOMO_VERSION/mihomo-linux-arm64-$MIHOMO_VERSION.gz" \
	--output "$MIHOMO_ARCHIVE"
verify_sha256 "$MIHOMO_SHA256" "$MIHOMO_ARCHIVE"
gzip -t "$MIHOMO_ARCHIVE"
gzip -dc "$MIHOMO_ARCHIVE" > "$OPENCLASH_CORE/clash_meta"
chmod 755 "$OPENCLASH_CORE/clash_meta"

TAILSCALE_ARCHIVE="$TMP_DIR/tailscale_${TAILSCALE_VERSION}_arm64.tgz"
curl --fail --location --silent --show-error --retry 3 \
	"https://pkgs.tailscale.com/stable/tailscale_${TAILSCALE_VERSION}_arm64.tgz" \
	--output "$TAILSCALE_ARCHIVE"
verify_sha256 "$TAILSCALE_SHA256" "$TAILSCALE_ARCHIVE"
TAILSCALED_MEMBER="tailscale_${TAILSCALE_VERSION}_arm64/tailscaled"
tar -tzf "$TAILSCALE_ARCHIVE" | grep -Fx "$TAILSCALED_MEMBER" >/dev/null || {
	echo "Tailscale archive is missing $TAILSCALED_MEMBER" >&2
	exit 1
}
tar -xOzf "$TAILSCALE_ARCHIVE" "$TAILSCALED_MEMBER" > "$TAILSCALE_BIN/tailscaled"
chmod 755 "$TAILSCALE_BIN/tailscaled"
ln -sfn tailscaled "$TAILSCALE_BIN/tailscale"

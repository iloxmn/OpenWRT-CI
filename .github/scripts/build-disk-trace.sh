#!/usr/bin/env bash
set -euo pipefail

MODE=${1:?Usage: build-disk-trace.sh <snapshot|monitor> <build-root> <trace-dir> [label|interval] [detail]}
BUILD_ROOT=${2:?Build root is required}
TRACE_DIR=${3:?Trace directory is required}
ARGUMENT=${4:-}

mkdir -p "$TRACE_DIR"

snapshot() {
	local label=$1
	local detail=${2:-false}
	local path

	{
		printf '\n=== disk snapshot: %s ===\n' "$label"
		printf 'timestamp=%s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
		printf 'build_root=%s\n' "$BUILD_ROOT"
		df -hT "$BUILD_ROOT"
		df -i "$BUILD_ROOT"

		if [[ "$detail" == "true" ]]; then
			printf '\n=== selected directory sizes (bytes) ===\n'
			for path in build_dir staging_dir dl tmp bin package .ccache; do
				if [[ -e "$BUILD_ROOT/$path" ]]; then
					du -s -B1 "$BUILD_ROOT/$path"
				fi
			done

			printf '\n=== largest paths through depth 2 (bytes) ===\n'
			if ! timeout 120s du -x -B1 --max-depth=2 "$BUILD_ROOT" 2>&1 |
				sort -nr | tail -n 40; then
				printf 'WARNING: detailed du scan failed or timed out\n'
			fi
		fi
	} | tee -a "$TRACE_DIR/disk-snapshots.log"
}

monitor() {
	local interval=${ARGUMENT:-60}
	local sleeper_pid=''

	trap 'if [[ -n "$sleeper_pid" ]]; then kill "$sleeper_pid" 2>/dev/null || true; fi; exit 0' TERM INT

	while true; do
		{
			printf '%s\t' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
			df -B1 --output=size,used,avail,pcent "$BUILD_ROOT" | tail -n 1
		} | tee -a "$TRACE_DIR/disk-samples.tsv"

		sleep "$interval" &
		sleeper_pid=$!
		wait "$sleeper_pid" || true
		sleeper_pid=''
	done
}

case "$MODE" in
	snapshot)
		snapshot "$ARGUMENT" "${5:-false}"
		;;
	monitor)
		monitor
		;;
	*)
		echo "Unknown mode: $MODE" >&2
		exit 2
		;;
esac

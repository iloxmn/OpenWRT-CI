#!/bin/sh
set -eu

URL="https://cf.trackerslist.com/best.txt"
MAX=200
STATE=/etc/trackers.md5

log() {
	logger -p daemon.info -t trackers "$*"
}

PORT=$(uci -q get aria2.main.rpc_listen_port || :)
PORT=${PORT:-6800}
SECRET=$(uci -q get aria2.main.rpc_secret || :)

tmp="/tmp/aria2-trackers.$$"
trap 'rm -f "$tmp"' EXIT HUP INT TERM

if ! curl -fsSL --max-time 30 -o "$tmp" "$URL"; then
	log "fetch failed ($URL), keeping old list"
	exit 1
fi

list=$(tr -d '\r' < "$tmp" \
	| grep -E '^(https?|udp|wss?)://' \
	| head -n "$MAX" \
	| tr '\n' ',' \
	| sed 's/,$//')

[ -n "$list" ] || { log "fetch returned an empty tracker list, keeping old list"; exit 1; }

n=$(printf '%s\n' "$list" | tr ',' '\n' | wc -l)
hash=$(printf '%s\n' "$list" | md5sum | cut -d' ' -f1)
if [ -f "$STATE" ] && [ "$hash" = "$(cat "$STATE")" ]; then
	exit 0
fi

if uci -q get aria2.main.bt_tracker >/dev/null 2>&1; then
	uci -q delete aria2.main.bt_tracker
fi

old_ifs=$IFS
IFS=','
set -f
for tracker in $list; do
	[ -n "$tracker" ] && uci add_list aria2.main.bt_tracker="$tracker"
done
IFS=$old_ifs
uci commit aria2

if [ -n "$SECRET" ]; then
	params="[\"token:$SECRET\",{\"bt-tracker\":\"$list\"}]"
else
	params="[{\"bt-tracker\":\"$list\"}]"
fi

if ! resp=$(curl -sS --max-time 10 -H 'Content-Type: application/json' \
	-d "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"aria2.changeGlobalOption\",\"params\":$params}" \
	"http://127.0.0.1:$PORT/jsonrpc"); then
	log "saved $n trackers, RPC update failed; will retry"
	exit 1
fi

case "$resp" in
	*'"result":"OK"'*)
		state_tmp="$STATE.tmp.$$"
		printf '%s\n' "$hash" > "$state_tmp"
		mv "$state_tmp" "$STATE"
		log "updated $n trackers"
		;;
	*)
		log "saved $n trackers, RPC update failed; will retry"
		exit 1
		;;
esac

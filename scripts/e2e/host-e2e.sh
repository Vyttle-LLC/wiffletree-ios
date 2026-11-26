#!/usr/bin/env bash
#
# End-to-end check of WiffletreeKit's connection client against a real host. Local only, not
# CI. Builds the host from a wiffletree checkout whose branch offers pairing by qr, starts it
# headless with a throwaway data folder, turns remote access on, opens pairing, then runs
# EndToEndTests: pair by the QR payload over real TLS and WebSocket, and list projects.
#
# Usage: scripts/e2e/host-e2e.sh [wiffletree checkout, default ~/dev/vyttle/wiffletree]
#
# The host listens on the fixed port 47821, so Wiffletree's own host must have remote access
# off. The host keeps its key in the login Keychain under the data folder; the cleanup removes
# that item.
set -euo pipefail

host_repo="${1:-$HOME/dev/vyttle/wiffletree}"
ios_repo="$(cd "$(dirname "$0")/../.." && pwd)"

if lsof -nP -iTCP:47821 -sTCP:LISTEN >/dev/null; then
    echo "error: port 47821 is in use, probably by Wiffletree's own host with remote access on." >&2
    exit 1
fi

cargo build -p workspace-host --manifest-path "$host_repo/Cargo.toml"
binary="$host_repo/target/debug/wiffletree-host"

# Short, because the socket path must fit in 103 bytes.
work="$(mktemp -d /tmp/wt-e2e.XXXXXX)"
data="$(cd "$work" && pwd -P)/host"
credential="$(uuidgen)"
mkfifo "$work/stdin"

# A child host reads its credential from the first line of standard input and stops when that
# input closes.
"$binary" serve --data-dir "$data" --child <"$work/stdin" >"$work/host.log" 2>&1 &
host_pid=$!
exec 3>"$work/stdin"
echo "$credential" >&3

cleanup() {
    exec 3>&-
    kill "$host_pid" 2>/dev/null || true
    wait "$host_pid" 2>/dev/null || true
    security delete-generic-password -s com.vyttle.wiffletree.host-key -a "$data" >/dev/null 2>&1 || true
    rm -rf "$work"
}
trap cleanup EXIT

for _ in $(seq 50); do
    [[ -S "$data/host.sock" ]] && break
    sleep 0.2
done
[[ -S "$data/host.sock" ]] || { cat "$work/host.log" >&2; echo "error: the host did not start" >&2; exit 1; }

project="End-to-end $(date +%H%M%S)"
qr="$(python3 -I "$ios_repo/scripts/e2e/host_socket.py" "$data" "$credential" "$project")"
echo "Pairing by QR code: $qr"

cd "$ios_repo/Packages/WiffletreeKit"
WIFFLETREE_E2E_QR="$qr" WIFFLETREE_E2E_PROJECT="$project" swift test --filter EndToEndTests

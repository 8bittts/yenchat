#!/bin/bash
# Print zmx listing rows for YEN's UUID sockets. Both the CLI and the macOS
# reaper consume this output. A zmx client probes every socket in ZMX_DIR,
# so give each build a private directory containing only its own sockets.
set -eu
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
# zmx creates the listing directory's logs/ with 0750 unless told.
export ZMX_DIR_MODE=0700
directory=$1
bundled=$2
uuid='^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$'
[[ -d "$directory" && -r "$directory" && -x "$directory" ]] || exit 1
# Socket paths must fit Darwin's 103-byte limit, even with a long home path.
views=$(mktemp -d /tmp/yen-ls.XXXXXXXX)
trap 'rm -rf "$views"' EXIT
trap 'exit 1' HUP INT TERM
directory=$(cd "$directory" && pwd)
# Status 2 means some builds could not be queried. Rows from other builds
# remain usable. A directory or setup failure exits 1.
partial=0
unreachable() {
    printf 'name=%s\terr=%s\n' "$1" "$2"
    partial=2
}
# Keep the device and inode observed before each probe. Some zmx versions
# remove a refused socket during ls; only propagate that cleanup to the
# original name if it still identifies the same socket.
mkdir "$views/.identity"
shopt -s nullglob
for socket in "$directory"/*; do
    name=${socket##*/}
    [[ "$name" =~ $uuid && -S "$socket" && ! -L "$socket" ]] || continue
    group=bundled
    if [[ -e "$socket.zmx" || -L "$socket.zmx" ]]; then
        if [[ ! -f "$socket.zmx" || -L "$socket.zmx" ]] || ! recorded=$(cat "$socket.zmx"); then
            unreachable "$name" InvalidBuildRecord
            continue
        fi
        if [[ ! "$recorded" -ef "$bundled" ]]; then
            group=${recorded##*/}
            if [[ ! "$group" =~ ^zmx-[0-9a-f]{16}$ || "$recorded" != /* || ! "${recorded%/*}" -ef "$directory/bin" ]]; then
                unreachable "$name" InvalidBuildRecord
                continue
            fi
        fi
    fi
    stat -f '%d:%i' "$socket" > "$views/.identity/$name" || {
        [[ ! -S "$socket" ]] && continue
        exit 1
    }
    mkdir -p "$views/$group"
    ln -s "$socket" "$views/$group/$name"
done
for view in "$views"/*; do
    group=${view##*/}
    binary=$bundled
    if [[ "$group" != bundled ]]; then
        binary="$directory/bin/$group"
        # Only execute digest-named copies created by PersistentSessions.
        digest=""
        if [[ -f "$binary" && -x "$binary" && ! -L "$binary" && ! -L "$directory/bin" ]]; then
            digest=$(shasum -a 256 < "$binary") || digest=""
        fi
        if [[ "$group" != "zmx-${digest:0:16}" ]]; then
            for socket in "$view"/*; do unreachable "${socket##*/}" MissingBuild; done
            continue
        fi
    fi
    sockets=("$view"/*)
    if rows=$(ZMX_DIR="$view" "$binary" ls); then
        [[ -z "$rows" ]] || printf '%s\n' "$rows"
        for alias in "${sockets[@]}"; do
            [[ -L "$alias" ]] && continue
            name=${alias##*/}
            [[ "$rows" == *"name=$name"$'\t'"err=ConnectionRefused"$'\t'* ]] || continue
            original="$directory/$name"
            [[ -S "$original" && ! -L "$original" ]] || continue
            current=$(stat -f '%d:%i' "$original") || continue
            if [[ "$current" == "$(cat "$views/.identity/$name")" ]]; then
                unlink "$original" || [[ ! -S "$original" ]]
            fi
        done
    else
        for socket in "$view"/*; do unreachable "${socket##*/}" ListingFailed; done
    fi
done
exit "$partial"

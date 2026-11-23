#!/bin/bash
# The stderr watcher of a `yen sessions --host` ssh run (lib/sessions-remote.sh,
# remote_run_watched): sessions-remote-watch.sh <ssh pid> <scratch dir> <list|attach> <text> [<marked>]
#
# Tailscale SSH under a `check` rule whose approval is due holds sign-in and
# sends an auth banner with a per-connection approval link, which ssh prints on
# stderr. list: on the banner, mark <scratch>/check and end ssh, because a
# listing cannot be approved. attach: from the banner until sign-in (the
# LocalCommand marker <scratch>/connected), copy each new line of stderr to
# this process's stderr, the terminal, so the link shows while ssh waits, and
# record how many lines were shown in <scratch>/shown. It never opens the link
# or answers anything, and it ends with ssh or when the scratch directory goes.
#
# attach with <marked> 1 (the CLI showed the reconnecting mark): until sign-in,
# write the mark to stdout, the pane, every 10 seconds, because the engine
# drops it after 15 and a check can hold sign-in for 30 minutes. If sign-in
# came while it wrote, clear it again, since the LocalCommand's clear may have
# gone first.
child=$1 scratch=$2 mode=$3 text=$4 marked=${5:-0} shown=0 seen=0 ticks=0
while kill -0 "$child" 2> /dev/null && [ -d "$scratch" ]; do
    if [ "$seen" = 0 ] && [ -s "$scratch/err" ] && LC_ALL=C grep -qF "$text" "$scratch/err"; then
        seen=1
        if [ "$mode" = list ]; then
            : > "$scratch/check"
            kill -TERM "$child" 2> /dev/null
            exit 0
        fi
    fi
    if [ "$seen" = 1 ]; then
        [ -e "$scratch/connected" ] && exit 0
        total=$(wc -l < "$scratch/err")
        total=$((total))
        if [ "$total" -gt "$shown" ]; then
            sed -n "$((shown + 1)),${total}p" "$scratch/err" \
                | LC_ALL=C sed -e $'s/\r$//' -e 's/[[:cntrl:]]/?/g' -e $'s/\xc2[\x80-\x9f]/?/g' >&2
            shown=$total
            echo "$shown" > "$scratch/shown"
        fi
    fi
    if [ "$mode" = attach ] && [ "$marked" = 1 ] && [ ! -e "$scratch/connected" ]; then
        ticks=$((ticks + 1))
        if [ "$ticks" -ge 50 ]; then
            ticks=0
            printf '\033]9;4;4;0\007'
            [ -e "$scratch/connected" ] && printf '\033]9;4;0\007'
        fi
    fi
    /bin/sleep 0.2
done

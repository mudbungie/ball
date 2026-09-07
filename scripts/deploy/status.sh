#!/bin/sh
# What this box is running, what the registry offers, and whether the timer is
# armed (bl-4316) — `make deploy-status`. A read: it installs nothing, arms
# nothing, and is safe to run at any time.
#
# It asks each binary rather than any bookkeeping, for the reason
# `bl-update` does: cargo's records can disagree with the file after a hand
# install, and the file is what an agent will run.
set -eu

bin="$HOME/.local/bin"

printf 'installed:\n'
if [ -x "$bin/bl" ]; then
    "$bin/bl" --version 2>/dev/null | sed 's/^/  /' || printf '  bl: states no version\n'
    "$bin/bl" --version 2>/dev/null \
        | awk 'NR==1 && $3 == "(plugins:" { for (i = 4; i <= NF; i++) { sub(/\)$/, "", $i); print $i } }' \
        | while IFS= read -r p; do
            if [ -x "$bin/$p" ]; then
                "$bin/$p" --version 2>/dev/null | sed 's/^/  /' || printf '  %s: states no version\n' "$p"
            else
                printf '  %s: ABSENT beside bl\n' "$p"
            fi
        done
else
    printf '  no bl at %s\n' "$bin/bl"
fi

printf 'newest live on crates.io:\n'
if index=$(curl -fsS --max-time 30 https://index.crates.io/ba/ll/balls 2>/dev/null); then
    printf '%s\n' "$index" | while IFS= read -r line; do
        case $line in *'"yanked":false'*) ;; *) continue ;; esac
        v=${line#*'"vers":"'}
        printf '%s\n' "${v%%'"'*}"
    done | sort -V | tail -1 | sed 's/^/  balls /'
else
    printf '  unreachable\n'
fi

printf 'timer:\n'
systemctl --user list-timers 'bl-update.timer' --no-pager 2>/dev/null | sed 's/^/  /' \
    || printf '  no systemctl on this box\n'
systemctl --user is-enabled bl-update.timer 2>/dev/null | sed 's/^/  enabled: /' || true

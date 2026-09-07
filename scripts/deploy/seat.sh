#!/bin/sh
# Seat the continuous-deployment timer for `bl` and its plugin set on THIS box
# (bl-4316):
#
#   make deploy-local
#
# **This box and no other, and that is the whole carrier question.** The engine
# and the foot ship a remote form because the box that most needs them is a
# server somebody reaches over ssh. `bl` is the tool an operator or an agent
# reaches for AT A PROMPT — which is the box somebody is sitting at, and that
# box cannot ssh to itself. Nothing here is committed about any machine: no
# address, account or host name, which is the leak gate's rule and the
# severability one at once. Seating a second box is three `scp`s and a
# `systemctl --user enable --now` of the same three files.
#
# **It seats a timer; it does not carry a build.** Nothing is compiled here.
# The unit of install is a published version and crates.io already serves it,
# so what is laid down is three small text files and the box installs from the
# registry on its own schedule from then on.
#
# **It restarts nothing, because there is nothing to restart.** `bl` is a
# program somebody runs to completion; `cargo install` replaces each binary by
# rename, so an op already running finishes on the build it started under and
# the next invocation is the new one.
#
# Idempotent, and the upgrade path: re-run it to move this box to this
# checkout's reconciler.
#
# **Its last act runs the reconciler once, synchronously, and its exit code is
# this script's** — so seating either ends with the newest release installed as
# a coherent set, or says why, rather than reporting that a timer was enabled
# and leaving the first real answer an hour away. That first tick is also the
# only thing that proves the box can reach the index and has a toolchain at
# all, so it is the one worth waiting for.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
die() { printf '%s: %s\n' "${0##*/}" "$*" >&2; exit 1; }

command -v systemctl >/dev/null 2>&1 \
    || die 'no systemctl on this box: the timer has nowhere to be seated'

say 'seating the reconciler on this box'
mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"
# To a temp name and then `mv` into place: the reconciler may be running right
# now (the timer is armed from a previous seating), and a plain copy truncates
# before it writes. rename(2) in the same directory means a running shell reads
# whole-old or whole-new and never a half file.
install -m 0755 "$here/bl-update" "$HOME/.local/bin/.bl-update.tmp"
mv -f "$HOME/.local/bin/.bl-update.tmp" "$HOME/.local/bin/bl-update"
install -m 0644 "$here/bl-update.service" "$HOME/.config/systemd/user/bl-update.service"
install -m 0644 "$here/bl-update.timer" "$HOME/.config/systemd/user/bl-update.timer"

say 'arming the timer'
systemctl --user daemon-reload
systemctl --user reset-failed bl-update.service 2>/dev/null || true
systemctl --user enable --now bl-update.timer

# The verification, and it is the reconciler itself rather than a probe of one.
# `systemctl --user start` blocks on a `Type=oneshot` unit and exits non-zero
# when it fails, so this is a real end-to-end run — the index reached, the
# versions compared, the build done if there was one — and not a status print.
say 'running the first reconcile (a cold build of the crate is not quick)'
if ! systemctl --user start bl-update.service; then
    journalctl --user -u bl-update.service --no-pager --lines=30 2>&1 | sed 's/^/  | /' >&2
    die 'the first reconcile failed (the timer is armed; it will retry)'
fi

journalctl --user -u bl-update.service --no-pager --lines=10 -o cat 2>/dev/null || true
say 'seated: this box tracks released versions hourly'

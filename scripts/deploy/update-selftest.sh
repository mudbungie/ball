#!/bin/sh
# Drive the REAL `scripts/deploy/bl-update` under fake `curl` and `cargo`
# (bl-4316) — `make deploy-selftest`, and a step of `make check`.
#
# **Both directions, every case.** A reconciler that never installs and one
# that installs on every tick are both green to a test that only checks the
# exit code, and the second is the expensive one: it rebuilds a crate hourly on
# a workstation. So each case asserts what the run SAID and whether `cargo
# install` was reached at all — the fake cargo writes a receipt, and its
# absence is as much an assertion as its content.
#
# Nothing here touches the operator's box: HOME is a scratch directory, the
# only `curl` and `cargo` on PATH are the fakes, and the "installed" binaries
# are three-line shell scripts that print a version line.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
UPDATE="$here/bl-update"
PLUGINS='bl-chore bl-delivery bl-speculate bl-tracker'

fails=0
pass() { printf 'ok   %s\n' "$*"; }
fail() { printf 'FAIL %s\n' "$*"; fails=$((fails + 1)); }
check() { # <condition-result> <label>
    if [ "$1" -eq 0 ]; then pass "$2"; else fail "$2"; fi
}

# A scratch box: $HOME/.local/bin holding fake binaries, and a PATH whose only
# curl/cargo are the shims below.
box() {
    BOX=$(mktemp -d)
    mkdir -p "$BOX/bin" "$BOX/home/.local/bin"
    cat > "$BOX/bin/curl" <<'SH'
#!/bin/sh
[ -f "$INDEX_FIXTURE" ] || exit 22
cat "$INDEX_FIXTURE"
SH
    # The fake cargo writes a receipt AND converges the box, so a second run of
    # the reconciler over the same box is the "already current" case — which is
    # what proves an install is not repeated forever.
    cat > "$BOX/bin/cargo" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$RECEIPT"
v=""
while [ $# -gt 0 ]; do
    case $1 in --version) v=$2; shift ;; esac
    shift
done
mkdir -p "$HOME/.local/bin"
for b in bl bl-chore bl-delivery bl-speculate bl-tracker; do
    if [ "$b" = bl ]; then
        printf '#!/bin/sh\necho "bl %s (plugins: bl-chore bl-delivery bl-speculate bl-tracker)"\n' "$v" \
            > "$HOME/.local/bin/$b"
    else
        printf '#!/bin/sh\necho "%s %s"\n' "$b" "$v" > "$HOME/.local/bin/$b"
    fi
    chmod 755 "$HOME/.local/bin/$b"
done
SH
    chmod 755 "$BOX/bin/curl" "$BOX/bin/cargo"
    RECEIPT="$BOX/cargo-receipt"
    : > "$RECEIPT"
    export RECEIPT
    HOME="$BOX/home"
    export HOME
    PATH="$BOX/bin:/usr/bin:/bin"
    export PATH
}

# Lay down a fake installed binary that answers `--version` with `$2`.
seat_bin() { # <name> <version>
    if [ "$1" = bl ]; then
        printf '#!/bin/sh\necho "bl %s (plugins: %s)"\n' "$2" "$PLUGINS" > "$HOME/.local/bin/bl"
    else
        printf '#!/bin/sh\necho "%s %s"\n' "$1" "$2" > "$HOME/.local/bin/$1"
    fi
    chmod 755 "$HOME/.local/bin/$1"
}

seat_set() { # <version>
    seat_bin bl "$1"
    for p in $PLUGINS; do seat_bin "$p" "$1"; done
}

index() { # <line>...
    INDEX_FIXTURE="$BOX/index.json"
    export INDEX_FIXTURE
    : > "$INDEX_FIXTURE"
    for v in "$@"; do printf '%s\n' "$v" >> "$INDEX_FIXTURE"; done
}

entry() { printf '{"name":"balls","vers":"%s","yanked":%s}\n' "$1" "$2"; }

# ---------------------------------------------------------------------------
box
index "$(entry 0.5.10 false)" "$(entry 0.5.11 false)"
seat_set 0.5.11
OUT=$("$UPDATE" 2>&1) && RC=0 || RC=$?
check "$RC" 'a current, coherent box exits 0'
case $OUT in *'is current'*) check 0 'it says the install is current' ;;
             *) check 1 "it says the install is current (said: $OUT)" ;; esac
check "$([ ! -s "$RECEIPT" ] && echo 0 || echo 1)" 'it reaches no cargo install'
rm -rf "$BOX"

# ---------------------------------------------------------------------------
box
index "$(entry 0.5.11 false)" "$(entry 0.5.12 false)"
seat_set 0.5.11
OUT=$("$UPDATE" 2>&1) && RC=0 || RC=$?
check "$RC" 'a stale box exits 0'
case $OUT in *'installing 0.5.12 (was 0.5.11)'*) check 0 'it names both versions' ;;
             *) check 1 "it names both versions (said: $OUT)" ;; esac
case $(cat "$RECEIPT") in *'--version 0.5.12'*--force*--root*) check 0 'cargo is asked for the exact newest, forced, into the install root' ;;
                          *) check 1 "cargo argv (was: $(cat "$RECEIPT"))" ;; esac
# ...and the SECOND run over the converged box installs nothing. This is the
# case that catches a reconciler that reinstalls forever.
: > "$RECEIPT"
"$UPDATE" >/dev/null 2>&1
check "$([ ! -s "$RECEIPT" ] && echo 0 || echo 1)" 'a second tick over the converged box installs nothing'
rm -rf "$BOX"

# ---------------------------------------------------------------------------
box
index "$(entry 0.5.12 false)"
OUT=$("$UPDATE" 2>&1) && RC=0 || RC=$?
check "$RC" 'a box with no bl at all exits 0'
case $OUT in *'was absent'*) check 0 'it names the absence rather than an empty version' ;;
             *) check 1 "it names the absence (said: $OUT)" ;; esac
rm -rf "$BOX"

# ---------------------------------------------------------------------------
# The coherence arm: bl is at the newest version, one plugin beside it is not.
box
index "$(entry 0.5.12 false)"
seat_set 0.5.12
seat_bin bl-delivery 0.5.9
OUT=$("$UPDATE" 2>&1) && RC=0 || RC=$?
check "$RC" 'an incoherent set exits 0'
case $OUT in *'incoherent'*'bl-delivery 0.5.9'*) check 0 'it names the disagreeing sibling and its version' ;;
             *) check 1 "it names the disagreeing sibling (said: $OUT)" ;; esac
check "$([ -s "$RECEIPT" ] && echo 0 || echo 1)" 'it reinstalls the crate to repair the set'
rm -rf "$BOX"

# ---------------------------------------------------------------------------
# A plugin missing outright is the same finding, reported as absent.
box
index "$(entry 0.5.12 false)"
seat_set 0.5.12
rm -f "$HOME/.local/bin/bl-tracker"
OUT=$("$UPDATE" 2>&1) && RC=0 || RC=$?
case $OUT in *'bl-tracker absent'*) check 0 'an absent sibling reads as absent, not as a version' ;;
             *) check 1 "an absent sibling reads as absent (said: $OUT)" ;; esac
rm -rf "$BOX"

# ---------------------------------------------------------------------------
# The yank IS the rollback lever: the newest live version is the newest
# non-yanked one, so yanking 0.5.12 puts an 0.5.11 box back on 0.5.11 — and
# an 0.5.12 box back DOWN to it.
box
index "$(entry 0.5.11 false)" "$(entry 0.5.12 true)"
seat_set 0.5.12
OUT=$("$UPDATE" 2>&1) && RC=0 || RC=$?
check "$RC" 'a yanked newest exits 0'
case $OUT in *'installing 0.5.11 (was 0.5.12)'*) check 0 'a yank rolls the box back' ;;
             *) check 1 "a yank rolls the box back (said: $OUT)" ;; esac
rm -rf "$BOX"

# ---------------------------------------------------------------------------
# An unreachable registry is a failure, not a silent no-op — the whole point of
# reading the fetch and the parse as two statements.
box
INDEX_FIXTURE="$BOX/nope"
export INDEX_FIXTURE
seat_set 0.5.11
OUT=$("$UPDATE" 2>&1) && RC=0 || RC=$?
check "$([ "$RC" -ne 0 ] && echo 0 || echo 1)" 'an unreachable registry exits non-zero'
case $OUT in *'cannot reach the registry'*) check 0 'it names the registry as the failure' ;;
             *) check 1 "it names the registry (said: $OUT)" ;; esac
check "$([ ! -s "$RECEIPT" ] && echo 0 || echo 1)" 'and installs nothing on the way out'
rm -rf "$BOX"

# ---------------------------------------------------------------------------
# An index that parses to nothing is its own failure, distinct from the above.
box
index
seat_set 0.5.11
OUT=$("$UPDATE" 2>&1) && RC=0 || RC=$?
check "$([ "$RC" -ne 0 ] && echo 0 || echo 1)" 'an empty index exits non-zero'
case $OUT in *'named no live version'*) check 0 'it distinguishes an empty index from an unreachable one' ;;
             *) check 1 "it distinguishes an empty index (said: $OUT)" ;; esac
rm -rf "$BOX"

if [ "$fails" -ne 0 ]; then
    printf '\n%s selftest assertion(s) failed\n' "$fails" >&2
    exit 1
fi
printf '\ndeploy selftest: all assertions passed\n'

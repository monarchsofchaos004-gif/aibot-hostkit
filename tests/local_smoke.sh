#!/usr/bin/env bash
# Quick checks that need no containers: syntax, embed sync, --plan, --dry-run, no-tty refusal.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAILS=0
chk() { if "${@:2}" >/dev/null 2>&1; then echo "PASS $1"; else echo "FAIL $1"; FAILS=$((FAILS + 1)); fi; }
H=$(mktemp -d)
export HOME="$H"
chk "bash -n install.sh" bash -n "$ROOT/install.sh"
chk "bash -n bin/aibot" bash -n "$ROOT/bin/aibot"
chk "embedded aibot in sync" "$ROOT/tools/sync-embed.sh" --check
chk "--plan" bash "$ROOT/install.sh" --plan
chk "--dry-run" bash "$ROOT/install.sh" --dry-run --with tmux,claude,remote,guard,notify-ntfy,rules --yes </dev/null
chk "dry-run touched nothing" test ! -e "$H/.aibot"
chk "no tty without --with fails fast" bash -c "! bash '$ROOT/install.sh' </dev/null"
lines=$(wc -l <"$ROOT/install.sh")
chk "install.sh <= 1500 lines ($lines)" test "$lines" -le 1500
rm -rf "$H"
exit "$FAILS"

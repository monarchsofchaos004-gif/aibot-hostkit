#!/usr/bin/env bash
# Copy bin/aibot into the heredoc inside install.sh (single-file installer for curl|bash).
# Usage: tools/sync-embed.sh [--check]
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp)
awk '
  /^  cat >"\$AIBOT_HOME\/bin\/aibot" <<.AIBOT_BIN_EOF.$/ { print; while ((getline line < "bin/aibot") > 0) print line; skip=1; next }
  skip && /^AIBOT_BIN_EOF$/ { skip=0 }
  !skip { print }
' install.sh >"$tmp"
if [ "${1:-}" = "--check" ]; then
  if cmp -s "$tmp" install.sh; then echo "embed in sync"; rm -f "$tmp"; exit 0; fi
  echo "embed OUT OF SYNC: run tools/sync-embed.sh"; rm -f "$tmp"; exit 1
fi
cat "$tmp" >install.sh
rm -f "$tmp"
echo "synced"

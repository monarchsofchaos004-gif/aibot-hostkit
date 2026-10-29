#!/usr/bin/env bash
# Runs on the Docker test host. Usage: docker_test.sh <path-to-aibot-hostkit>
# Touches ONLY containers named aibot-test-* and the images it pulled itself.
# Scenarios: A ubuntu24.04 root (+cron), B ubuntu24.04 user with sudo, C debian12 user WITHOUT sudo.
set -u
SRC="${1:?path to aibot-hostkit}"
D="sudo -n docker"
LOG=/tmp/aibot-test-logs
mkdir -p "$LOG"
PULLED=""

cleanup() {
  for n in aibot-test-A aibot-test-B aibot-test-C; do $D rm -f "$n" >/dev/null 2>&1 || true; done
}
trap cleanup EXIT
cleanup

pull_if_missing() {
  if ! $D image inspect "$1" >/dev/null 2>&1; then $D pull -q "$1" >/dev/null && PULLED="$PULLED $1"; fi
}

start() { # start name image
  $D run -d --rm --memory 1g --name "$1" "$2" sleep 7200 >/dev/null || return 1
  $D cp "$SRC" "$1:/opt/aibot-hostkit" && $D exec -u 0 "$1" chmod -R a+rX /opt/aibot-hostkit
}

prep_root() { # prep_root name extra-packages
  $D exec -u 0 "$1" bash -c "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq >/dev/null && apt-get install -y -qq curl ca-certificates jq $2 >/dev/null 2>&1"
}

pull_if_missing ubuntu:24.04
pull_if_missing debian:12

start aibot-test-A ubuntu:24.04 && prep_root aibot-test-A "cron"
$D exec -u 0 aibot-test-A bash -c 'cron'
start aibot-test-B ubuntu:24.04 && prep_root aibot-test-B "sudo"
$D exec -u 0 aibot-test-B bash -c 'useradd -m -s /bin/bash bob && echo "bob ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/bob'
start aibot-test-C debian:12 && prep_root aibot-test-C ""
$D exec -u 0 aibot-test-C bash -c 'useradd -m -s /bin/bash carol'
$D exec -u 0 aibot-test-C bash -c 'command -v sudo' >/dev/null 2>&1 && echo "WARN: debian image unexpectedly has sudo"

$D exec -u 0 -e HOME=/root aibot-test-A bash /opt/aibot-hostkit/tests/inner.sh "A:ubuntu24-root+cron" 1 1 >"$LOG/A.log" 2>&1 &
pa=$!
$D exec -u bob -e HOME=/home/bob -w /home/bob aibot-test-B bash /opt/aibot-hostkit/tests/inner.sh "B:ubuntu24-sudo" 1 0 >"$LOG/B.log" 2>&1 &
pb=$!
$D exec -u carol -e HOME=/home/carol -w /home/carol aibot-test-C bash /opt/aibot-hostkit/tests/inner.sh "C:debian12-nosudo" 0 0 >"$LOG/C.log" 2>&1 &
pc=$!
wait "$pa"; ra=$?
wait "$pb"; rb=$?
wait "$pc"; rc=$?
cat "$LOG/A.log" "$LOG/B.log" "$LOG/C.log"

# static analysis in a separate throw-away container
pull_if_missing koalaman/shellcheck:stable
$D run --rm --memory 1g -v "$SRC:/mnt:ro" koalaman/shellcheck:stable -s bash -x /mnt/install.sh /mnt/bin/aibot /mnt/tools/sync-embed.sh /mnt/tests/inner.sh /mnt/tests/docker_test.sh >"$LOG/shellcheck.log" 2>&1
echo "SHELLCHECK exit=$? (log: $LOG/shellcheck.log)"
grep -cE "\(error\)" "$LOG/shellcheck.log" | sed 's/^/SHELLCHECK errors: /'
grep -cE "\(warning\)" "$LOG/shellcheck.log" | sed 's/^/SHELLCHECK warnings: /'

cleanup
for img in $PULLED; do $D rmi "$img" >/dev/null 2>&1 || true; done
echo "SCENARIO exit codes: A=$ra B=$rb C=$rc"
[ $((ra + rb + rc)) -eq 0 ]

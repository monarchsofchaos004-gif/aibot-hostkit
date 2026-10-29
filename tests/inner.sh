#!/usr/bin/env bash
# Runs INSIDE a throw-away container as the test user. Usage: inner.sh <label> <has_sudo:1|0> <cron:1|0>
# Prints PASS/FAIL lines; exit code = number of failures. Never logs in to a real Claude account:
# the claude binary may be installed (official installer) but the session runs a harmless shim.
set -u
LABEL="${1:-?}" HAS_SUDO="${2:-0}" CRON="${3:-0}"
SRC=/opt/aibot-hostkit
FAILS=0
t_start=$(date +%s)

pass() { printf 'PASS [%s] %s\n' "$LABEL" "$1"; }
fail() { printf 'FAIL [%s] %s\n' "$LABEL" "$1"; FAILS=$((FAILS + 1)); }
ok_if() { # ok_if "desc" cmd...
  local d="$1"
  shift
  if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi
}
AIBOT="$HOME/.aibot/bin/aibot"

# ---- shim claude: just sleeps, never touches a real account
mkdir -p /tmp/aibot-shim
printf '#!/bin/bash\nexec sleep 100000\n' >/tmp/aibot-shim/claude
chmod +x /tmp/aibot-shim/claude
export AIBOT_CLAUDE_CMD=/tmp/aibot-shim/claude

# ---- 1. --plan
out=$(bash "$SRC/install.sh" --plan --lang en 2>&1)
case "$out" in *"[tmux]"*"[notify-line]"*"[shared]"*"[uninstall]"*) pass "--plan lists components" ;; *) fail "--plan lists components" ;; esac
out=$(bash "$SRC/install.sh" --plan --lang zh 2>&1)
case "$out" in *"使用者要準備"*) pass "--plan zh" ;; *) fail "--plan zh" ;; esac

# ---- 2. dry-run changes nothing
out=$(bash "$SRC/install.sh" --lang en --dry-run --with tmux,claude,remote,guard,notify-ntfy,rules --yes 2>&1) || fail "dry-run exit code"
case "$out" in *"[dry-run]"*) pass "--dry-run prints actions" ;; *) fail "--dry-run prints actions" ;; esac
[ ! -e "$HOME/.aibot" ] && [ ! -e "$HOME/work" ] && pass "--dry-run created nothing" || fail "--dry-run created nothing"

out=$(bash "$SRC/install.sh" --lang en --dry-run --with codex,gemini --yes 2>&1)
case "$out" in *"npm install -g --prefix"*"@openai/codex"*"@google/gemini-cli"*) pass "dry-run shows official npm install commands for codex+gemini" ;; *) fail "dry-run codex/gemini commands" ;; esac
[ ! -e "$HOME/.local/bin/codex" ] && pass "dry-run did not install codex" || fail "dry-run did not install codex"

# ---- 3. no tty and no --with -> clear refusal, no hang
out=$(bash "$SRC/install.sh" --lang en </dev/null 2>&1 | head -3)
case "$out" in *"--with"*) pass "no tty -> asks for --with" ;; *) fail "no tty -> asks for --with" ;; esac

# ---- 4. real install
[ "$CRON" = 1 ] && { crontab -l >/dev/null 2>&1 || true; }
out=$(bash "$SRC/install.sh" --lang en --with tmux,claude,remote,guard,notify-ntfy,rules --yes 2>&1)
rc=$?
printf '%s\n' "$out" >"/tmp/install_$LABEL.out"
if [ "$HAS_SUDO" = 1 ]; then
  [ "$rc" = 0 ] && pass "install rc=0" || fail "install rc=$rc"
  ok_if "tmux installed" command -v tmux
  ok_if "claude binary installed (official installer)" test -x "$HOME/.local/bin/claude"
  ok_if "session aibot up" tmux has-session -t aibot
  mode=$(grep -o "^AIBOT_GUARD_MODE=.*" "$HOME/.aibot/config.env" | cut -d= -f2)
  if [ "$CRON" = 1 ]; then [ "$mode" = cron ] && pass "guard mode cron" || fail "guard mode cron (got $mode)"
  else [ "$mode" = tmux ] && pass "guard mode tmux fallback" || fail "guard mode tmux (got $mode)"; fi
else
  [ "$rc" = 0 ] && pass "install rc=0 without sudo (skips are not failures)" || fail "install rc=$rc without sudo"
  case "$out" in *"component=tmux status=skipped"*) pass "tmux clearly skipped without sudo" ;; *) fail "tmux clearly skipped without sudo" ;; esac
  case "$out" in *"component=remote status=skipped"*) pass "remote skipped (no tmux)" ;; *) fail "remote skipped (no tmux)" ;; esac
  ok_if "claude still installed in user space" test -x "$HOME/.local/bin/claude"
fi
[ "$(stat -c %a "$HOME/.aibot/secrets.env")" = 600 ] && pass "secrets.env is 600" || fail "secrets.env is 600"
topic=$(grep -o "^AIBOT_NTFY_TOPIC=.*" "$HOME/.aibot/secrets.env" | cut -d= -f2)
[ -n "$topic" ] && pass "ntfy topic generated" || fail "ntfy topic generated"
case "$out" in *"ntfy: ok"* | *"Test message sent"*) pass "ntfy test message sent" ;; *) fail "ntfy test message sent (network?)" ;; esac
[ "$(grep -c aibot-hostkit "$HOME/.bashrc")" = 1 ] && pass "PATH line in .bashrc once" || fail "PATH line in .bashrc once"
ok_if "CLAUDE.md template written" test -s "$HOME/work/CLAUDE.md"

# ---- 5. idempotent re-run
bash "$SRC/install.sh" --lang en --with tmux,remote,guard,rules --yes >/tmp/rerun_"$LABEL".out 2>&1
[ "$(grep -c aibot-hostkit "$HOME/.bashrc")" = 1 ] && pass "re-run: PATH line still once" || fail "re-run: PATH line still once"
ok_if "re-run: existing CLAUDE.md not overwritten" test -s "$HOME/work/CLAUDE.aibot.md"
if [ "$CRON" = 1 ]; then
  [ "$(crontab -l | grep -c aibot-hostkit)" = 2 ] && pass "re-run: crontab entries not duplicated" || fail "re-run: crontab entries not duplicated"
fi

# ---- 6. doctor
if [ "$HAS_SUDO" = 1 ]; then
  d=$("$AIBOT" doctor 2>&1); drc=$?
  printf '%s\n' "$d" >"/tmp/doctor_$LABEL.out"
  [ "$drc" = 0 ] && pass "doctor: no FAIL ($(printf '%s' "$d" | tail -1))" || { fail "doctor has FAIL"; printf '%s\n' "$d"; }
else
  d=$("$AIBOT" doctor 2>&1); drc=$?
  [ "$drc" != 0 ] && pass "doctor reports problems when tmux missing" || fail "doctor should flag missing tmux"
fi
"$AIBOT" status >/dev/null 2>&1 && pass "status runs" || fail "status runs"

# ---- 7. guard: kill claude, expect restart <= 70 s, log, notify rate limit
if [ "$HAS_SUDO" = 1 ]; then
  pane_pid() { tmux list-panes -t aibot:agent -F '#{pane_pid}' 2>/dev/null | head -1; }
  wait_restart() { # wait_restart old_pid -> echo seconds or FAIL
    local old="$1" s=0 p
    while [ "$s" -lt 100 ]; do
      p=$(pane_pid)
      if [ -n "$p" ] && [ "$p" != "$old" ] && kill -0 "$p" 2>/dev/null; then echo "$s"; return 0; fi
      sleep 1
      s=$((s + 1))
    done
    echo FAIL
  }
  p1=$(pane_pid)
  kill -9 "$p1"
  secs=$(wait_restart "$p1")
  if [ "$secs" != FAIL ] && [ "$secs" -le 70 ]; then pass "guard restarted claude after ${secs}s (<=70)"; else fail "guard restart took $secs"; fi
  grep -qE "agent process was gone|session .aibot. was missing" "$HOME/.aibot/logs/guard.log" && pass "guard.log records the restart" || fail "guard.log records the restart"
  p2=$(pane_pid)
  kill -9 "$p2"
  secs2=$(wait_restart "$p2")
  if [ "$secs2" != FAIL ] && [ "$secs2" -le 70 ]; then pass "second restart after ${secs2}s"; else fail "second restart took $secs2"; fi
  sent=$(grep -cE "notify (sent|failed)" "$HOME/.aibot/logs/guard.log")
  supp=$(grep -c "notify suppressed" "$HOME/.aibot/logs/guard.log")
  if [ "$sent" = 1 ] && [ "$supp" -ge 1 ]; then pass "notify rate limit: 1 sent, $supp suppressed"; else fail "notify rate limit (sent=$sent suppressed=$supp)"; fi
  # whole session killed -> recreated (cron mode only; tmux mode guard lives inside the session)
  if [ "$CRON" = 1 ]; then
    tmux kill-session -t aibot
    s=0; while [ "$s" -lt 100 ] && ! tmux has-session -t aibot 2>/dev/null; do sleep 1; s=$((s + 1)); done
    [ "$s" -le 70 ] && pass "killed session recreated after ${s}s" || fail "killed session not recreated (${s}s)"
  fi
  # stop pauses the guard
  "$AIBOT" stop >/dev/null 2>&1
  sleep 5
  tmux has-session -t aibot 2>/dev/null && fail "stop leaves session down" || pass "stop leaves session down"
  "$AIBOT" start >/dev/null 2>&1
  tmux has-session -t aibot 2>/dev/null && pass "start brings it back" || fail "start brings it back"
fi

# ---- 8. secrets are never printed (fake telegram token)
FAKE="0000000000:AAFAKEtokenForTestingOnly_abcdef"
out=$(AIBOT_TG_TOKEN="$FAKE" AIBOT_TG_CHAT=12345 bash "$SRC/install.sh" --lang en --with notify-telegram --yes 2>&1)
case "$out" in *"$FAKE"*) fail "token leaked into installer output" ;; *) pass "token not in installer output" ;; esac
ok_if "token stored in secrets.env" grep -q "AIBOT_TG_TOKEN" "$HOME/.aibot/secrets.env"
nout=$("$AIBOT" notify "x" 2>&1)
case "$nout" in *"$FAKE"*) fail "token leaked by aibot notify" ;; *) pass "token not in notify output" ;; esac
grep -rq "$FAKE" "$HOME/.aibot/logs" 2>/dev/null && fail "token leaked into logs" || pass "token not in logs"
out=$(env -u AIBOT_TG_TOKEN bash "$SRC/install.sh" --lang en --with notify-discord --yes 2>&1)
case "$out" in *"component=notify-discord status=skipped"*) pass "missing env secret -> component skipped with explanation" ;; *) fail "missing env secret skip" ;; esac

# ---- 9. interactive path via a pty (reads /dev/tty); answer n to everything but rules
if command -v script >/dev/null 2>&1; then
  rm -f "$HOME/work/CLAUDE.md" "$HOME/work/CLAUDE.aibot.md"
  # answers are typed slowly: sudo/tcsetattr flushes input typed ahead during the preflight
  { sleep 8; for a in n n n n n n n n n n y n; do printf '%s\n' "$a"; sleep 0.4; done; sleep 2; } |
    timeout 90 script -qec "bash $SRC/install.sh --lang en" /dev/null >/tmp/inter_"$LABEL".out 2>&1
  ok_if "interactive (tty) run installed rules only" test -s "$HOME/work/CLAUDE.md"
fi


# ---- 9b. other agents (stand-in shims only; never installs/logs in to codex/gemini) and no-AI mode
if [ "$HAS_SUDO" = 1 ]; then
  printf '#!/bin/bash\nexec sleep 100000\n' >/tmp/aibot-shim/codex
  cp /tmp/aibot-shim/codex /tmp/aibot-shim/gemini
  cp /tmp/aibot-shim/codex /tmp/aibot-shim/mycmd
  chmod +x /tmp/aibot-shim/*
  agent_cycle() { # agent_cycle label install-args... : install, kill, expect restart <=70s
    local lbl="$1" pp np s2
    shift
    "$AIBOT" uninstall --yes >/dev/null 2>&1
    bash "$SRC/install.sh" --lang en "$@" --yes >/tmp/agent_"$LABEL"_"$lbl".out 2>&1 || fail "$lbl: install failed"
    tmux has-session -t aibot 2>/dev/null && pass "$lbl: session up" || fail "$lbl: session up"
    pp=$(tmux list-panes -t aibot:agent -F '#{pane_pid}' | head -1)
    tr '\0' ' ' </proc/"$pp"/cmdline | grep -q "sleep" && pass "$lbl: pane runs the stand-in" || fail "$lbl: pane runs the stand-in"
    kill -9 "$pp"
    s2=0
    while [ "$s2" -lt 100 ]; do
      np=$(tmux list-panes -t aibot:agent -F '#{pane_pid}' 2>/dev/null | head -1)
      if [ -n "$np" ] && [ "$np" != "$pp" ] && kill -0 "$np" 2>/dev/null; then break; fi
      sleep 1
      s2=$((s2 + 1))
    done
    [ "$s2" -le 70 ] && pass "$lbl: guard restarted it after ${s2}s" || fail "$lbl: restart took ${s2}s"
    grep -qE "agent process was gone|was missing" "$HOME/.aibot/logs/guard.log" && pass "$lbl: guard.log has it" || fail "$lbl: guard.log has it"
  }
  export AIBOT_CODEX_CMD=/tmp/aibot-shim/codex AIBOT_GEMINI_CMD=/tmp/aibot-shim/gemini
  agent_cycle codex --with tmux,remote,guard --agent codex
  agent_cycle gemini --with tmux,remote,guard --agent gemini
  unset AIBOT_CODEX_CMD AIBOT_GEMINI_CMD AIBOT_CLAUDE_CMD
  agent_cycle noai --with tmux,guard,notify-ntfy --cmd "/tmp/aibot-shim/mycmd one"
  grep -q "^AIBOT_CMD=" "$HOME/.aibot/config.env" && pass "noai: AIBOT_CMD stored" || fail "noai: AIBOT_CMD stored"
  "$AIBOT" doctor >/dev/null 2>&1 && pass "noai: doctor ok" || fail "noai: doctor ok"
fi

# ---- 9c. aibot audit: runs ONLY here, in this throw-away container, on a FAKE home full of fake secrets
S=SENTINEL_FAKE_
F=$(mktemp -d)
mk() { # mk relpath content [mode]
  mkdir -p "$(dirname "$F/$1")"
  printf '%s\n' "$2" >"$F/$1"
  chmod "${3:-600}" "$F/$1"
}
mkdir -p "$F/.ssh"
printf -- '-----BEGIN RSA PRIVATE KEY-----\n%sssh_rsa_body\n-----END RSA PRIVATE KEY-----\n' "$S" >"$F/.ssh/id_rsa"
chmod 644 "$F/.ssh/id_rsa" # the ONE file that is readable by others
printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\n%s\nAAAAAAAA\n%sssh_ed_body\n-----END OPENSSH PRIVATE KEY-----\n' \
  "$(printf 'openssh-key-v1\0\0\0\0\4none\0\0\0\4none\0\0\0\0\0' | base64 -w0)" "$S" >"$F/.ssh/id_ed25519"
chmod 600 "$F/.ssh/id_ed25519"
printf -- '-----BEGIN RSA PRIVATE KEY-----\nProc-Type: 4,ENCRYPTED\nDEK-Info: AES-128-CBC,%sdek\n%sbody\n-----END RSA PRIVATE KEY-----\n' "$S" "$S" >"$F/.ssh/id_enc"
chmod 600 "$F/.ssh/id_enc"
printf 'ssh-ed25519 %skey1 a@b\nssh-ed25519 %skey2 c@d\n' "$S" "$S" >"$F/.ssh/authorized_keys"
chmod 600 "$F/.ssh/authorized_keys"
mk .config/gh/hosts.yml "github.com: oauth_token: ${S}gh"
mk .git-credentials "https://u:${S}git@example.com"
mk .netrc "machine x password ${S}netrc"
mk .aws/credentials "aws_access_key_id=${S}aws"
mk .config/gcloud/application_default_credentials.json "${S}gcloud"
mk .azure/msal_token_cache.json "${S}azure"
{ printf '%s\n' "${S}kube"; head -c 1100000 /dev/zero | tr '\0' 'a'; echo; } >"$F/.kube-big"
mkdir -p "$F/.kube" && mv "$F/.kube-big" "$F/.kube/config" && chmod 600 "$F/.kube/config"
mk .docker/config.json "{\"auths\": {\"r.example\": {\"auth\": \"${S}docker\"}}}"
mk .npmrc "//registry.example/:_authToken=${S}npm"
printf '%s\n' "${S}outside_home" >"/tmp/outside_$LABEL"
ln -s "/tmp/outside_$LABEL" "$F/.pypirc"
mk .cargo/credentials.toml "token = \"${S}cargo\""
mk .config/rclone/rclone.conf "token = ${S}rclone"
mk .claude/.credentials.json "${S}claude"
mk .codex/auth.json "${S}codex"
mk .gemini/oauth_creds.json "${S}gemini"
mk .aibot/secrets.env "AIBOT_NTFY_TOPIC=${S}ntfy"
mkdir -p "$F/.config/google-chrome/Default" "$F/.config/google-chrome/Profile 1" "$F/.mozilla/firefox/abc.default"
printf '%s\n' "${S}cookie" >"$F/.config/google-chrome/Default/Cookies"
printf '%s\n' "${S}cookie" >"$F/.mozilla/firefox/abc.default/cookies.sqlite"
chmod 700 "$F/.config/google-chrome" "$F/.mozilla/firefox"
mk proj/.env "API_KEY=${S}envfile"
mk proj/clean.env "FOO=bar"
mk a/b/c/d/deep.env "API_KEY=${S}toodeep"
printf 'export GH_TOKEN=%shist1\ncurl --password %shist2 x\nls\n' "$S" "$S" >"$F/.bash_history"
chmod 600 "$F/.bash_history"
snap_before=$(find "$F" -printf '%p %m %s %T@\n' | sort | md5sum)
ab_audit() { env -i HOME="$F" PATH="$PATH" LANG=C FAKE_API_TOKEN="${S}envval" PLAIN_VAR=1 bash "$SRC/bin/aibot" audit "$@"; }
aj=$(ab_audit --json --lang en); arc=$?
at=$(ab_audit --lang en)
az=$(ab_audit --lang zh)
snap_after=$(find "$F" -printf '%p %m %s %T@\n' | sort | md5sum)
[ "$arc" = 0 ] && pass "audit --json exit code 0 (findings are not errors)" || fail "audit exit code $arc"
miss=""
for c in ssh-key ssh-authorized github-cli git-credentials netrc aws gcloud azure kube docker npm pypi cargo rclone claude codex gemini aibot-secrets browser env-file shell-history env-var; do
  case "$aj" in *"\"category\":\"$c\""*) ;; *) miss="$miss $c" ;; esac
done
[ -z "$miss" ] && pass "audit lists every category" || fail "audit missing categories:$miss"
case "$aj$at$az" in *SENTINEL_FAKE_*) fail "audit output leaked a fake secret" ;; *) pass "audit output contains no secret content (text, json, zh)" ;; esac
njson=$(printf '%s\n' "$aj" | grep -c '"category"')
ntext=$(printf '%s\n' "$at" | grep -c '^- ')
[ "$njson" = "$ntext" ] && [ "$njson" -ge 22 ] && pass "audit text and json agree ($njson items)" || fail "audit item counts differ (json=$njson text=$ntext)"
[ "$(printf '%s\n' "$at" | grep -c '⚠')" = 1 ] && printf '%s\n' "$at" | grep '⚠' | grep -q '~/.ssh/id_rsa' && pass "only the 644 file is flagged (text)" || fail "644 flag (text)"
[ "$(printf '%s\n' "$aj" | grep -c '"exposed":true')" = 1 ] && printf '%s\n' "$aj" | grep '"exposed":true' | grep -q '"path":"~/.ssh/id_rsa"' && pass "only the 644 file is flagged (json)" || fail "644 flag (json)"
printf '%s\n' "$aj" | grep '"path":"~/.ssh/id_ed25519"' | grep -q 'NOT passphrase' && pass "unencrypted OpenSSH key noted" || fail "unencrypted OpenSSH key noted"
printf '%s\n' "$aj" | grep '"path":"~/.ssh/id_enc"' | grep -q '"note":"passphrase-protected"' && pass "encrypted PEM key noted" || fail "encrypted PEM key noted"
printf '%s\n' "$aj" | grep '"path":"~/.pypirc"' | grep -q 'not followed' && pass "symlink leading outside ~ not followed" || fail "symlink outside ~"
printf '%s\n' "$aj" | grep '"path":"~/.kube/config"' | grep -q 'over 1MB' && pass "over-1MB file listed but not read" || fail "over-1MB note"
case "$aj" in *deep.env* | *clean.env*) fail "env scan depth/clean filter" ;; *) pass "*.env: only <=3 levels and only key-like files" ;; esac
case "$aj" in *'"path":"env:FAKE_API_TOKEN"'*) ;; *) fail "env var name listed" ;; esac
case "$aj" in *PLAIN_VAR*) fail "harmless env var listed" ;; *) pass "env vars: only secret-like names, never values" ;; esac
case "$az" in *"共 "*) pass "audit zh" ;; *) fail "audit zh" ;; esac
command -v jq >/dev/null 2>&1 && { printf '%s\n' "$aj" | jq -e '.count == (.items|length)' >/dev/null 2>&1 && pass "audit --json is valid JSON" || fail "audit --json is valid JSON"; }
[ "$snap_before" = "$snap_after" ] && pass "audit changed nothing (read-only)" || fail "audit modified files"
CL=$(mktemp -d)
cj=$(env -i HOME="$CL" PATH="$PATH" LANG=C bash "$SRC/bin/aibot" audit --lang en); crc=$?
case "$cj" in *"0 item(s)"*) [ "$crc" = 0 ] && pass "clean account: 0 items, exit 0" || fail "clean account exit $crc" ;; *) fail "clean account should have 0 items" ;; esac
ls -A "$CL" | grep -q . && fail "audit created files in a clean home" || pass "audit created nothing in a clean home"
rm -rf "$F" "$CL" "/tmp/outside_$LABEL"

# ---- 9d. several bots on one computer: ledger + lock (standalone aibot, own throw-away AIBOT_HOME)
SH=$(mktemp -d)
ab() { AIBOT_HOME="$SH/.aibot" bash "$SRC/bin/aibot" "$@"; }
abq() { AIBOT_HOME="$SH/.aibot" bash "$SRC/bin/aibot" "$@" >/dev/null 2>&1; }
ab ledger add "first note" --by tester >/dev/null 2>&1
grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} tester first note$' "$SH/.aibot/shared/LEDGER.md" && pass "ledger add: line format" || fail "ledger add: line format"
AIBOT_BOT_NAME=zed ab ledger add "named by env" >/dev/null 2>&1
grep -q ' zed named by env$' "$SH/.aibot/shared/LEDGER.md" && pass "ledger: default name from AIBOT_BOT_NAME" || fail "ledger: default name"
ab ledger add "$(printf 'bad\atext')" --by C >/dev/null 2>&1
grep -q ' C badtext$' "$SH/.aibot/shared/LEDGER.md" && pass "ledger: control characters stripped" || fail "ledger: control chars"
n0=$(wc -l <"$SH/.aibot/shared/LEDGER.md")
abq ledger add "token ghp_FAKE" && fail "ledger accepted ghp_" || pass "ledger refuses ghp_ secret"
abq ledger add "key sk-FAKE" && fail "ledger accepted sk-" || pass "ledger refuses sk- secret"
abq ledger add "AKIAIOSFODNN7EXAMPLE" && fail "ledger accepted AKIA" || pass "ledger refuses AKIA secret"
abq ledger add "long ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdef" && fail "ledger accepted 32+ char run" || pass "ledger refuses 32+ char key-like run"
abq ledger add "$(printf 'one\ntwo')" && fail "ledger accepted 2 lines" || pass "ledger refuses multi-line"
abq ledger add "$(head -c 600 /dev/zero | tr '\0' 'a' | sed 's/aaaaa/aaa a /g')" && fail "ledger accepted >500 chars" || pass "ledger refuses >500 chars"
[ "$(wc -l <"$SH/.aibot/shared/LEDGER.md")" = "$n0" ] && ! grep -q 'ghp_\|AKIA' "$SH/.aibot/shared/LEDGER.md" && pass "refused lines were not written" || fail "refused lines written"
ab ledger tail 2 | grep -q 'badtext' && pass "ledger tail" || fail "ledger tail"
ab ledger grep ZED | grep -q 'named by env' && pass "ledger grep" || fail "ledger grep"
: >"$SH/.aibot/shared/LEDGER.md"
( for i in $(seq 50); do abq ledger add "a$i" --by A; done ) &
pl1=$!
( for i in $(seq 50); do abq ledger add "b$i" --by B; done ) &
pl2=$!
wait "$pl1" "$pl2"
L="$SH/.aibot/shared/LEDGER.md"
[ "$(wc -l <"$L")" = 100 ] && [ "$(grep -cE ' A a[0-9]+$' "$L")" = 50 ] && [ "$(grep -cE ' B b[0-9]+$' "$L")" = 50 ] && [ -z "$(sort "$L" | uniq -d)" ] && pass "ledger: 2 writers x 50 lines = 100 intact lines" || fail "ledger concurrent writes ($(wc -l <"$L") lines)"
# locks
rm -f "$SH/order"
AIBOT_HOME="$SH/.aibot" bash "$SRC/bin/aibot" lock tl -- bash -c "echo s1 >>$SH/order; sleep 3; echo e1 >>$SH/order" &
pk1=$!
sleep 1
lst=$(ab lock list 2>&1)
case "$lst" in "tl "*) pass "lock list shows the held lock" ;; *) fail "lock list: $lst" ;; esac
AIBOT_HOME="$SH/.aibot" bash "$SRC/bin/aibot" lock tl -- bash -c "echo s2 >>$SH/order" &
pk2=$!
wait "$pk1" "$pk2"
[ "$(tr '\n' ' ' <"$SH/order")" = "s1 e1 s2 " ] && pass "lock: second process waited for the first" || fail "lock order: $(tr '\n' ' ' <"$SH/order")"
AIBOT_HOME="$SH/.aibot" bash "$SRC/bin/aibot" lock tw -- sleep 4 &
pk3=$!
sleep 1
t0=$(date +%s)
wout=$(ab lock tw --wait 1 -- true 2>&1); wrc=$?
t1=$(date +%s)
[ "$wrc" = 75 ] && [ $((t1 - t0)) -le 3 ] && pass "lock --wait 1: exit 75 after ~1s" || fail "lock --wait 1: rc=$wrc after $((t1 - t0))s"
case "$wout" in *"Held by"* | *"拿著"*) pass "lock timeout says who holds it" ;; *) fail "lock timeout message" ;; esac
wait "$pk3"
AIBOT_HOME="$SH/.aibot" bash "$SRC/bin/aibot" lock kl -- sleep 8 &
pk4=$!
sleep 1
kill -9 "$pk4"
wait "$pk4" 2>/dev/null
ab lock kl --wait 3 -- true >/dev/null 2>&1 && pass "lock frees itself when the holder is kill -9'd" || fail "lock stuck after kill -9"
ab lock list 2>&1 | grep -q 'kl ' && fail "lock list shows a dead holder" || pass "lock list ignores dead holders"
ab lock ez -- bash -c 'exit 7' >/dev/null 2>&1
[ "$?" = 7 ] && pass "lock passes the command's exit code through" || fail "lock exit code passthrough"
abq lock '../evil' -- true && fail "lock accepted a bad name" || pass "lock refuses a bad name"
# shared component: folder + reminder block only in OUR rules files, uninstall removes the block
bash "$SRC/install.sh" --lang en --with rules,shared --yes >/tmp/shared_"$LABEL".out 2>&1
bash "$SRC/install.sh" --lang en --with rules,shared --yes >>/tmp/shared_"$LABEL".out 2>&1
ok_if "shared: folders created" test -d "$HOME/.aibot/shared/locks"
[ "$(grep -c 'aibot-hostkit:shared:begin' "$HOME/work/CLAUDE.md")" = 1 ] && pass "shared: reminder block added once to our rules file" || fail "shared: reminder block in CLAUDE.md"
mkdir -p "$SH/own" && printf 'my own rules\n' >"$SH/own/CLAUDE.md"
cp "$SH/own/CLAUDE.md" "$SH/own/CLAUDE.md.orig"
bash "$SRC/install.sh" --lang en --with shared --work "$SH/own" --yes >>/tmp/shared_"$LABEL".out 2>&1
cmp -s "$SH/own/CLAUDE.md" "$SH/own/CLAUDE.md.orig" && pass "shared: a rules file that is not ours is never touched" || fail "shared touched a foreign CLAUDE.md"
bash "$SRC/install.sh" --lang en --with rules,shared --work "$HOME/work" --yes >>/tmp/shared_"$LABEL".out 2>&1
rm -rf "$SH"

# ---- 10. uninstall
if [ "$HAS_SUDO" = 1 ] && [ "$CRON" = 1 ]; then crontab -l 2>/dev/null | grep -q aibot-hostkit && pass "crontab has aibot entries before uninstall" || fail "crontab entries before uninstall"; fi
"$AIBOT" uninstall --yes >/tmp/uninstall_"$LABEL".out 2>&1
[ ! -e "$HOME/.aibot" ] && pass "uninstall: ~/.aibot removed" || fail "uninstall: ~/.aibot removed"
grep -q aibot-hostkit "$HOME/.bashrc" 2>/dev/null && fail "uninstall: .bashrc cleaned" || pass "uninstall: .bashrc cleaned"
crontab -l 2>/dev/null | grep -q aibot-hostkit && fail "uninstall: crontab cleaned" || pass "uninstall: crontab cleaned"
tmux has-session -t aibot 2>/dev/null && fail "uninstall: session removed" || pass "uninstall: session removed"
ok_if "uninstall keeps user files (~/work)" test -d "$HOME/work"
ok_if "uninstall keeps Claude Code binary" test -x "$HOME/.local/bin/claude"
[ "$(grep -c 'aibot-hostkit:shared:begin' "$HOME/work/CLAUDE.md")" = 0 ] && pass "uninstall: shared reminder block removed, file kept" || fail "uninstall: shared block removed"

printf 'DONE [%s] fails=%d elapsed=%ss\n' "$LABEL" "$FAILS" "$(( $(date +%s) - t_start ))"
exit "$FAILS"

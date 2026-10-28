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
case "$out" in *"[tmux]"*"[notify-line]"*"[uninstall]"*) pass "--plan lists components" ;; *) fail "--plan lists components" ;; esac
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
FAKE="1234567890:AAFAKEtokenForTestingOnly_abcdef"
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
  { sleep 8; for a in n n n n n n n n n n y; do printf '%s\n' "$a"; sleep 0.4; done; sleep 2; } |
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

# ---- 10. uninstall
if [ "$HAS_SUDO" = 1 ] && [ "$CRON" = 1 ]; then crontab -l 2>/dev/null | grep -q aibot-hostkit && pass "crontab has aibot entries before uninstall" || fail "crontab entries before uninstall"; fi
"$AIBOT" uninstall --yes >/tmp/uninstall_"$LABEL".out 2>&1
[ ! -e "$HOME/.aibot" ] && pass "uninstall: ~/.aibot removed" || fail "uninstall: ~/.aibot removed"
grep -q aibot-hostkit "$HOME/.bashrc" 2>/dev/null && fail "uninstall: .bashrc cleaned" || pass "uninstall: .bashrc cleaned"
crontab -l 2>/dev/null | grep -q aibot-hostkit && fail "uninstall: crontab cleaned" || pass "uninstall: crontab cleaned"
tmux has-session -t aibot 2>/dev/null && fail "uninstall: session removed" || pass "uninstall: session removed"
ok_if "uninstall keeps user files (~/work)" test -d "$HOME/work"
ok_if "uninstall keeps Claude Code binary" test -x "$HOME/.local/bin/claude"

printf 'DONE [%s] fails=%d elapsed=%ss\n' "$LABEL" "$FAILS" "$(( $(date +%s) - t_start ))"
exit "$FAILS"

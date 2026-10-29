# Changelog

## 0.2.0
- `aibot audit [--json]`: read-only inventory of the logins/keys every bot on the computer can read
  (fixed list of paths, no recursive disk scan, never prints contents, no network).
- `aibot ledger add|tail|grep`: append-only shared notebook, refuses multi-line text and key-like text.
- `aibot lock NAME [--wait SEC] -- command` / `aibot lock list`: flock-based mutual exclusion that frees itself
  when the holder dies; exit 75 when busy, with who holds it.
- New component `shared`: creates `~/.aibot/shared/` and adds a reminder block to the rules file aibot wrote;
  `aibot uninstall` removes the block.
- README: "Several bots, one computer" section (English and Traditional Chinese).

## 0.1.0
- First version: preflight, tmux, claude (official installer), remote (tmux + `claude --remote-control`),
  guard (cron / systemd --user / tmux window fallback, 60 s, rate-limited notifications),
  notify-telegram / ntfy / discord / line, rules template, uninstall.
- `aibot` command: status, start, stop, restart, logs, notify, doctor, tg-chatid, uninstall.
- Non-interactive mode for bots: `--plan`, `--with ... --yes`, `--dry-run`.

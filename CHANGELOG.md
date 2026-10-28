# Changelog

## 0.1.0 (unreleased)
- First version: preflight, tmux, claude (official installer), remote (tmux + `claude --remote-control`),
  guard (cron / systemd --user / tmux window fallback, 60 s, rate-limited notifications),
  notify-telegram / ntfy / discord / line, rules template, uninstall.
- `aibot` command: status, start, stop, restart, logs, notify, doctor, tg-chatid, uninstall.
- Non-interactive mode for bots: `--plan`, `--with ... --yes`, `--dry-run`.

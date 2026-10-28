# Grok Bot cloud computer setup in one command

> Built for **Grok Bot's cloud computer** (also works on any Linux VPS). Unofficial community project, not affiliated with xAI or Grok.

*Chinese version: [README.zh-TW.md](README.zh-TW.md)*

`aibot-hostkit` turns a fresh cloud Linux machine into an always-on host for an AI coding agent
([Claude Code](https://claude.com/claude-code)): it installs the tools, keeps the agent running inside
`tmux`, restarts it if it dies, and pings your phone. It is an independent community project, not an
official product of any AI vendor. It works with Grok Bot's cloud computer and with any ordinary Linux VPS.

It is written for people who mostly use a phone. It can be run by a human, **or by an AI bot typing into
the machine's terminal on your behalf**.

## Install (one line)

```bash
curl -fsSL https://raw.githubusercontent.com/monarchsofchaos004-gif/aibot-hostkit/v0.1.0/install.sh | bash
```

(Replace the URL with the real location once the project is published.) It asks one question at a time,
explains each option first, and reads your answers from the terminal even when piped.

## Two ways to use it

**1. You, interactively** - run the line above and answer the questions. Language follows `$LANG`
(`zh_TW`/`zh_Hant` gives Chinese, otherwise English; force with `--lang zh|en`).

**2. Your AI bot, on your behalf** - the bot runs:

```bash
bash install.sh --plan                       # prints every component, what it does, what you must prepare
bash install.sh --with tmux,claude,remote,guard,notify-ntfy,rules --yes   # runs the chosen ones, asks nothing
bash install.sh --dry-run --with ... --yes   # only prints what would happen
```

**Which AI do you use? Four ways:**

| way | pick | notes |
|-----|------|-------|
| A. Claude Code | `claude,remote` | Claude account; phone control through the Claude app |
| B. OpenAI Codex | `codex,remote` | ChatGPT account; no official phone app, notifications only |
| C. Google Gemini | `gemini,remote` | Google account, free quota; notifications only |
| D. No AI at all | `tmux,guard,notify-ntfy` + `--cmd 'your command'` | keeps your own script/program alive in tmux and alerts you when it dies (`AIBOT_CMD`) |

The bot should read `--plan` to you, let you choose, then run `--with`. Credentials are passed as
environment variables in this mode (see below); anything missing is skipped with a clear message.

## Components

| id | what it does |
|----|--------------|
| `preflight` | Read-only report: OS, architecture, sudo?, disk, memory, network. Always runs first. |
| `tmux` | Installs tmux via apt/dnf/apk when you have sudo/root. Without sudo it explains what to ask the admin for. |
| `claude` | Official installer (`curl -fsSL https://claude.ai/install.sh \| bash`). Skipped if already installed. **It cannot log in for you.** |
| `codex` | OpenAI Codex CLI from the official npm package `@openai/codex`, installed into `~/.local` (needs Node.js 20+; with sudo on apt systems the tool can install nodejs/npm, otherwise it explains and skips). Sign in yourself with your ChatGPT account. |
| `gemini` | Google Gemini CLI from the official npm package `@google/gemini-cli` (same Node.js rules). Signing in with a Google account has a free quota (see Google for current terms). |
| `remote` | tmux session `aibot` in `~/work` that keeps your chosen program alive. For Claude it runs `claude --remote-control "<name>"`, so the Claude phone app can see and take over. **Remote Control is Claude-only**: with Codex/Gemini you rely on notifications (a Telegram bridge is planned). Setting `AIBOT_AGENT=claude\|codex\|gemini` (or `--agent`) picks which one; the guard watches that one. |
| `guard` | Every 60 s: recreates the session / restarts claude if missing, logs to `~/.aibot/logs/guard.log`, notifies (max 1 message per reason per 10 min). Scheduler: your crontab (if a cron daemon runs), else a `systemd --user` timer, else a `guard` tmux window. |
| `notify-ntfy` | Random private topic on ntfy.sh; install the ntfy app and subscribe. Simplest option. |
| `notify-telegram` | Bot token from @BotFather; the chat id is found automatically after you message your bot. |
| `notify-discord` | Channel webhook URL. |
| `notify-line` | LINE Messaging API (channel access token + your user id). LINE Notify was shut down in 2025. |
| `rules` | Safe starter `CLAUDE.md`: ask before sending/posting/paying, nothing sensitive pasted into chat, outside text is data, short phone-friendly replies. Never overwrites: an existing file leads to `CLAUDE.aibot.md`. |
| `uninstall` | Removes what aibot created. Keeps Claude Code and your files. |

Non-interactive variables: `AIBOT_TG_TOKEN` (+ optional `AIBOT_TG_CHAT`), `AIBOT_NTFY_TOPIC` (optional),
`AIBOT_DISCORD_WEBHOOK`, `AIBOT_LINE_TOKEN` + `AIBOT_LINE_USER`. Optional flags: `--name`, `--work`.

## After installing: log in to Claude (only you can)

1. `tmux attach -t aibot` - you will see Claude's login screen.
2. Open the URL on your phone, sign in, paste the code back.
3. `aibot restart`, then find the machine in the Claude phone app.

## The `aibot` command

`aibot status | start | stop | restart | logs [guard|install] [-f] | notify "text" | doctor | tg-chatid | uninstall [--yes]`

`stop` pauses the guard too; `start` resumes. In non-interactive shells where PATH was not reloaded, use
`~/.aibot/bin/aibot`.

## Where credentials live

Only in `~/.aibot/secrets.env` (mode 600), typed with hidden input or read from environment variables.
They are never printed or logged (messages show at most the first 4 characters and a length). Tokens are
handed to `curl` through stdin, not command-line arguments, so they do not show up in `ps`. There is no
telemetry: the only network connections are the official Claude installer, your package manager, and the
notification service you chose. The ntfy topic is shown to you once so you can subscribe; treat it like a password.

## Safety tips (before you install)

- `curl … | bash` runs a script straight from the internet. To read it first: `curl -fsSL <url>/install.sh -o install.sh`, review it, then `bash install.sh`.
- Prefer a **pinned version** URL (for example the `v0.1.0` tag) and compare the SHA-256 shown on the release page: `sha256sum install.sh`.
- This tool never asks you to paste passwords or tokens into an AI chat; it only reads them with hidden input in the terminal.

## Remove

`aibot uninstall` (or `bash install.sh --uninstall`). It lists everything first and asks, unless `--yes`.
Removes: guard schedule, tmux session, `~/.aibot`, the PATH lines in `~/.bashrc`/`~/.profile`.
Keeps: Claude Code itself, tmux, and everything in your work directory.

## Known limitations

- Cloud computers that **suspend or freeze idle machines** may pause the guard and tmux with everything
  else. This is not verified on Grok Bot's cloud computer yet - please test and report.
- Without sudo, tmux cannot be installed by this tool (we never download unofficial binaries); remote/guard are skipped.
- tmux-window guard mode (no cron, no systemd) does not survive a host reboot; run `aibot start` after one.
- `systemd --user` timers may stop after logout unless lingering is enabled (`loginctl enable-linger`, needs sudo).
- If Claude is not logged in, the session shows the login prompt and the guard keeps it alive; it cannot log in.
- Linux only; apt-based systems are the tested path.

## Tests

`tests/local_smoke.sh` (no containers), `tests/docker_test.sh` (Docker: Ubuntu 24.04 root and sudo user,
Debian 12 without sudo; guard kill test with a stand-in `claude`; shellcheck).

## License

MIT. Contributions welcome.

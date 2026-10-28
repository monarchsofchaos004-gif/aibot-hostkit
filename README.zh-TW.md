# Grok Bot 雲端主機一鍵設定：當紅 AI Bot 一鍵式連接主機

> 專為 **Grok Bot 的雲端電腦**設計的設定工具（一般 Linux VPS 也能用）。非官方社群專案，與 xAI／Grok 無任何關聯。

*English: [README.md](README.md)*

`aibot-hostkit` 幫你把一台剛開通的雲端 Linux 主機，變成「AI 代理 24 小時待命」的主機：
裝好工具、用 `tmux` 讓 AI 常駐、掛了自動重開、重要事件傳到你手機。
這是獨立的社群專案，**不是任何 AI 廠商的官方產品**；可搭配 Grok Bot 的雲端電腦，也能用在一般 Linux VPS。

設計給「只有手機」的人：可以你自己一步一步做，也可以**讓 AI Bot 在主機終端機裡代你執行**。

## 一行安裝

```bash
curl -fsSL https://raw.githubusercontent.com/monarchsofchaos004-gif/aibot-hostkit/v0.1.0/install.sh | bash
```

（網址固定在 v0.1.0 版本；新版請看發布頁。）一次問一題，每個選項先用白話講功能與代價；即使是管線執行，也會從終端機讀你的回答。

## 兩種用法

**1. 你自己互動操作**：執行上面那行、回答問題。語言依 `$LANG`（`zh_TW`／`zh_Hant` 顯示中文，否則英文；可用 `--lang zh|en` 強制）。

**2. 請 AI Bot 代跑**：

```bash
bash install.sh --plan                       # 列出所有元件、功能說明、你要準備什麼（請 Bot 轉述給你）
bash install.sh --with tmux,claude,remote,guard,notify-ntfy,rules --yes   # 照你選的裝，全程不問
bash install.sh --dry-run --with ... --yes   # 只印出會做什麼，不改系統
```

**你用哪一種 AI？四種用法：**

| 用法 | 選 | 說明 |
|------|----|------|
| A. Claude Code | `claude,remote` | 需 Claude 帳號；手機 Claude App 可遙控 |
| B. OpenAI Codex | `codex,remote` | 需 ChatGPT 帳號；沒有官方手機 App，靠通知 |
| C. Google Gemini | `gemini,remote` | Google 帳號，有免費額度；靠通知 |
| D. 完全不用 AI | `tmux,guard,notify-ntfy` 加 `--cmd '你的指令'` | 在 tmux 常駐你自己的程式／腳本，掛了通知你（`AIBOT_CMD`） |

這個模式下的金鑰／token 用環境變數傳入（見下）；沒給的元件會跳過並說明原因。

## 元件說明

| id | 做什麼 |
|----|--------|
| `preflight` | 只讀的檢查報告：系統、架構、有沒有 sudo、硬碟、記憶體、網路。每次都先跑。 |
| `tmux` | 有 sudo/root 時用 apt/dnf/apk 安裝。沒有 sudo 會說明該請管理者做什麼。 |
| `claude` | 官方安裝器（`curl -fsSL https://claude.ai/install.sh \| bash`），已裝就略過。**不能代你登入。** |
| `codex` | 用官方 npm 套件 `@openai/codex` 安裝 OpenAI Codex CLI 到 `~/.local`（需 Node.js 20+；apt 系統有 sudo 時可代裝 nodejs/npm，否則說明後略過）。用 ChatGPT 帳號自己登入。 |
| `gemini` | 用官方 npm 套件 `@google/gemini-cli` 安裝 Google Gemini CLI（Node.js 規則同上）。用 Google 帳號登入有免費額度（以官方為準）。 |
| `remote` | 在 `~/work` 開 tmux 工作階段 `aibot`，讓你選的程式一直開著。Claude 會執行 `claude --remote-control "<名稱>"`，手機開 Claude App 就能看到並接手。**手機遙控目前只有 Claude 有官方 App**；用 Codex／Gemini 靠通知（之後會做 Telegram 橋接）。用 `AIBOT_AGENT=claude\|codex\|gemini`（或 `--agent`）指定，看守也盯那一個。 |
| `guard` | 看守，每 60 秒檢查：工作階段或 claude 不在就重開，寫 `~/.aibot/logs/guard.log`，並通知你（同一原因 10 分鐘最多 1 則）。排程優先順序：使用者 crontab（需 cron 有在跑）→ `systemd --user` → tmux 的 guard 視窗。 |
| `notify-ntfy` | 在 ntfy.sh 產生隨機私人主題；手機裝 ntfy App 訂閱即可。最簡單。 |
| `notify-telegram` | 用 @BotFather 建的 bot token；你先傳訊息給 bot，工具會自動抓 chat id。 |
| `notify-discord` | 頻道的 webhook 網址。 |
| `notify-line` | LINE Messaging API（channel access token＋你的 user id）。LINE Notify 已於 2025 年停止服務。 |
| `rules` | 放一份安全版 `CLAUDE.md`：對外動作（寄信、發文、付款）先問你、敏感資料不貼進對話、網頁/信件文字只當資料、手機閱讀用短句。已存在不會覆蓋，會改寫到 `CLAUDE.aibot.md`。 |
| `uninstall` | 移除 aibot 建立的東西；保留 Claude Code 與你的檔案。 |

非互動模式的環境變數：`AIBOT_TG_TOKEN`（可加 `AIBOT_TG_CHAT`）、`AIBOT_NTFY_TOPIC`（可省略）、`AIBOT_DISCORD_WEBHOOK`、`AIBOT_LINE_TOKEN`＋`AIBOT_LINE_USER`。另有 `--name`、`--work`。

## 裝完後：登入 Claude（只有你本人能做）

1. `tmux attach -t aibot`，會看到 Claude 的登入畫面。
2. 用手機打開畫面上的網址、登入、把代碼貼回來。
3. 執行 `aibot restart`，再到手機的 Claude App 找這台主機。

## `aibot` 指令

`aibot status | start | stop | restart | logs [guard|install] [-f] | notify "訊息" | doctor | tg-chatid | uninstall [--yes]`

`stop` 會連看守一起暫停，`start` 恢復。若新開的非互動 shell 找不到 `aibot`，用完整路徑 `~/.aibot/bin/aibot`。

## 金鑰存在哪

只存在 `~/.aibot/secrets.env`（權限 600），用隱藏輸入或環境變數取得；**絕不印出、不寫進 log**（最多顯示前 4 碼與長度）。
token 以標準輸入交給 `curl`，不放在命令列參數，所以 `ps` 看不到。**零遙測**：只連官方 Claude 安裝來源、套件管理員，以及你選的通知服務。
ntfy 主題名會讓你看到一次以便訂閱，請當成密碼保管。

## 安全建議（裝之前）

- `curl … | bash` 等於直接執行網路上的程式。想先看內容：先下載 `curl -fsSL <網址>/install.sh -o install.sh`，看過再 `bash install.sh`。
- 建議用**固定版本**的網址（例如 `v0.1.0` 標籤），並比對發布頁上的 SHA-256：`sha256sum install.sh`。
- 本工具不會要你把密碼、token 貼進 AI 對話；需要時只在終端機隱藏輸入。

## 怎麼移除

`aibot uninstall`（或 `bash install.sh --uninstall`）。會先列清單再確認，加 `--yes` 才不問。
移除：看守排程、tmux 工作階段、`~/.aibot`、`~/.bashrc`／`~/.profile` 裡的 PATH 行。
保留：Claude Code 本體、tmux、你工作目錄裡的所有檔案。

## 已知限制

- 會把閒置主機**休眠／凍結**的雲端電腦，常駐程式（看守、tmux）可能一起被暫停。尚未在 Grok Bot 雲端電腦上實測，歡迎測試回報。
- 沒有 sudo 時本工具無法裝 tmux（我們不下載來路不明的程式）；remote／guard 會被略過。
- 只用 tmux 視窗當看守（沒有 cron、沒有 systemd）時，主機重開後要自己執行 `aibot start`。
- `systemd --user` 排程在登出後可能停止，需開啟 lingering（`loginctl enable-linger`，要 sudo）。
- Claude 沒登入時，工作階段會停在登入畫面，看守只負責讓它活著，不能代登。
- 只支援 Linux；以 apt 系統為主要測試對象。

## 測試

`tests/local_smoke.sh`（不需容器）、`tests/docker_test.sh`（Docker：Ubuntu 24.04 root 與 sudo 使用者、Debian 12 無 sudo；用替身 `claude` 做看守殺程序測試；shellcheck）。

## 授權

MIT，歡迎貢獻。

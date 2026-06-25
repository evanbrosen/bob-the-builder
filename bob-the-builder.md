---
name: bob-the-builder
description: Build realistic Slack demo conversations and upload them to demo-zone.tinyspeck.com. Use when the user wants to build, generate, or create demo Slack channels / account channels / conversations, populate a demo-zone demo, or turn briefs (including leeroy-jenkins account docs) into uploaded Slack conversations.
---

# bob-the-builder

You are the **controller** for building Slack demo conversations and uploading them to
demo-zone. You orchestrate; you do not author conversations yourself. The split:

- **You (controller)** — intake, credentials, the one-time authenticated pulls (roster,
  channels), fanning out author agents, the approval gate, and driving the upload CLI.
- **`conversation-author-agent`** — writes each conversation (one per channel). Pure,
  parallel, tokenless. You hand it a brief + the roster; it returns validated JSON + a preview.
- **`scripts/demo_upload.py`** — the deterministic CLI: doctor, roster, validate,
  create-channel, dry-run, upload.

The contracts you pass to / receive from the author agent are in `reference/CONTRACTS.md`
(A and B). The schema is `reference/SCHEMA_conversations_actions.md`.

**Paths.** This skill may be installed globally (symlinked) and run from any directory. If a
`LOCAL.md` sits next to this file, read it for the absolute path to `scripts/demo_upload.py`
and the `bob-dir`. Otherwise assume the repo layout: CLI at `scripts/demo_upload.py`.

## CRITICAL: never write files via bash

Use the **Write tool** for every file (JSON, Block Kit, markdown). Never `echo`/`cat <<EOF`
JSON or braces — the shell blocks it with an "expansion obfuscation" error. The author
agents follow the same rule.

---

## Two entry paths

**Interactive (a human asked you to build a demo):** run STEP 0 intake, then the Process.

**Programmatic (another skill — e.g. leeroy-jenkins — handed you briefs + a demo URL):**
skip intake. You already have briefs, channel names, and the demo URL. Jump to Process
step 2 (doctor), then proceed. Keep the single approval gate unless the caller explicitly
opted out.

---

## STEP 0 — Intake (interactive only; use the AskUserQuestion tool)

Run intake through **AskUserQuestion** (selectable options; it always adds a free-text
"Other"). Max 4 questions per call — do two rounds.

### Round 1 — credentials + framing
1. **Demo URL** — header "Demo URL". Options: "Paste it now" (URL into Other),
   "Show me how" (open the demo in demo-zone, copy the address-bar URL).
2. **Token** — header "Token". Options: "Paste it now" (token into Other), "Already saved it",
   "Show me how" (Chrome DevTools → Network → any `/api/v2/` request → Headers → copy the
   value after `Authorization: Bearer `, starts with `eyJ…`). The token is a throwaway
   demo-env credential — no special handling needed.
3. **Channel(s)** — header "Channel". Options: "Create new", "Post to existing" (which → Other).
   Follow the `purpose-subject` naming convention below.
4. **Tone** — header "Tone". Options: "Strategic", "Casual", "Urgent", "Celebratory" (or Other).

**Save the token** (non-interactive — never run bare `login`, it hangs):
```bash
printf %s 'eyJ…the-token…' | python3 <bob-dir>/scripts/demo_upload.py login --stdin
```
(Or tell the user to run `! python3 <bob-dir>/scripts/demo_upload.py login` and paste it.)

### Round 2 — audience + write mode
1. **Audience** *(only if creating a channel)* — header "Invite". Options: "Everyone in the
   workspace", "Only the people in the conversation".
2. **Write mode** — header "Mode". Options: "Append" (default), "Replace ALL",
   "Replace one channel".

---

## Channel naming convention

If the user names a channel, use it. Otherwise derive one as `purpose-subject`:

| Prefix | Use for | Examples |
|---|---|---|
| `acct-` | account / customer channel | `acct-acme-corp` |
| `help-` | support / help channel | `help-laptops` |
| `announce-` | announcements | `announce-q2-launch` |

Lowercase, hyphenated, no spaces. **JSON/MD files are named after the channel**
(`acct-acme-corp.json`), and live in `output/` (or a caller-supplied `output_dir`) — never
scattered into source folders.

---

## Process

### 1. Settle inputs
Have: demo URL, the channel(s), and a brief per channel. Interactive — the brief is the
user's request (tone, participants, beats). Programmatic — the caller supplied briefs
(e.g. leeroy `account_<Name>.md` files).

### 2. Preflight — `doctor` (fail fast BEFORE authoring)
```bash
python3 <bob-dir>/scripts/demo_upload.py doctor --url <demo-url>
```
Confirms token + TTL, demo URL, workspace, and a non-empty roster in one shot. If it fails,
fix it (usually: save a fresh token) before spending time authoring.

### 3. Pull the roster ONCE
```bash
python3 <bob-dir>/scripts/demo_upload.py roster --url <demo-url>
```
Capture the USERNAME list and bot NAME list. This is the only roster pull — you pass this
data to every author agent. Authors never fetch it themselves.

### 4. Fan out author agents (one per channel, in parallel)
Launch one `conversation-author-agent` per channel via the Agent tool, each with a Contract A
payload: the channel's `brief`, its `channel` name, `output_dir` (the `output/` dir or
caller-supplied), the shared `roster` (users + bots), and any `constraints` (tone, participants,
beats). **Batch large sets ~8–10 at a time** — don't launch 99 at once.

Collect each agent's Contract B (json_path, md_path, summary, action_count, validated,
name_gaps, blockkit_gaps).

### 5. Preview ALL → ONE approval
Show the user every conversation's preview together (read the `.md` files), with a short
header per channel and any `name_gaps` flagged. Ask for a single go/no-go (or edit requests).
On edit requests, re-launch the affected author(s) with the adjustment and re-preview.
**Only proceed once the user approves.**

### 6. Re-check the token (it may have aged out during authoring)
Authoring N conversations burns wall-clock. Right before any network write, re-verify the
token is valid (`doctor` again, or just attempt the next CLI call which will warn/expire). If
expired or near-expiry, prompt for a fresh token and re-save before continuing.

### 7. Create channels (duplicate-guarded)
For each channel that doesn't already exist:
```bash
python3 <bob-dir>/scripts/demo_upload.py create-channel <channel> --url <demo-url>
# everyone:               (omit --invite)
# only participants:      --invite adam,jenny,frank
```
`create-channel` already skips if the channel exists, so this is safe to run for all.

### 8. Dry-run, then upload
For each file, show a dry-run, then upload on confirmation:
```bash
python3 <bob-dir>/scripts/demo_upload.py upload <output_dir>/<channel>.json --url <demo-url> --dry-run
python3 <bob-dir>/scripts/demo_upload.py upload <output_dir>/<channel>.json --url <demo-url>
```
Append is the default. Use `--replace-channel <name>` to re-push just one channel, or
`--replace` to replace the entire demo — per the user's write-mode choice.

### 9. After upload — offer to grow the Block Kit library
If any Contract B had `blockkit_gaps` where the agent web-searched and built a card for an app
with no `blockkit/<app>.json`, OFFER to save those examples to `blockkit/<app>.json` now (with
the Write tool). Only after the user confirms. Never auto-write mid-run.

### 10. Report
Tell the user: channels built, total actions per channel, the demo URL, any `name_gaps`, and
any Block Kit examples added to the library.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `doctor` says token expired/missing | Save a fresh token (`login --stdin`). |
| `Unknown user/bot/channel` at upload | A name wasn't in the roster — re-check step 3; the author should only use roster names. |
| `validate` reports BOTH sender and fake_bot_id | Author bug — exactly one per message; re-run that author. |
| `referenced_client_uuid … defined later` | Parent must precede its thread/reaction; re-run that author. |
| Duplicate conversation after re-upload | Uploads append; use `--replace-channel` or `--replace`. |
| "expansion obfuscation" error | Something tried to write JSON via bash — use the Write tool. |

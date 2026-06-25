# bob-the-builder — Integration Contracts

This is the stable, public boundary between **producers** (anything that wants a Slack
demo conversation built — a human via the controller, or another skill like
**leeroy-jenkins**) and bob's two executors. Read this if you want to drive bob
programmatically without reading the controller skill.

There are two pieces you can call independently:

1. **`conversation-author-agent`** — a pure function: brief + roster → validated JSON + preview.
2. **`scripts/demo_upload.py`** — a deterministic CLI: validate · create-channel · dry-run · upload.

---

## Contract A — into `conversation-author-agent`

Launch the agent (via the Agent tool) with a single JSON payload:

```json
{
  "brief":       "Free text OR a structured doc. A leeroy account_<Name>.md works as-is.",
  "channel":     "acct-acme-corp",
  "output_dir":  "/abs/path/where/files/are/written",
  "roster":      {
    "users": ["adam", "jenny", "frank"],
    "bots":  ["Service Cloud for Slack", "Salesforce", "DocuSign"]
  },
  "constraints": {
    "tone":           "strategic | casual | urgent | celebratory",
    "participants":   ["adam", "jenny"],
    "must_hit_beats": ["legal blocker raised", "timeline pressure for Q2 close"],
    "length":         "short | medium | long"
  }
}
```

### Rules the agent follows (and callers can rely on)

- **The agent is a PURE FUNCTION. It never touches the network or a token.** The caller
  (controller) supplies `roster` — the agent does NOT fetch it. This keeps authors
  parallel-safe, tokenless, and side-effect-free.
- **`roster` is REQUIRED.** Names in the output come ONLY from this roster. The agent
  never invents a username or bot name. If the brief references someone not in the
  roster, the agent picks the closest real name or flags it in Contract B (`name_gaps`).
- **`brief` is format-agnostic.** A one-liner or a full structured account doc both work;
  the agent infers tone, beats, and participants from whatever it is given, and only asks
  the caller back if something critical is missing.
- **Channel-prefixed `client_uuid`s (load-bearing).** Every `client_uuid` the agent emits
  carries a short prefix derived from the channel (e.g. `acct-genentech` → `ge-1`, `ge-3t1`).
  This guarantees uniqueness when several authors' outputs are merged into ONE upload — two
  authors emitting `msg-1` would otherwise collide and silently mis-thread.
- **Block Kit only for bots that exist.** Before authoring a rich app card, the agent
  confirms that app's bot is in `roster.bots`. If present, it uses `blockkit/<app>.json`
  (or web-searches the app's real card layout and builds one if no file exists). If the bot
  is absent, it falls back to a plain message and records the gap in Contract B.
- **Self-validation before returning.** The agent runs `demo_upload.py validate` on its own
  output in a fix→re-validate loop until clean. `validated: true` therefore means the JSON
  actually passed local schema validation, not that the agent assumed so.
- **All files written with the Write tool — never via bash.** JSON and Block Kit contain
  braces+quotes that trip the shell's "expansion obfuscation" guard.

---

## Contract B — back from `conversation-author-agent`

The agent's final message is a single JSON object:

```json
{
  "channel":       "acct-acme-corp",
  "json_path":     "<output_dir>/acct-acme-corp.json",
  "md_path":       "<output_dir>/acct-acme-corp.md",
  "summary":       "One paragraph describing the conversation arc.",
  "participants":  ["adam", "jenny", "Service Cloud for Slack"],
  "action_count":  7,
  "validated":     true,
  "name_gaps":     [],
  "blockkit_gaps": [
    { "app": "ServiceNow", "resolution": "web-searched + built, offer to save after upload" }
  ]
}
```

- `json_path` is a schema-valid demo file ready for `demo_upload.py upload`.
- `name_gaps` lists brief-named participants not found in the roster (and what was used instead).
- `blockkit_gaps` lists apps that had no `blockkit/<app>.json` and how the agent handled them —
  the controller uses this to OFFER saving new examples to the library AFTER upload.

---

## Contract C — the upload CLI (`scripts/demo_upload.py`)

The deterministic half. Names (usernames, bot names, channel names) are resolved to IDs by
the CLI — callers never deal in UUIDs.

```bash
# Preflight everything before spending authoring time (token+TTL, URL, workspace, roster):
python3 scripts/demo_upload.py doctor --url <demo-url>

# Pull the roster to feed Contract A:
python3 scripts/demo_upload.py roster --url <demo-url>

# Validate a generated file (no network):
python3 scripts/demo_upload.py validate <output_dir>/acct-acme-corp.json

# Create the channel if missing (duplicate-guarded — safe to re-run):
python3 scripts/demo_upload.py create-channel acct-acme-corp --url <demo-url>
python3 scripts/demo_upload.py create-channel acct-acme-corp --url <demo-url> --invite adam,jenny

# Preview the exact payload, then upload (append is the default):
python3 scripts/demo_upload.py upload <file> --url <demo-url> --dry-run
python3 scripts/demo_upload.py upload <file> --url <demo-url>

# Re-push a single channel without disturbing the rest of the demo:
python3 scripts/demo_upload.py upload <file> --url <demo-url> --replace-channel acct-acme-corp

# Replace the ENTIRE demo's actions:
python3 scripts/demo_upload.py upload <file> --url <demo-url> --replace
```

---

## The leeroy-jenkins handoff (worked example)

leeroy finishes a run with `customers/<slug>/account_<Name>.md` briefs (one per account) and
a target demo-zone workspace. To turn those into account channels:

1. `doctor --url <demo-url>` — confirm the token/workspace are good before authoring.
2. `roster --url <demo-url>` — pull users + bots once.
3. For each `account_<Name>.md`: launch a `conversation-author-agent` (Contract A) with that
   file as `brief`, `channel = acct-<account-slug>`, and the shared roster. Run them in
   parallel (batch ~8–10 at a time for large sets).
4. Collect Contract B from each; preview all conversations together; one approval.
5. `create-channel` for each (duplicate-guarded), then `upload` each file.

No edits to leeroy are required — it already emits exactly the brief these agents consume.

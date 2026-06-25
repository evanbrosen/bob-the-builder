# Worked example: brief → conversation

Shows what a `conversation-author-agent` turns a brief into. Demonstrates the three things
that are easy to get wrong: **channel-prefixed `client_uuid`s**, **roster-only names**, and
**Block Kit serialized into `text`**.

## Input (Contract A)

```json
{
  "brief": "Acme Corp renewal is at risk. Service Cloud opens a high-priority case about a chiller fault. Jenny triages, Frank raises the timeline pressure for Q2 close. Wrap with next steps.",
  "channel": "acct-acme-corp",
  "output_dir": "./output",
  "roster": {
    "users": ["adam", "jenny", "frank"],
    "bots": ["Service Cloud for Slack", "DocuSign"]
  },
  "constraints": { "tone": "urgent", "participants": ["jenny", "frank"], "length": "short" }
}
```

## Output JSON (`output/acct-acme-corp.json`)

Note the `ac-` prefix on every `client_uuid` (derived from `acct-acme-corp`), and the first
message is a Block Kit card serialized into `text` because **Service Cloud for Slack is in the
roster**.

```json
{
  "name": "Acme Corp Account",
  "conversations_actions": [
    {
      "type": "Message", "channel": "acct-acme-corp", "client_uuid": "ac-1",
      "fake_bot_id": "Service Cloud for Slack",
      "text": "{\"blocks\":[{\"type\":\"header\",\"text\":{\"type\":\"plain_text\",\"text\":\"🆕 New Case Opened\",\"emoji\":true}},{\"type\":\"section\",\"fields\":[{\"type\":\"mrkdwn\",\"text\":\"*Case:*\\n00012345\"},{\"type\":\"mrkdwn\",\"text\":\"*Priority:*\\nHigh\"},{\"type\":\"mrkdwn\",\"text\":\"*Account:*\\nAcme Corp\"},{\"type\":\"mrkdwn\",\"text\":\"*Subject:*\\nChiller unit reporting fault code E-204\"}]},{\"type\":\"context\",\"elements\":[{\"type\":\"mrkdwn\",\"text\":\"Opened via Email · SLA first response due in 1h\"}]}]}",
      "delay": 0
    },
    {
      "type": "Message", "channel": "acct-acme-corp", "client_uuid": "ac-2",
      "sender": "jenny",
      "text": "On it — pulling the asset history now. This account's renewal is up in 30 days, so let's move fast.",
      "delay": 0
    },
    {
      "type": "Message", "channel": "acct-acme-corp", "client_uuid": "ac-3",
      "sender": "frank",
      "text": "We *cannot* let this slip — Acme is a Q2 close. Keep me posted hourly.",
      "delay": 0
    },
    {
      "type": "Bulk Reaction", "channel": "acct-acme-corp",
      "referenced_client_uuid": "ac-3", "reaction_emoji": "fire", "reaction_count": 3,
      "delay": 0
    },
    {
      "type": "Thread", "channel": "acct-acme-corp", "client_uuid": "ac-3t1",
      "sender": "jenny", "referenced_client_uuid": "ac-3",
      "text": "Understood. First update in 30 min.",
      "delay": 0
    },
    {
      "type": "Message", "channel": "acct-acme-corp", "client_uuid": "ac-4",
      "fake_bot_id": "Service Cloud for Slack",
      "text": "Next steps: field tech dispatched, ETA 2h. Case 00012345 set to *In Progress*.",
      "delay": 0
    }
  ]
}
```

## Output preview (`output/acct-acme-corp.md`)

```markdown
# Demo: Acme Corp Account

### Channel: #acct-acme-corp

**[ac-1]** Service Cloud for Slack (bot)
> 🆕 *New Case Opened* — Case 00012345 · High · Acme Corp · "Chiller unit reporting fault code E-204"

**[ac-2]** Jenny
> On it — pulling the asset history now. This account's renewal is up in 30 days, so let's move fast.

**[ac-3]** Frank
> We *cannot* let this slip — Acme is a Q2 close. Keep me posted hourly.

  **[reaction]** 3× 🔥 (on ac-3)

  **[ac-3t1]** Jenny (reply to ac-3)
  > Understood. First update in 30 min.

**[ac-4]** Service Cloud for Slack (bot)
> Next steps: field tech dispatched, ETA 2h. Case 00012345 set to *In Progress*.

---
**Total actions:** 6 · **Participants:** Jenny, Frank, Service Cloud for Slack (bot)
```

## Return (Contract B)

```json
{
  "channel": "acct-acme-corp",
  "json_path": "./output/acct-acme-corp.json",
  "md_path": "./output/acct-acme-corp.md",
  "summary": "Service Cloud opens a high-priority chiller-fault case on an at-risk Acme renewal; Jenny triages under Q2-close timeline pressure from Frank; wraps with a field tech dispatched.",
  "participants": ["jenny", "frank", "Service Cloud for Slack"],
  "action_count": 6,
  "validated": true,
  "name_gaps": [],
  "blockkit_gaps": []
}
```

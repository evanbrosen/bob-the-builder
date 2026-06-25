# bob-the-builder

Generate realistic Slack demo conversations from plain-English briefs and upload them to
[demo-zone.tinyspeck.com](https://demo-zone.tinyspeck.com) — built to be driven by a human
*or* by another skill (like [leeroy-jenkins](../leeroy-jenkins)) for a one-shot
"nothing → fully built account channels" flow.

## Architecture — control vs. execute

Three decoupled pieces (mirrors leeroy-jenkins's controller + executor pattern):

| Piece | File | Role |
|---|---|---|
| **Controller** | `bob-the-builder.md` | Intake, credentials, the one-time roster pull, fan-out, the approval gate, driving the upload. Human-facing; skippable for programmatic callers. |
| **Author (executor)** | `agents/conversation-author-agent.md` | Pure function: brief + roster → one validated conversation (JSON + preview). Parallel, tokenless, owns all schema knowledge. |
| **Upload (executor)** | `scripts/demo_upload.py` | Deterministic CLI: doctor · roster · validate · create-channel · dry-run · upload. |

The boundary between them is a **natural-language brief** — see `reference/CONTRACTS.md`.
Because authoring is a separable, reusable agent, any producer can hand bob a brief and get
back an uploadable conversation. Authors are pure and tokenless, so N of them run in parallel.

## Setup

```bash
git clone <repo> bob-the-builder
cd bob-the-builder
./install.sh          # symlinks skill + agent, writes LOCAL.md, offers a scoped allowlist
python3 scripts/demo_upload.py login    # paste a token (throwaway demo-env credential)
```

## Use it

> "Build an account channel for Acme Corp — strategic tone, Adam/Jenny/Frank, reference an
> upcoming opportunity and a legal blocker, and have Service Cloud post the case."

The controller walks a short multiple-choice intake (demo URL, token, channel, tone, audience,
write mode), runs a `doctor` preflight, pulls the roster once, fans out an author agent per
channel, **previews everything for one approval**, then creates channels and uploads.

### From leeroy-jenkins
After a leeroy run produces `customers/<slug>/account_<Name>.md` briefs, point bob at them:
hand each file to a `conversation-author-agent` as the `brief`, share one roster, preview all,
upload. No leeroy edits needed — see the worked example in `reference/CONTRACTS.md`.

## Key behaviors

- **Schema source of truth:** `reference/SCHEMA_conversations_actions.md` (the demo-zone API
  owners' doc). The CLI validator and the author agent both follow it.
- **Block Kit cards** are JSON-serialized into an action's `text` (the schema has no `blocks`
  field). Per-app examples live in `blockkit/<app>.json`; the library self-grows (the author
  web-searches unknown apps and offers to save new examples after upload).
- **Append by default.** Re-push one channel with `--replace-channel`, or the whole demo with
  `--replace`. `create-channel` is duplicate-guarded.
- **Generated files** go to `output/` (gitignored) or a caller-supplied dir — never scattered
  into source.
- **Never writes JSON via bash** (avoids the shell's "expansion obfuscation" block) — all files
  via the editor tool.

## Layout

```
bob-the-builder/
├── bob-the-builder.md                  # controller skill
├── agents/conversation-author-agent.md # author executor
├── scripts/demo_upload.py              # upload executor (CLI)
├── reference/
│   ├── SCHEMA_conversations_actions.md # demo-zone schema (source of truth)
│   └── CONTRACTS.md                    # integration contracts A/B/C
├── blockkit/                           # per-app Block Kit examples
├── examples/                           # a valid demo + preview + a worked brief
├── output/                             # generated files land here (gitignored)
└── install.sh
```

# bob-the-builder — Build Plan

> Status: **PLAN — awaiting approval.** Nothing is built or deleted until this is signed off.
> Created 2026-06-24. Supersedes the old `demo-zone-builder` and `demo-builder` folders.

## 1. Why this rebuild exists

The old `demo-zone-builder` skill fused three concerns into one linear, human-only
narrative: intake, conversation authoring, and upload. Because authoring was welded
into an interactive controller, nothing else (notably **leeroy-jenkins**) could hand it
a conversation and say "ship this." It was a point solution that built exactly one
conversation per chat.

`bob-the-builder` splits it into **control vs. execute**, mirroring leeroy-jenkins
(controller `leeroy-jenkins.md` + executor `account-builder-agent` + deterministic
`sf_helpers.py`). The decoupling boundary is a **natural-language brief**.

End goal: **leeroy-jenkins → bob-the-builder, nothing to fully-built account channels in a few clicks.**

## 2. Architecture

| Layer | File | Role | Model |
|---|---|---|---|
| Controller | `bob-the-builder.md` | Intake, credentials, roster fetch, approval gate, orchestration. Human-facing; skippable for programmatic callers. | Strong |
| Executor — Part 1 (author) | `agents/conversation-author-agent.md` | Brief + roster → `<channel>.json` + `<channel>.md`. Parallelizable. **Owns ALL demo-zone schema knowledge.** | Strong |
| Executor — Part 2 (upload) | `scripts/demo_upload.py` | validate · create-channel · dry-run · upload. Deterministic. | n/a |

### Why an agent (not inline)
A subagent gets its own context, runs in parallel (N briefs → N agents, like leeroy
Phase 6), and is callable by any skill via the Agent tool. This is what makes the
leeroy bulk handoff possible.

## 3. The two contracts (the reusable core)

Documented in `reference/CONTRACTS.md` so any producer can integrate without reading the skill.

### Contract A — into the author agent
```json
{
  "brief":       "free text OR a structured doc (leeroy account_<Name>.md works as-is)",
  "channel":     "acct-acme-corp",
  "demo_url":    "https://demo-zone.tinyspeck.com/demo-builder/<id>",
  "roster":      { "users": ["..."], "bots": ["..."] },
  "output_dir":  "/abs/path/to/output",
  "constraints": { "tone": "strategic", "participants": ["adam","jenny"], "must_hit_beats": ["..."] }
}
```
- **The author agent is a PURE FUNCTION: brief + roster → JSON. It never touches the
  network or the token.** The controller does every authenticated pull ONCE (roster =
  users + bots, channel list, anything authors need) and passes that data in. This means
  (a) authors need no token, (b) no N-duplicate roster pulls, (c) the token only matters
  at upload time. `roster` is therefore REQUIRED in Contract A, not optional.
- **Brief parsing is format-agnostic** (decision): accepts a one-liner up to a full
  leeroy account doc; infers tone/beats/participants from whatever it gets; asks the
  caller back ONLY if critically underspecified.
- **Names come only from the passed-in roster** — the agent can never invent a username
  or bot name (the root cause of the old 99-case failure). If the brief names someone not
  in the roster, the agent picks the closest real name or flags it in Contract B.
- **#1 — Bot must exist before Block Kit.** Before authoring an app card, the agent
  confirms that app's bot is in the passed-in roster. Bot present → use
  `blockkit/<app>.json` (or web-search-and-build if missing, per §9). Bot ABSENT → do not
  author that card; fall back to a plain message and flag the gap in Contract B. (No point
  building a card for a bot that will hard-fail at upload resolve.)
- **#2 — Channel-prefixed `client_uuid`s.** Every `client_uuid` the agent emits MUST carry
  a short per-channel prefix derived from the channel (e.g. `acct-genentech` → `ge-1`,
  `ge-3t1`). This guarantees uniqueness when N parallel authors' outputs are merged into one
  upload payload — without it, two agents emitting `msg-1` collide and `referenced_client_uuid`
  silently mis-threads. Load-bearing for bulk runs.

### Contract B — back from the author agent
```json
{
  "channel":      "acct-acme-corp",
  "json_path":    "<output_dir>/acct-acme-corp.json",
  "md_path":      "<output_dir>/acct-acme-corp.md",
  "summary":      "one-paragraph description",
  "participants": ["adam","jenny","Service Cloud for Slack"],
  "action_count": 7,
  "validated":    true
}
```
The JSON is already schema-valid — **#E: the author runs `demo_upload.py validate` on its own
file in a validate→fix→re-validate loop until clean BEFORE returning** (validate is local/no-network,
so a tokenless author can do this). `validated: true` is therefore real, not assumed. This is the
primary guard against the original 99-case failure (bad schema reaching upload).

## 4. Directory layout

```
bob-the-builder/                      # ~/claude-projects/bob-the-builder (sibling of leeroy-jenkins)
├── bob-the-builder.md                # CONTROLLER skill
├── agents/
│   └── conversation-author-agent.md  # EXECUTOR Part 1
├── scripts/
│   └── demo_upload.py                # EXECUTOR Part 2 (ported + hardened)
├── reference/
│   ├── SCHEMA_conversations_actions.md  # demo-zone schema — API-owner doc, authoritative name preserved
│   └── CONTRACTS.md                     # Contracts A & B for producers
├── blockkit/                         # per-app Block Kit examples — flat, one JSON file per app
│   ├── service_cloud.json
│   ├── salesforce.json
│   ├── docusign.json
│   └── <app>.json                    # agent appends new ones after uploads (see §10)
├── examples/
│   ├── acct-acme-corp.json
│   ├── acct-acme-corp.md
│   └── brief-to-conversation.md      # a worked brief → output walkthrough
├── output/                           # generated files land HERE — .gitignored
├── install.sh                        # symlink skill + agent into ~/.claude (leeroy-style)
├── .gitignore                        # output/, .DS_Store, LOCAL.md
├── BUILD_PLAN.md                     # this file
└── README.md
```

Generated files default to `output/` (or a caller-passed `output_dir`) — never scattered
into source folders. This fixes the "it saves into my project folders" complaint.

## 5. Controller flow (`bob-the-builder.md`)

**Interactive path (human):**
1. Intake via AskUserQuestion — demo URL, token, channel(s), tone, audience, append/replace.
2. Save token (`login --stdin`).
3. **Controller does ALL authenticated pulls once** — roster (users + bots), channel list —
   and holds them. This is the only network the authors depend on.
4. Fan out one `conversation-author-agent` per channel (parallel), passing each the roster
   data. **Authors run fully offline — no token, no network.**
5. **Preview ALL conversations together → one approval** (decision).
6. **#3 — Re-check token TTL right HERE, just before any network write.** Authoring N
   conversations burns wall-clock; the token may have aged out since step 2. If it's expired
   or near-expiry, prompt for a fresh one before proceeding. (The pre-upload moment is the only
   place the check matters — authors never needed the token.)
7. create-channel for any that don't exist (duplicate-guarded).
8. dry-run → upload all on confirmation.
9. Report: channels built, action counts, demo URL.

**Concurrency cap (#F):** 5 parallel authors is fine; the old carrier run was 99. The controller
batches large fan-outs (~8–10 authors at a time) rather than launching all at once — avoids waste
and rate-limit errors. Note in the controller.

**Programmatic path (leeroy or other skill):** caller supplies briefs + demo_url
directly → controller skips intake, runs steps 3–9. Same approval gate unless caller
opts out.

## 6. CLI hardening in scope (decision: do now)

Port `demo_upload.py` from `demo-zone-builder` and add:
1. **`create-channel` duplicate guard** — check existing channels first; skip + report if it exists (no more dupes on re-run).
2. **Batch checkpoint / resume** — for bulk uploads that outrun the ~1hr token: track which channels/actions succeeded, resume without re-sending everything. (SESSION_NOTES #5.)
3. **Block Kit-aware validation** — when an action's `text` parses as JSON, accept it as a Block Kit
   payload and verify it has a top-level `blocks` array (see §9). Plain-string `text` still valid.
4. **Per-channel replace/delete** (§10b) — re-push one channel without touching the rest.
5. **#C — `doctor` preflight command** — one call checks: token present + valid + TTL, demo URL
   reachable, workspace resolves, roster non-empty. Fails fast with one clear message BEFORE any
   authoring time is spent. Controller runs this at the top of the flow.

Already present (keep): local validation, workspace auto-detect from `--url`, name→ID
resolution, `--stdin` login, append/replace, dry-run.

Token is a non-secret demo-env credential — no special handling needed; plaintext is fine,
`login` can be on the allowlist.

## 7. Migration & cleanup sequence (only after approval)

1. Scaffold `bob-the-builder/` skeleton.
2. Port from `demo-zone-builder`: `demo_upload.py`, `SCHEMA_conversations_actions.md` (authoritative
   name — NOT the non-authoritative `demo-builder/SCHEMA.md`), `examples/`.
3. Write controller `bob-the-builder.md`, `conversation-author-agent.md`, `CONTRACTS.md`, `README.md`, `install.sh`, `.gitignore`.
4. Harden CLI (§6): duplicate-guard, batch resume, Block-Kit validation, per-channel replace, `doctor`.
5. `git init`, first commit. Create GitHub repo `bob-the-builder`; push.
6. **Verify end-to-end** against a real demo URL (build + upload one channel) BEFORE deleting anything.
7. Document the leeroy handoff call pattern in `CONTRACTS.md` (no leeroy edits — per §8).
8. Delete local `demo-builder` and `demo-zone-builder` folders (no keepers — per §8).
9. Archive (don't delete) the old `github.com/evanbrosen/demo-zone-builder` repo.

## 8. Open items — RESOLVED 2026-06-24
- [x] **Leeroy handoff = documented call pattern first.** bob ships standalone and reusable;
  `CONTRACTS.md` documents exactly how a producer (leeroy) calls the author agent with account
  briefs. SE runs leeroy, then runs bob pointed at `customers/<slug>/`. No edits to the working
  leeroy skill yet — prove bob end-to-end first, add an auto-Phase later once proven.
- [x] **No keepers from `demo-builder` scratch.** `CONVERSATION_PREVIEW_OPTIONS.md` concludes
  "markdown preview + natural-language edits + approve + upload" — already the plan's flow, so it's
  just deliberation. Carrier KB/service_process docs are customer-specific demo *content*, not
  builder infrastructure. Both old folders deleted wholesale after §7 step 6 verification.
- [x] **Author-agent model = inherit session** (no pin), matching leeroy's `account-builder-agent`.

## 9. Block Kit support (added 2026-06-24)

**Key mechanic (proven in old `gen_agilent.py`):** the API schema has NO `blocks` field.
Rich app/bot cards are done by `json.dumps`-ing a `{"blocks":[...]}` object into the action's
`text` string. So `text` holds EITHER plain text OR a serialized Block Kit JSON string.

Implications baked into the build:
1. `reference/SCHEMA_conversations_actions.md` gets an appended note documenting the
   Block-Kit-in-`text` convention (the raw API doc omits it).
2. `demo_upload.py` validator: when a `text` value parses as JSON, accept it and sanity-check it
   has a top-level `blocks` array. (Added to CLI-hardening scope.)

### Block Kit library — `blockkit/`
- **Flat folder, one JSON file per app**, named by app: `service_cloud.json`, `salesforce.json`,
  `docusign.json`, etc. Each file holds canonical Block Kit card example(s) for that app, copy-ready
  for the author agent to serialize into `text`. The app name maps to the bot/`fake_bot_id` in the roster.
- **Seed set:** `service_cloud.json`, `salesforce.json`, `docusign.json` (extracted from
  `gen_agilent.py` + known patterns). Library grows over time (see below).

### Unknown-app behavior (decision)
When the author agent needs an app card it has NO `blockkit/<app>.json` for:
1. **Web-search for screenshots of the official app's Slack messages/cards**, then build Block Kit
   that mirrors the real app's layout (header/sections/fields/context/buttons as seen).
2. Use that generated Block Kit in the conversation.
3. **AFTER the entire upload completes**, the controller OFFERS to save the new example back into
   `blockkit/<app>.json` so the library self-grows. Never auto-writes mid-run; offer + confirm at the end.

## 10. Teardown / re-run (decided 2026-06-24)
- **In scope v1:** per-channel replace/delete in `demo_upload.py` so "fix one channel and re-push"
  works without re-pushing the whole demo (the iterate-on-run-2 case).
- **Deferred:** a full `bob-teardown` command (leeroy-teardown analog) — add after bob is proven.

## 11. Friction-killers (added 2026-06-24)

These target the two mid-build stops Evan named — bash approval prompts and the "expansion
obfuscation" error — plus fast-fail.

### #A — Global scoped allowlist (kills bash-approval prompts)
- `install.sh` OFFERS to add a tightly-scoped allowlist to **global `~/.claude/settings.json`**
  (NOT a repo-local `settings.local.json` — bob runs from arbitrary dirs, e.g. a leeroy
  `customers/<slug>/` folder, so project-scoped perms wouldn't apply).
- Allowlist = bob's read-only/local commands: `validate`, `roster`, `channels`, `users`, `bots`,
  `list`, `doctor`, `--help`, `login`, plus the `security` keychain calls and `git`/`gh` for the repo.
- **`upload` (the network mutation) stays OFF the allowlist** — always a deliberate confirm.
- Avoid the old mistakes: NOT over-specific (`validate examples/foo.json` × N — the old
  demo-zone-builder accreted ~24 of these) and NOT over-broad (`python3 *` — the old demo-builder's
  insecure catch-all). Scope to `python3 <abs-path>/demo_upload.py <subcommand> *`.

### #B — No bash for structured content (kills "expansion obfuscation")
- Hard rule in BOTH the controller and the author agent (leeroy already states this verbatim):
  **all JSON / Block Kit / Python is written with the Write tool, NEVER via `echo`/heredoc/inline
  bash.** Bash sees braces+quotes and hard-stops with the obfuscation error.
- Bob is especially exposed because **Block Kit payloads are pure braces** — a heredoc'd
  `{"blocks":[...]}` would trip it every time. The CLI only ever *reads* JSON files; it never
  constructs JSON in a shell string.

## 12. Still OUT of v1 scope (agreed deferrals)
- Full `bob-teardown` command (§10).
- Leeroy auto-Phase (documented call pattern first, §8).
- Run-manifest / audit log, uninstall script, schema-drift versioning.
- Emoji-name validation, multi-workspace, nested threads.

## 13. Ready to build
All decisions locked (A, B, C, E folded in; D dropped — token is a non-secret demo credential).
Build order = §7. Verification (§7 step 6) needs a live demo URL + fresh token from Evan; everything
before it builds without him. Awaiting go.

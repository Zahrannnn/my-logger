# My Logger — Activity logging skill for AI coding tools

[![GitHub release](https://img.shields.io/github/v/release/Zahrannnn/my-logger)](https://github.com/Zahrannnn/my-logger/releases)
[![license](https://img.shields.io/github/license/Zahrannnn/my-logger)](LICENSE)
[![last commit](https://img.shields.io/github/last-commit/Zahrannnn/my-logger)](https://github.com/Zahrannnn/my-logger/commits)
[![Claude Code](https://img.shields.io/badge/Claude_Code-skill-orange)](https://claude.com/claude-code)
[![PowerShell](https://img.shields.io/badge/powershell-5.1%2B-blue)](https://learn.microsoft.com/en-us/powershell/)

Log your AI-assisted work to any activity tracking API. Five flows (init, submit, edit, delete, status) cover the daily workflow without leaving your terminal.

Works with Claude Code, Cursor, Codex, and any AI tool that can invoke PowerShell scripts.

## Quick Start

```
User: /my-logger
Agent: Today is 2026-07-28. You have 2 existing items. Projects: Core (ID 12), Docs (ID 7). Main task today?
User: Fixed the auth middleware bug and wrote tests
Agent: Drafts 2 tasks → confirms → posts → reports
```



## Installation

### Claude Code (plugin install)

```bash
/plugin marketplace add Zahrannnn/my-logger
/plugin install my-logger@Zahrannnn-my-logger
```

### Any AI tool (npx skills)

```bash
npx skills add Zahrannnn/my-logger
```

Interactive installer. Select your agents (Claude Code, Cursor, Codex, etc.) and it places SKILL.md in the right directory.


## Setup

```bash
# Run inside any connected AI tool:
/my-logger init
```

Answer prompts for your API endpoint, email, password, and role. The init flow logs in, fetches your projects, and writes `~/.config/my-logger/settings.json`. You only do this once.

## What You Get

| Feature | Description |
|---------|-------------|
| Submit | Draft and post daily activities from conversation context |
| Edit | Change title/notes/projectId of existing entries |
| Delete | Remove wrong entries |
| Status | List today's logged time |
| No overlap deletion | Builder auto-stacks new items after existing ones |

## Typical vs With Skill

| Aspect | Without this skill | With my-logger |
|--------|-------------------|----------------|
| Logging workflow | Switch context to browser, open tracker UI, fill form manually | Stay in terminal, AI drafts from conversation, one-confirm posting |
| Daily tracking | Manual hour-by-hour recollection at end of day | AI mines tool calls and edits from session context |
| Time overlap handling | Delete and re-sequence existing entries | Auto-stack after last existing activity |
| Multi-day task splits | Create separate entries across tabs/forms | One task with hours weighted per day |

## How It Works

| Step | What happens |
|------|-------------|
| 1. Preflight | Script pings API server. If unreachable, tells user to connect VPN |
| 2. Gather | Fetches existing activities + projects for the day |
| 3. Draft | AI mines conversation for tool calls matching the task description |
| 4. Confirm | Shows draft table, prompts for day and hour weights |
| 5. Build | PlanJSON constructed with literal or proportional hours |
| 6. Post | Script POSTs each activity, returns IDs of success/failure |
| 7. Report | Per-day summary with response verification |

## Key Design Decisions

- **JSON-only script output** — every helper script emits a single JSON object to stdout. No Write-Host prose. The AI agent parses JSON and drives all user prompts. This makes the skill tool-agnostic (works with Claude Code, Cursor, Codex, etc.).
- **Nothing deleted automatically** — the overlap avoidance rule ("Never Delete to Resolve Time Overlaps") is the most important invariant. The builder stacks new items after existing ones. Users explicitly request deletion.
- **Proportional hours by default** — items get weighted minutes proportional to their `hours` field.
- **Credential in settings file** — password stored in `~/.config/my-logger/settings.json` by user choice. No env vars, no keychain. The agent never sees the password (scripts read it directly).

## Limitations

- Requires PowerShell 5.1+ (Windows) or pwsh 7+ (cross-platform). Ships with Windows, but macOS/Linux users need `pwsh` installed.
- Only works with the `/activities`, `/projects`, and `/users/login` REST API pattern. Your tracker must match these endpoints.
- Edit flow limited to title/notes/projectId — time edits require delete + re-post.
- No batch delete or bulk operations.

## Dependencies

- **PowerShell 5.1+** (required). Ships with Windows; installable on macOS/Linux.
- **VPN connection** (if your API server is on a private network). The preflight check detects unreachable servers and halts gracefully.
- **A REST activity tracking API** implementing the documented endpoints.

## Quality Checklist

- All scripts emit parseable JSON to stdout only
- Error messages go to stderr, never mixed into JSON output
- VPN preflight runs before every API call, not just on first login
- Token acquired fresh per script invocation (never cached to disk)
- Overlapping time slots auto-resolved via cursor stacking (no data loss)
- Failed POSTs return structured error objects with HTTP error messages


## Version History

- **1.0.0** — Initial release. 5 flows, literal/proportional hours, overlap-safe builder.

## License

MIT

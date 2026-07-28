---
name: my-logger
description: Log work to any activity tracking API. Submit, edit, delete, list daily activities, or run a weekly gap-sweep (helpme). Triggers "/my-logger", "my-logger init", "my-logger helpme", "log my activities".
---

# My Logger

Submit work to any activity tracking API via six flows: init, submit, edit, delete, status, helpme. No filesystem scan, no external model.

## When to Activate

- User runs `/my-logger` or `/my-logger init`
- User runs `/my-logger helpme` or "fill my week", "sweep my week"
- User says: "log my activities", "submit my work today"
- User says: "edit my activity", "fix my activity today"
- User says: "delete my activity", "remove the wrong activity"
- User says: "what did I log today", "show my activities"
- User says: "init my logger", "setup my logger"
- User says: "helpme", "fill missing hours"

## Settings Location

`~/.config/my-logger/settings.json`

Single file holds identity, credentials, role, and project list. Password lives in the file — ensure proper file permissions.

Fields: `apiBase`, `email`, `password`, `role`, `userId`, `defaultProjectId`, `defaultProjectName`, `projects`, `totalHours`, `workdayStartLocal`, `workdayEndLocal`, `timezoneId`, `maxActivities`, `fillerProjectId`.

## VPN Preflight — Automatic

The API server is expected to be internal to the user's office network. Every helper script calls `Assert-MyLoggerVpn` before login. The probe handles 4xx/5xx HTTP responses gracefully (server reachable but rejected empty login body) — only genuine connection failures (timeout, DNS, refused) trigger the `UNREACHABLE` error.

Do NOT ask user about VPN status before running helpers. Just run the helper. If it throws `UNREACHABLE`, surface the error verbatim and ask user to connect to their office VPN, then retry. No pre-emptive VPN prompts.

## Helper Scripts

Canonical location: the `scripts/` directory alongside this SKILL.md. Every script outputs JSON only — no `Write-Host` prose except `Write-MyJsonOut` (which outputs a single JSON object to stdout). Agent parses output, drives prompts via whatever user-input mechanism the tool provides, then calls back with answers.

Script reference:

| Script | Purpose | Key Intents |
|---|---|---|
| `my-api.ps1` | Library. Dot-source with `-LibraryOnly`. Exposes all HTTP helpers, `Build-MyActivityObjects`, `Get-MyDayActivitiesJson`, `Write-MyJsonOut`. | — |
| `my-init.ps1` | First-time setup. | `template` prints blank config. `save` logs in, fetches projects, writes `settings.json`. |
| `my-submit.ps1` | Post activities. | `gather` prints settings + projects + today's existing activities. `post` accepts `PlanJSON` (days to items, optional `literalHours: true`) and posts each. `helpme` sweeps Sun-Thu week gaps and emits a plan skeleton. |
| `my-edit.ps1` | Manage existing activities. | `list` prints today's activities. `patch` accepts `Id` + `FieldsJSON`. `remove` accepts `Id` and DELETEs. |

## API Endpoints Used

Base path: `settings.apiBase`.

| Method | Path | Flow |
|---|---|---|
| POST | `/users/login` | every flow, gets bearer token |
| GET | `/projects` | init: multi-select; submit gather: project picker |
| GET | `/activities/user/{userId}` | submit/edit/delete/helpme: list existing for the day (filter client-side by `startTime`) |
| POST | `/activities` | submit post / helpme post: new items |
| PATCH | `/activities/{id}` | edit patch: title/notes/projectId only |
| DELETE | `/activities/{id}` | delete remove: single id |

All examples use synthetic data.

## Flow 1: `/my-logger init` or "init my logger"

First-time setup. Run once.

1. **VPN preflight** — automatic (see above).
2. Run: `pwsh "$scriptsDir\my-init.ps1" -Intent template` -> get blank config schema (stdout: JSON).
3. Prompt user for each field:
   - `apiBase` (the API base URL for your activity tracker)
   - `email`
   - `password`
   - `role` (single select: FE / BE / AI / Mobile / PM / Data / QA / DevOps / Security)
   - `totalHours` (default 9)
   - `workdayStartLocal` (default 09:00), `workdayEndLocal` (default 18:00)
   - `timezoneId` (your local timezone, e.g. `Egypt Standard Time`, `Eastern Standard Time`)
4. Run: `pwsh "$scriptsDir\my-init.ps1" -Intent save -ConfigJSON '<json with above fields>'`.
5. Script logs in, fetches projects (validates password), writes `settings.json`.
6. Script returns JSON with `projects` array.
7. Prompt user (multi-select) which projects to keep as active. If none selected, keep all.
8. If subset chosen, re-save settings manually: edit `~/.config/my-logger/settings.json` and trim `projects` + set `defaultProjectId`/`defaultProjectName` to first selected.
9. Report ready. Tell user to run `/my-logger` anytime.

## Flow 2: `/my-logger` or "log my activities" — Submit

The default flow.

1. **VPN preflight** — automatic.
2. Run: `pwsh "$scriptsDir\my-submit.ps1" -Intent gather` -> JSON: settings, today's date, projects list, existing activities for today.
3. Parse, show user: "Today is YYYY-MM-DD. You already have N activity items: [...]. Projects available: [...]"
4. Prompt user: "Main task today? (one line describing the primary thing you worked on)".
5. Mine current conversation for tool calls / edits / bash runs matching that intent. Group into 1-3 task candidates. For each candidate draft:
   - `title` (4-9 words, specific)
   - `notes` (1-2 sentences, what was actually done)
   - `projectId` (default = settings.defaultProjectId; ask if user wants different)
6. Show draft table: `# | title | notes | project | files touched | hours`
7. Prompt user, one question per task:
   - Day (default today's date; allow override to any `YYYY-MM-DD`)
   - Hours weight (default proportional; allow split like `2h / 3h` across days)
8. Multi-day split: if user gives `2h / 3h` for one task, that's two items (one per day) with those hour weights pointing to same logical task.
9. Build `PlanJSON`:
   ```json
   {
     "days": [
       {
         "date": "2026-07-28",
         "items": [
           { "title": "...", "notes": "...", "projectId": 12, "hours": 2 },
           { "title": "...", "notes": "...", "projectId": 12, "hours": 3 }
         ]
       }
     ]
   }
   ```
10. Show final plan grouped by day, confirm via user prompt.
11. Run: `pwsh "$scriptsDir\my-submit.ps1" -Intent post -PlanJSON '<built json>'` -> JSON `{posted:[...], failed:[...], postedCount, failedCount}`.
12. Report per-day summary with response IDs. If any `failed`, show error messages, ask user if retry wanted.

## Flow 3: `/my-logger edit` or "edit my activity"

1. **VPN preflight** — automatic.
2. Run: `pwsh "$scriptsDir\my-edit.ps1" -Intent list -Date YYYY-MM-DD` (default today) -> today's activities.
3. Show numbered list. Prompt user which to edit.
4. Prompt which fields to change (title/notes/projectId — NOT time). Ask new values.
5. Run: `pwsh "$scriptsDir\my-edit.ps1" -Intent patch -Id <id> -FieldsJSON '{"title":"...","notes":"...","projectId":12}'` (only changed fields).
6. Report result.

## Flow 4: `/my-logger delete` or "delete my activity"

1. **VPN preflight** — automatic.
2. Run: `pwsh "$scriptsDir\my-edit.ps1" -Intent list -Date YYYY-MM-DD` (default today).
3. Show numbered list. Prompt user which to delete. Confirm destructive action.
4. Run: `pwsh "$scriptsDir\my-edit.ps1" -Intent remove -Id <id>`.
5. Report removed.

## Flow 5: `/my-logger status` or "what did I log today"

1. **VPN preflight** — automatic.
2. Run: `pwsh "$scriptsDir\my-edit.ps1" -Intent list -Date YYYY-MM-DD` (default today).
3. Show: "Activities for YYYY-MM-DD: 1. [title] project:foo notes:... ; 2. ..." — read-only.

## Flow 6: `/my-logger helpme` or "fill my week"

Week sweep. Computes gaps for Sun-Thu and fills each day to reach `totalHours` (default 9h) with role-themed research/self-learning tasks. Adds weekly team meeting on Monday 12:00 if missing.

1. **VPN preflight** — automatic.
2. Run: `pwsh "$scriptsDir\my-submit.ps1" -Intent helpme` -> JSON: `{weekStart, role, defaultProjectId, fillerProjectId, totalHours, days:[{date, dayName, holiday, hoursLogged, gap, hasMeeting}]}`.
3. Parse and show user a per-day table:
   ```
   Week of YYYY-MM-DD (role: FE)
   Sun YYYY-MM-DD — logged 5h, gap 4h
   Mon YYYY-MM-DD — logged 8h, gap 1h, meeting present
   Tue YYYY-MM-DD — logged 9h, gap 0h (full)
   Wed YYYY-MM-DD — logged 0h, gap 9h
   Thu YYYY-MM-DD — logged 2h, gap 7h
   ```
4. Prompt user (multi-select): "Any official holiday this week? Select all that apply." Options = each day's date string.
5. If holidays marked, re-run with `-HolidaysCSV` flag.
6. If `settings.role` is empty, prompt user for role (single select: FE / BE / AI / Mobile / PM / Data / QA / DevOps / Security). Suggest updating settings via `/my-logger init` next time.
7. For each day with `gap > 0`:
   - **Monday + `hasMeeting = false`**: add Weekly Team Meeting item `{title:"Weekly Team Meeting", notes:"Weekly sync with team", projectId:settings.defaultProjectId, hours:1, startTimeLocal:"12:00"}`. Subtract 1h from remaining gap.
   - **Remaining gap**: split across 1-3 filler tasks themed per weekday (see Role Themes table below). Each filler: `projectId: settings.fillerProjectId`. `hours` sum to remaining gap. Rotate themes across days so no two days share identical task titles.
8. Build `PlanJSON`:
   ```json
   {
     "literalHours": true,
     "days": [
       {
         "date": "2026-07-26",
         "items": [
           { "title": "...", "notes": "...", "projectId": 23, "hours": 3 },
           { "title": "...", "notes": "...", "projectId": 23, "hours": 1 }
         ]
       },
       {
         "date": "2026-07-27",
         "items": [
           { "title": "Weekly Team Meeting", "notes": "Weekly sync with team", "projectId": 12, "hours": 1, "startTimeLocal": "12:00" },
           { "title": "...", "notes": "...", "projectId": 23, "hours": 7 }
         ]
       }
     ]
   }
   ```

`literalHours: true` tells `Build-MyActivityObjects` to treat each item's `hours` field as literal hours (not proportional weights). Default submit flow omits this flag and uses proportional weighting across the workday.

9. Show final plan grouped by day. Confirm via user prompt.
10. Run: `pwsh "$scriptsDir\my-submit.ps1" -Intent post -PlanJSON '<built json>'` -> JSON `{posted:[...], failed:[...], postedCount, failedCount}`.
11. Report per-day summary with response IDs. If any `failed`, show error messages, ask user if retry wanted.

### Role Themes

Each role has 5 theme buckets. Agent rotates buckets across the 5 weekdays (Sun to Thu) so each day gets a different theme. When a day needs multiple filler tasks, pick 2-3 distinct themes from same role and split the gap.

| Role | Sun | Mon | Tue | Wed | Thu |
|---|---|---|---|---|---|
| FE | React/Vue patterns deep-dive | CSS layout & animation research | Bundle size / Web Vitals optimization | Component library spike | Cross-browser compat research |
| BE | API design & schema research | DB indexing & query tuning | Auth/session security review | Caching patterns spike | Async/queue processing research |
| AI | Model evaluation benchmarks | Prompt engineering research | RAG retrieval tuning spike | Fine-tuning dataset prep | LLM guardrails & safety research |
| Mobile | Platform lifecycle research | Animation/transition spike | Offline sync patterns | Crash analytics review | Store submission checklist |
| PM | Roadmap & scope planning | Stakeholder interview prep | Risk register review | Retrospective action items | Metrics & KPI research |
| Data | Schema & warehouse modeling | ETL pipeline spike | Data quality audit | Dashboard & viz research | Query performance tuning |
| QA | Test framework spike | Flaky test investigation | Coverage gap analysis | E2E scenario design | Performance test research |
| DevOps | IaC pattern (Terraform) research | CI pipeline optimization | Container image hardening | Observability & alerting spike | Secrets & rotation review |
| Security | Threat model refresh | Dependency CVE review | AuthZ policy audit | Secrets scanning spike | Pen-test rehearsal prep |

Filler task title template: `<theme phrase>: <specific topic>`. Notes: 1-2 sentences describing what was researched/learned. Hours: agent decides split per day's remaining gap.

## Rules

- Scripts emit JSON only (stdout) or structured errors (stderr). Agent parses and presents.
- A new token is acquired per script call (in-memory only, no token file).
- Project picker: ask every session, never auto-assume.
- Edit is limited to title/notes/projectId. Time edits require delete + re-post.
- Filter activities by `startTime` date client-side in the script.
- Dedup fingerprint check is dropped — user confirms every submit, no accidental duplicates.
- Default day per task: today. User overrides via prompt.
- Multi-day split allowed: same logical task with `2h / 3h` becomes two POST objects.

### Never Delete to Resolve Time Overlaps

Existing activities are immutable. The agent MUST NOT delete or re-post existing activities to "fix" time overlaps or "sequentialize" time slots.

- If a new activity's allocated time overlaps an existing activity, the builder (`Build-MyActivityObjects` with `-ExistingActivities`) automatically pushes the new activity to the next available slot after existing activities end. No manual deletion needed.
- If the workday has no remaining gaps, ask the user — do NOT delete anything.
- Existing activities are only deletable via the explicit "delete my activity" flow, only when the user explicitly asks.
- Never propose "delete the first activity and re-post all six" or any variant.

## Failures

- Login fails -> tell user password in `~/.config/my-logger/settings.json` is wrong, suggest `/my-logger init`.
- Settings file missing -> tell user to run `/my-logger init`.
- No projects returned -> suggest `/my-logger init` again or check API permissions.
- POST fails for one item -> script returns it in `failed[]`, agent reports, ask retry.
- Script throws PowerShell error -> show raw error, suggest inspecting settings file.
- `UNREACHABLE` error -> tell user to connect to their office VPN, retry same command.
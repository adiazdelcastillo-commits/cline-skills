---
name: remote-python-runner
description: Run a project's validation and test suite on remote GitHub-hosted Python through the GitHub MCP Server, then report the results. Use whenever the user asks to run tests, validations, checks, lint, pytest, or to verify that code works, and no local Python interpreter is available, or when the user explicitly asks for cloud or remote execution.
---

# Remote Python Runner

Execute the project's test suite on GitHub-hosted Python and report the result.

## Decision rule

1. If a working local Python interpreter exists AND the user did not ask for remote
   execution, run tests locally.
2. Otherwise, execute remotely on GitHub via the GitHub MCP Server.

## Preconditions

- The `github` MCP server is connected and listed in the MCP Servers panel.
- The target repository contains `.github/workflows/run-tests.yml`.
- That workflow exists on the default branch.

If any precondition fails, say so and offer the fallback
`scripts/gh-run.ps1` (REST channel) before attempting anything else.

### Checking whether the MCP tools are actually available

Before assuming the MCP channel works, confirm you can see tools such as
`actions_run_trigger`, `actions_list` and `actions_get` in your own tool list.

**If those tools are absent, the MCP channel is not available in this session.**
Do not attempt MCP calls and do not report an MCP error: switch directly to the
REST fallback and tell the user the MCP server is configured but not connected.

### If the server responds but `actions_*` tools are missing

The `X-MCP-Toolsets` header filters which tools the server delivers. Verified against
the live server:

| `X-MCP-Toolsets` | Total tools | `actions_*` |
|---|---|---|
| *(absent — default)* | 46 | **0** |
| `actions` | 4 | 3 |
| `actions,repos,context` | 27 | 3 |
| `all` | 95 | 3 |

The header must be present in `cline_mcp_settings.json` under
`mcpServers.github.headers`. Without it the default toolset excludes Actions entirely,
which looks exactly like "the server is not connected".
Diagnose with `scripts/diagnose-mcp.ps1` or `scripts/diag-toolsets.ps1`.

## Procedure

1. Identify `owner` and `repo`. Ask the user only if they cannot be inferred.
2. Confirm the workflow exists with
   `actions_list(method=list_workflows, owner, repo)`.
3. Trigger it with
   `actions_run_trigger(owner, repo, workflow_id=run-tests.yml, ref, inputs={suite, pytest_args})`.
4. Poll every ~10 s for up to 15 min using
   `actions_list(method=list_workflow_runs)`.
5. Read the outcome with `actions_get(method=get_workflow_run, run_id)`.
6. Fetch results:
   - `actions_get(method=get_workflow_run_logs_url, run_id)` for logs
   - `actions_get(method=list_workflow_run_artifacts, run_id)` then
     `download_workflow_run_artifact` for `summary.md` and `report.xml`.
7. Report to the user: conclusion, counts of passed and failed tests, top
   failures with their assertion messages, and a link to the run.

## Reporting rules (non-negotiable)

- **Never report success unless `conclusion == "success"`.** If it is `failure`,
  `cancelled` or `timed_out`, report that exact state.
- A green workflow with failing tests is impossible: the workflow fails the job when
  pytest fails. If you ever see `success` together with `failures > 0` in `report.xml`,
  treat it as a **pipeline bug** and report it as such — never as a pass.
- Always state the test counts (`passed`, `failed`, `errors`, `skipped`) from
  `report.xml`, not an impression.
- Always include the run URL.
- If the run cannot be completed (timeout, auth error, missing workflow), report the
  error and the remedy from `references/troubleshooting.md`.

## Inputs the workflow accepts

| Input | Values | Meaning |
|---|---|---|
| `suite` | `all`, `fast`, `slow` | `fast` runs `-m "not slow"`; `slow` runs `-m slow` |
| `pytest_args` | free text | Extra pytest arguments, e.g. `-k redondeo_comercial` |

Never invent inputs that the workflow does not declare.

## Fallback

If the MCP server is unavailable, run:

```powershell
.\scripts\gh-run.ps1 -Owner <owner> -Repo <repo>
```

This uses the REST channel with the same PAT that the MCP server uses. It never
prints the token.

## Safety

- Never write, echo or log the PAT.
- Never run workflows on code from untrusted forks without telling the user first.
- The workflow declares `permissions: contents: read`; do not weaken it.
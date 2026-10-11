---
name: remote-python-runner
description: Run a project's pytest/validation suite on remote GitHub-hosted Python through the GitHub MCP server, then report the results. Use whenever the user asks to run tests, validations, checks, lint, pytest, or to verify that code works, and no local Python interpreter is available, or when the user explicitly asks for cloud or remote execution.
metadata:
  opencode/slash: "true"
---

# Remote Python Runner

Execute the project's test suite on GitHub-hosted Python and report the result.

## Refuse fast (read before anything else)

Check the three preconditions below FIRST. If any fails, decline in ONE line stating
which one and why remote execution cannot help here — then do the work the way that
fits (usually locally). Do NOT narrate the skill, do NOT announce invocation ceremony,
do NOT write paragraphs explaining the skill itself.

## Decision rule

1. If a working local Python interpreter exists AND the user did not ask for remote
   execution AND the job's useful output is local files (media, builds, extracted
   documents), run locally.
2. If the job produces local artifacts the user needs on disk (audio, screenshots,
   rendered files), run locally even when remote was requested: explain in one line
   that remote runners cannot deliver files to this machine, then proceed locally.
3. Otherwise, execute remotely on GitHub via the GitHub MCP server.

## Preconditions (all three must hold for remote execution)

- The `github` MCP server is connected (`github_actions_*` tools visible).
- The target repository contains `.github/workflows/run-tests.yml`.
- That workflow exists on the default branch.

Remote validation rule
-----------------------

This is the correction that the current session fixed. The local folder is irrelevant
for finding the workflow: `run-tests.yml` is declared by the repository being run,
not by the folder that happens to be open. Open Code in any empty folder, give it the
repository URL or owner/repo, and it must:

1. Treat any local git worktree as optional. If the current folder is not a git
   repository, say so and move on to the remote check.
2. Ask the user to confirm the repository before triggering. The user may point to a
   repository that the skill does not own, and the workflow may be invisible to the
   skill until it is run on a repository where it exists.
3. Validate that the repository on the default branch contains
   `.github/workflows/run-tests.yml`. If the workflow exists, tell the user so and
   proceed.
4. If the current folder is a git repository but the workflow is not found in the
   repository, the precondition fails and the skill declines. That is the only real
   failure: the repository does not contain the workflow that the skill must run.

This keeps the refusal fast and accurate, and does not require a local clone or a
manually opened folder.

## Procedure

1. Identify `owner` and `repo`. Ask the user only if they cannot be inferred.
2. Confirm the workflow exists with `github_actions_list` (method `list_workflows`).
3. Trigger it with `github_actions_run_trigger` (`workflow_id=run-tests.yml`, `ref`,
   `inputs={suite, pytest_args}`).
4. Poll every ~10 s for up to 15 min with `github_actions_list` (method
   `list_workflow_runs`).
5. Read the outcome with `github_actions_get` (method `get_workflow_run`).
6. Fetch results: `github_actions_get` (method `get_workflow_run_logs_url`), then
   `list_workflow_run_artifacts` plus `download_workflow_run_artifact` for
   `summary.md` and `report.xml`.
7. Report: conclusion, passed/failed/error/skipped counts from `report.xml`, top
   failures with assertion messages, and the run URL.

> Tool names carry the MCP server-name prefix. The names above assume the server is
> named `github` in `opencode.json`. If you named it differently, replace the
> `github_` prefix with `<your-server-name>_`.

## Reporting rules (non-negotiable)

- Never report success unless `conclusion == "success"`.
- `success` together with `failures > 0` in `report.xml` is a pipeline bug: report
  it as such, never as a pass.
- Always state counts from `report.xml`, never an impression.
- Always include the run URL.
- On timeout, auth errors or a missing workflow, report the error and the remedy.

## Workflow inputs

| Input | Values | Meaning |
|---|---|---|
| `suite` | `all`, `fast`, `slow` | maps to the pytest `-m` selectors |
| `pytest_args` | free text | extra pytest args, e.g. `-k redondeo_comercial` |

Never invent inputs the workflow does not declare.

## Safety

- Never write, echo or log the PAT.
- Never run workflows on code from untrusted forks without telling the user first.
- Keep the workflow's `permissions: contents: read`; do not weaken it.

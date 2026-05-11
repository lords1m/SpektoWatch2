# ACP Integration

ACP is installed as a repository-local context layer. It does not add runtime
dependencies to the iOS or watchOS targets.

## Installed Files

- Root `AGENT.md` for agent session bootstrapping.
- `agent/progress.yaml` for current state and next action.
- `agent/commands/*.md` for reusable command prompts.
- `agent/design/*.md` for durable product and technical context.
- `agent/milestones/*.md` and `agent/tasks/**` for work tracking.
- `agent/scripts/acp-status` and `agent/scripts/acp-validate` for local checks.

## How To Use

At the start of a task, read the root `AGENT.md`, inspect `progress.yaml`, then
open the active task file. During implementation, update the task status and any
relevant design notes. Before final handoff, run validation and note test
results in the response.

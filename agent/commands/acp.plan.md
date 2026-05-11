# ACP Plan

Generate milestones and tasks from the active design document.

## Inputs

- Active design: `agent/design/spektowatch-field-engineering-design.md`
- Current progress: `agent/progress.yaml`
- Existing milestones and tasks under `agent/milestones/` and `agent/tasks/`

## Procedure

1. Read the active design.
2. Extract the next milestone boundary, acceptance criteria, and non-goals.
3. Create one immediate milestone with concrete implementation tasks.
4. Capture later scope as future milestones or backlog, not as active tasks.
5. Make the first actionable task the current task in `agent/progress.yaml`.
6. Update validation to include any newly required ACP artifacts.

## Output

- A milestone file under `agent/milestones/`.
- Task files under `agent/tasks/<milestone-id>/`.
- Updated `agent/progress.yaml`.

The next command is usually `@acp.proceed`.

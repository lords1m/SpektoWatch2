# ACP Sync

Reconcile `agent/progress.yaml` with milestone and task files.

## Steps

1. Read all milestone files under `agent/milestones/`.
2. Read task files referenced by the active milestone.
3. Ensure completed task IDs in `progress.yaml` correspond to completed task
   files.
4. Update `current_task`, `status`, and `active_context.next_action` if the
   active task is complete.

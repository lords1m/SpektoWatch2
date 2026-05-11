# ACP Clarification Create

Generate a clarification document from the active draft.

## Inputs

- Prefer a draft under `agent/drafts/*.draft.md`.
- If no draft exists, use the most relevant project brief under
  `agent/design/`.

## Output

Create `agent/clarifications/<draft-name>.clarification.md`.

The clarification document must focus on:

- Gaps in requirements or proposed solution.
- Ambiguous requirements.
- Open questions.
- Poorly defined specs.
- Acceptance criteria that are missing or not measurable.

Questions should include blank answer lines beginning with `>` so the user can
respond inline. Keep the document specific to the repository and current draft;
do not generate generic product questions when the codebase already answers
them.

## After Creating

Tell the user where the clarification file is and ask them to answer directly on
the `>` lines. The next command is `@acp.clarification-address`.

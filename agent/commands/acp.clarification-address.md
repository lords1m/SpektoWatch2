# ACP Clarification Address

Process user responses in the active clarification document.

## Inputs

- Active clarification: `agent/clarifications/*.clarification.md`
- Source draft referenced by the clarification file.

## Procedure

1. Read the clarification document.
2. Find user responses on lines beginning with `>`.
3. For each answered area, add agent analysis in HTML comment blocks so the
   user's original answer remains intact.
4. Resolve "I don't know" answers by giving a recommendation, assumptions, and
   tradeoffs.
5. Flag contradictions, cascading effects, or remaining open questions.
6. Update the clarification `Status` to `addressed` only when every answered
   area has been processed.
7. Update `agent/progress.yaml` with the next recommended ACP step.

## Output

The clarification document should contain:

- Key decisions.
- Recommendations.
- Remaining open questions.
- Acceptance implications.

The next command is usually `@acp.design-create --from clar`.

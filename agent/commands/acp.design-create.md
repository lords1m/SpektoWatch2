# ACP Design Create

Create a durable design document from a draft or addressed clarification.

## Usage

`@acp.design-create --from clar`

## Inputs

- Prefer an addressed clarification under `agent/clarifications/`.
- Use the source draft referenced by the clarification for original framing.

## Procedure

1. Read the addressed clarification.
2. Extract user decisions, agent recommendations, tradeoffs, and open questions.
3. Create a design document under `agent/design/`.
4. Include a key decisions appendix.
5. Preserve open questions that still block future implementation.
6. Update `agent/progress.yaml` with the next ACP step.

## Output

The next step is usually `@acp.plan`.

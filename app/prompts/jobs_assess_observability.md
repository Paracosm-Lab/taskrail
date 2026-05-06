# Job Observability: Assess Observability

You are the assessment stage for the `job_observability` queue.

Read the upstream `job_inventory` artifact and relevant source code. Score each job on a 0-3 scale for error_capture, structured_logging, timeout_protection, retry_strategy, idempotency, context_propagation, and metrics.

Classification rules:
- `well_instrumented`: average score >= 2.0
- `under_instrumented`: average score >= 1.0 and < 2.0
- `blind`: average score < 1.0

Include a human-readable scorecard in the success report body and return only JSON that TaskRail can parse with an `observability_assessment` artifact. Do not edit files in this stage.

# Logging Assess Quality

You are the assess_quality agent for the StupidClaw Logging Consistency Audit cookbook.

## Inputs

- The upstream `log_inventory` artifact.
- Relevant source files from the repository.

## Task

Score logging quality per file/module. Consider:

- Structured: key-value/hash/JSON logs score higher than bare strings.
- Contextual: request_id, user_id, operation, job_id, external service name, and error class improve usefulness.
- Appropriate level: identify debug noise at info/error levels and expected conditions logged as errors.
- Useful: decide whether a log would help reconstruct an incident.
- Existing good patterns: identify patterns already present in the codebase that can become the standard.
- Worst offenders: prioritize controllers, jobs, service objects, error handlers, and critical paths with no logging or debug output.

## Output

Return a successful report and one artifact of kind `logging_assessment` with this shape:

```json
{
  "best_patterns": [
    { "file": "app/services/payment_processor.rb", "line": 18, "reason": "structured event with operation and user_id" }
  ],
  "worst_offenders": [
    { "file": "app/controllers/orders_controller.rb", "line": 12, "reason": "puts params.inspect leaks noisy unstructured data", "priority": "high" }
  ],
  "scores_by_file": {
    "app/controllers/orders_controller.rb": { "score": 20, "reasons": ["debug output", "missing context"] }
  },
  "recommended_standard": {
    "format": "structured_json",
    "required_context": ["operation", "request_id"],
    "source": "best existing patterns"
  }
}
```

Do not edit files in this stage.

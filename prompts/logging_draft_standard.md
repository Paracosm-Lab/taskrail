# Logging Draft Standard

You are the draft_standard agent for the StupidClaw Logging Consistency Audit cookbook.

## Inputs

- The upstream `logging_assessment` artifact.
- Any examples of best patterns from the source code.

## Task

Draft a logging standard based on the best working patterns already found in the codebase.

Include:

- Required fields by log level.
- Structured format specification.
- Level guidelines for debug/info/warn/error/fatal.
- Anti-patterns to avoid.
- Example log lines for request handling, job processing, external API calls, and error recovery.

## Output

Return a successful report and one artifact of kind `logging_standard` with this shape:

```json
{
  "standard": {
    "format": "structured_json",
    "required_fields_by_level": {
      "info": ["event", "operation"],
      "warn": ["event", "operation", "reason"],
      "error": ["event", "operation", "error_class", "error_message", "request_id"]
    },
    "guidelines": [
      "Use info for business lifecycle events.",
      "Use warn for recoverable unexpected conditions.",
      "Use error for failed operations requiring investigation."
    ],
    "examples": [
      { "scenario": "job processing", "log": { "event": "job_started", "operation": "SyncUserJob", "user_id": "..." } }
    ],
    "anti_patterns": [
      "puts params.inspect",
      "Rails.logger.error e.message without error_class or backtrace context"
    ]
  }
}
```

Do not edit files in this stage.

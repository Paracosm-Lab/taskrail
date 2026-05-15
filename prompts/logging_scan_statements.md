# Logging Scan Statements

You are the scan_log_statements agent for the TaskRail Logging Consistency Audit cookbook.

## Inputs

- Assignment repository path or default working directory.
- Any upstream context included in the assignment.

## Task

Find every log-like statement across the codebase, including:

- `Rails.logger.*`
- `Logger.*`
- `console.log`
- `puts`
- `print`
- `p`
- `pp`
- Custom logger calls such as `logger.info`, `ApplicationLogger`, or service-specific wrappers
- Sentry breadcrumbs, tags, context, and captured exception context calls

For each statement, capture:

- `file`: repo-relative file path
- `line`: integer line number
- `logger`: logger API or debug output function used
- `level`: `debug`, `info`, `warn`, `error`, `fatal`, `breadcrumb`, `context`, or `unknown`
- `format`: `structured`, `unstructured`, or `debug_output`
- `content`: concise description or literal logged content
- `context_present`: true when correlation or useful diagnostic fields are present

Classify structured logs as key-value/hash/JSON-style output, unstructured logs as bare strings/interpolation, and debug output as `puts`/`print`/`p`/`pp` style statements.

## Output

Return a successful report and one artifact of kind `log_inventory` with this shape:

```json
{
  "statements": [
    {
      "file": "app/controllers/orders_controller.rb",
      "line": 12,
      "logger": "Rails.logger",
      "level": "info",
      "format": "unstructured",
      "content": "processing order",
      "context_present": false
    }
  ],
  "summary": {
    "total": 1,
    "by_format": { "unstructured": 1 },
    "by_level": { "info": 1 },
    "by_service": { "rails_app": 1 }
  }
}
```

Do not edit files in this stage.

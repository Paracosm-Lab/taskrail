# Job Observability: Scan Job Classes

You are the scan stage for the `job_observability` queue.

Read the assignment context and repository files. Find every async job or worker class for frameworks including ActiveJob, Sidekiq, GoodJob, SQS workers, and Celery-style workers when present.

For each job, catalog:
- class_name
- file
- queue
- args from the perform/call method signature
- retry_config including max retries, backoff, and dead letter behavior
- timeout or deadline configuration
- error_handling such as rescue blocks, Sentry capture, or logger error calls
- logging statements and whether they are structured/contextual
- idempotent evidence or missing idempotency handling
- dependencies such as databases, external APIs, storage, mailers, or other services
- schedule such as cron, on-demand, event-driven, or unknown

Return only JSON that StupidClaw can parse with a `job_inventory` artifact containing framework and jobs entries. Do not edit files in this stage.

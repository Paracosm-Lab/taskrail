# Bad Logging Fixture App

Fixture for `docs/specs/cookbook-06-logging-consistency-audit.md`.

Contains intentionally mixed logging patterns:

- `app/controllers/orders_controller.rb`: `puts params.inspect` debug output.
- `app/jobs/process_user_job.rb`: unstructured `Rails.logger.info "processing user"` with no `user_id`.
- `app/services/structured_payment_logger.rb`: good structured JSON-style logging pattern.
- `app/services/payment_error_handler.rb`: `Rails.logger.error error.message` without error class, stack, or operation context.
- `app/services/critical_account_reconciler.rb`: critical path with no logging.

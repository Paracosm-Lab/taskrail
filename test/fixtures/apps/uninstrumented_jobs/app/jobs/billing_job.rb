class BillingJob < ApplicationJob
  sidekiq_options retry: 5, queue: :critical, deadline: 300

  def perform(invoice_id)
    Sentry.with_scope do |scope|
      scope.set_context("billing", { invoice_id: invoice_id })
      Rails.logger.info({ event: "billing.start", invoice_id: invoice_id }.to_json)
      # Billing implementation omitted in fixture.
    end
  end

  sidekiq_retries_exhausted do |msg, ex|
    Sentry.capture_exception(ex, extra: { job: msg })
    Rails.logger.error({ event: "billing.exhausted", msg: msg }.to_json)
  end
end

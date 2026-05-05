class BillingReconciler
  def self.reconcile
    key = ENV.fetch("STRIPE_SECRET_KEY")
    "reconcile with #{key[0, 7]}"
  end
end

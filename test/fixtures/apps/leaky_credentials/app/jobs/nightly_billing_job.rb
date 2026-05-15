class NightlyBillingJob
  def perform
    PaymentGateway.charge(1000)
    BillingReconciler.reconcile
  end
end

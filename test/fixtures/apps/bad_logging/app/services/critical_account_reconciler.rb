class CriticalAccountReconciler
  def self.call(account_id:)
    account = Account.find(account_id)
    account.reconcile!
    account.save!
  end
end

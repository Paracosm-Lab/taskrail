class Customer
  def active?
    true
  end

  def stale_score
    0
  end

  def dynamic_billing_status
    public_send(:active?)
  end
end

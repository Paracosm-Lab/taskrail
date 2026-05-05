class ExportJob < ApplicationJob
  def perform(user_id)
    user = User.find(user_id)
    csv = generate_csv(user.orders)
    S3.upload("exports/#{user_id}.csv", csv)
  end

  private

  def generate_csv(orders)
    orders.map(&:to_s).join("\n")
  end
end

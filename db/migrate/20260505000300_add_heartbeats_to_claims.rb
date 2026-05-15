class AddHeartbeatsToClaims < ActiveRecord::Migration[8.0]
  def change
    add_column :claims, :last_heartbeat_at, :datetime
    add_column :claims, :heartbeat_message, :string
  end
end

class AddMetadataToClaims < ActiveRecord::Migration[8.0]
  def change
    add_column :claims, :metadata, :jsonb, null: false, default: {}
  end
end

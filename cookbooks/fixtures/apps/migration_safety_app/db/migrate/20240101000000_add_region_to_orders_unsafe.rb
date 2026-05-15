class AddRegionToOrdersUnsafe < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :region, :string, null: false, default: "us"
  end
end

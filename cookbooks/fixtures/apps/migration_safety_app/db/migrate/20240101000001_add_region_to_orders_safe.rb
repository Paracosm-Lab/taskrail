class AddRegionToOrdersSafe < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_column :orders, :region, :string
    OrderBackfill.region!(default_region: "us")
    change_column_null :orders, :region, false
  end

  def down
    remove_column :orders, :region
  end
end

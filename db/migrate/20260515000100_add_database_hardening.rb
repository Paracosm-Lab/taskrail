class AddDatabaseHardening < ActiveRecord::Migration[8.0]
  def change
    add_index :claims, :status
    add_index :work_items, :status
    add_index :trace_events, [:trace_id, :sequence]

    add_check_constraint :work_items, "status BETWEEN 0 AND 5", name: "work_items_status_check"
    add_check_constraint :claims, "status BETWEEN 0 AND 3", name: "claims_status_check"
  end
end

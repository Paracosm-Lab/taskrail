class AddCategoryToWorkQueues < ActiveRecord::Migration[8.0]
  def change
    add_column :work_queues, :category, :string
  end
end

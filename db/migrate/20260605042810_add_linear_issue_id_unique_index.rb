class AddLinearIssueIdUniqueIndex < ActiveRecord::Migration[8.0]
  def change
    add_index :work_items, "(tags->>'linear_issue_id')",
              unique: true,
              where: "tags->>'linear_issue_id' IS NOT NULL",
              name: "idx_work_items_linear_issue_id"
  end
end

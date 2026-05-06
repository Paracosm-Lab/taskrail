class AddPipes < ActiveRecord::Migration[8.0]
  def change
    create_table :pipes, id: :uuid do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.references :from_queue, null: false, foreign_key: { to_table: :work_queues }, type: :uuid
      t.string :from_stage, null: false
      t.references :to_queue, null: false, foreign_key: { to_table: :work_queues }, type: :uuid
      t.string :to_stage
      t.jsonb :when_config, null: false, default: {}
      t.jsonb :transform_config, null: false, default: {}
      t.jsonb :limits, null: false, default: {}
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end
    add_index :pipes, :slug, unique: true

    # work_items.pipe_id — set when a pipe created this item, null otherwise
    add_reference :work_items, :pipe, type: :uuid, foreign_key: { to_table: :pipes }, null: true

    # artifacts.claim_id — make nullable so pipe-copied artifacts need no claim
    change_column_null :artifacts, :claim_id, true
  end
end

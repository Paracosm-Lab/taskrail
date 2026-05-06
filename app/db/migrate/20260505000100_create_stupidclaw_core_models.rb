class CreateStupidclawCoreModels < ActiveRecord::Migration[8.0]
  def change
    create_table :work_queues, id: :uuid do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.jsonb :stages, null: false, default: []
      t.jsonb :config, null: false, default: {}
      t.timestamps
    end
    add_index :work_queues, :slug, unique: true

    create_table :stage_configs, id: :uuid do |t|
      t.references :work_queue, null: false, foreign_key: true, type: :uuid
      t.string :stage_name, null: false
      t.string :allowed_skills, array: true, null: false, default: []
      t.string :forbidden_skills, array: true, null: false, default: []
      t.integer :max_retries
      t.string :escalation_target
      t.jsonb :completion_criteria, null: false, default: []
      t.text :agent_prompt
      t.string :model_override
      t.integer :timeout_seconds
      t.string :adapter_type, null: false, default: "fake"
      t.timestamps
    end
    add_index :stage_configs, [:work_queue_id, :stage_name], unique: true

    create_table :work_items, id: :uuid do |t|
      t.string :title, null: false
      t.string :spec_url, null: false
      t.references :work_queue, null: false, foreign_key: true, type: :uuid
      t.string :stage_name, null: false
      t.integer :status, null: false, default: 0
      t.references :parent, foreign_key: { to_table: :work_items }, type: :uuid
      t.integer :position
      t.jsonb :tags, null: false, default: {}
      t.integer :retry_count, null: false, default: 0
      t.integer :regression_count, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    create_table :claims, id: :uuid do |t|
      t.references :work_item, null: false, foreign_key: true, type: :uuid
      t.string :agent_type, null: false
      t.jsonb :assignment, null: false, default: {}
      t.integer :status, null: false, default: 0
      t.boolean :async_execution, null: false, default: false
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :timeout_seconds
      t.timestamps
    end

    create_table :reports, id: :uuid do |t|
      t.references :claim, null: false, foreign_key: true, type: :uuid
      t.references :work_item, null: false, foreign_key: true, type: :uuid
      t.string :stage_name, null: false
      t.integer :status, null: false, default: 0
      t.jsonb :body, null: false, default: {}
      t.text :blocked_question
      t.timestamps
    end

    create_table :artifacts, id: :uuid do |t|
      t.references :work_item, null: false, foreign_key: true, type: :uuid
      t.references :claim, null: false, foreign_key: true, type: :uuid
      t.string :kind, null: false
      t.jsonb :data, null: false, default: {}
      t.timestamps
    end

    create_table :traces, id: :uuid do |t|
      t.references :claim, null: false, foreign_key: true, type: :uuid
      t.references :work_item, null: false, foreign_key: true, type: :uuid
      t.string :stage_name, null: false
      t.string :agent_type, null: false
      t.string :model
      t.integer :total_tokens_in, null: false, default: 0
      t.integer :total_tokens_out, null: false, default: 0
      t.integer :total_cost_cents, null: false, default: 0
      t.integer :total_duration_ms, null: false, default: 0
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    create_table :trace_events, id: :uuid do |t|
      t.references :trace, null: false, foreign_key: true, type: :uuid
      t.integer :sequence, null: false
      t.string :event_type, null: false
      t.integer :tokens_in, null: false, default: 0
      t.integer :tokens_out, null: false, default: 0
      t.integer :cost_cents, null: false, default: 0
      t.integer :duration_ms, null: false, default: 0
      t.text :input_summary
      t.text :output_summary
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    create_table :transition_logs, id: :uuid do |t|
      t.references :work_item, null: false, foreign_key: true, type: :uuid
      t.string :from_stage
      t.string :to_stage
      t.string :trigger, null: false
      t.jsonb :details, null: false, default: {}
      t.timestamps
    end
  end
end

# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_05_16_012500) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "artifacts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "work_item_id", null: false
    t.uuid "claim_id"
    t.string "kind", null: false
    t.jsonb "data", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["claim_id"], name: "index_artifacts_on_claim_id"
    t.index ["work_item_id"], name: "index_artifacts_on_work_item_id"
  end

  create_table "claims", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "work_item_id", null: false
    t.string "agent_type", null: false
    t.jsonb "assignment", default: {}, null: false
    t.integer "status", default: 0, null: false
    t.boolean "async_execution", default: false, null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.integer "timeout_seconds"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_heartbeat_at"
    t.string "heartbeat_message"
    t.jsonb "metadata", default: {}, null: false
    t.index ["status"], name: "index_claims_on_status"
    t.index ["work_item_id"], name: "index_claims_on_work_item_id"
    t.check_constraint "status >= 0 AND status <= 3", name: "claims_status_check"
  end

  create_table "personal_access_tokens", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "name", null: false
    t.string "token_digest", null: false
    t.string "token_prefix", null: false
    t.string "scopes", default: [], null: false, array: true
    t.datetime "last_used_at"
    t.datetime "revoked_at"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token_digest"], name: "index_personal_access_tokens_on_token_digest", unique: true
    t.index ["user_id", "revoked_at"], name: "index_personal_access_tokens_on_user_id_and_revoked_at"
    t.index ["user_id"], name: "index_personal_access_tokens_on_user_id"
  end

  create_table "pipes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.uuid "from_queue_id", null: false
    t.string "from_stage", null: false
    t.uuid "to_queue_id", null: false
    t.string "to_stage"
    t.jsonb "when_config", default: {}, null: false
    t.jsonb "transform_config", default: {}, null: false
    t.jsonb "limits", default: {}, null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["from_queue_id"], name: "index_pipes_on_from_queue_id"
    t.index ["slug"], name: "index_pipes_on_slug", unique: true
    t.index ["to_queue_id"], name: "index_pipes_on_to_queue_id"
  end

  create_table "reports", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "claim_id", null: false
    t.uuid "work_item_id", null: false
    t.string "stage_name", null: false
    t.integer "status", default: 0, null: false
    t.jsonb "body", default: {}, null: false
    t.text "blocked_question"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["claim_id"], name: "index_reports_on_claim_id"
    t.index ["work_item_id"], name: "index_reports_on_work_item_id"
  end

  create_table "stage_configs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "work_queue_id", null: false
    t.string "stage_name", null: false
    t.string "allowed_skills", default: [], null: false, array: true
    t.string "forbidden_skills", default: [], null: false, array: true
    t.integer "max_retries"
    t.string "escalation_target"
    t.jsonb "completion_criteria", default: [], null: false
    t.text "agent_prompt"
    t.string "model_override"
    t.integer "timeout_seconds"
    t.string "adapter_type", default: "fake", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "adapter_config", default: {}, null: false
    t.index ["work_queue_id", "stage_name"], name: "index_stage_configs_on_work_queue_id_and_stage_name", unique: true
    t.index ["work_queue_id"], name: "index_stage_configs_on_work_queue_id"
  end

  create_table "trace_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "trace_id", null: false
    t.integer "sequence", null: false
    t.string "event_type", null: false
    t.integer "tokens_in", default: 0, null: false
    t.integer "tokens_out", default: 0, null: false
    t.integer "cost_cents", default: 0, null: false
    t.integer "duration_ms", default: 0, null: false
    t.text "input_summary"
    t.text "output_summary"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["trace_id", "sequence"], name: "index_trace_events_on_trace_id_and_sequence"
    t.index ["trace_id"], name: "index_trace_events_on_trace_id"
  end

  create_table "traces", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "claim_id", null: false
    t.uuid "work_item_id", null: false
    t.string "stage_name", null: false
    t.string "agent_type", null: false
    t.string "model"
    t.integer "total_tokens_in", default: 0, null: false
    t.integer "total_tokens_out", default: 0, null: false
    t.integer "total_cost_cents", default: 0, null: false
    t.integer "total_duration_ms", default: 0, null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["claim_id"], name: "index_traces_on_claim_id"
    t.index ["work_item_id"], name: "index_traces_on_work_item_id"
  end

  create_table "transition_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "work_item_id", null: false
    t.string "from_stage"
    t.string "to_stage"
    t.string "trigger", null: false
    t.jsonb "details", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["work_item_id"], name: "index_transition_logs_on_work_item_id"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower((email)::text)", name: "index_users_on_lower_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "work_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "title", null: false
    t.string "spec_url", null: false
    t.uuid "work_queue_id", null: false
    t.string "stage_name", null: false
    t.integer "status", default: 0, null: false
    t.uuid "parent_id"
    t.integer "position"
    t.jsonb "tags", default: {}, null: false
    t.integer "retry_count", default: 0, null: false
    t.integer "regression_count", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "pipe_id"
    t.index ["parent_id"], name: "index_work_items_on_parent_id"
    t.index ["pipe_id"], name: "index_work_items_on_pipe_id"
    t.index ["status"], name: "index_work_items_on_status"
    t.index ["work_queue_id"], name: "index_work_items_on_work_queue_id"
    t.check_constraint "status >= 0 AND status <= 5", name: "work_items_status_check"
  end

  create_table "work_queues", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.jsonb "stages", default: [], null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "category"
    t.index ["slug"], name: "index_work_queues_on_slug", unique: true
  end

  add_foreign_key "artifacts", "claims"
  add_foreign_key "artifacts", "work_items"
  add_foreign_key "claims", "work_items"
  add_foreign_key "personal_access_tokens", "users"
  add_foreign_key "pipes", "work_queues", column: "from_queue_id"
  add_foreign_key "pipes", "work_queues", column: "to_queue_id"
  add_foreign_key "reports", "claims"
  add_foreign_key "reports", "work_items"
  add_foreign_key "stage_configs", "work_queues"
  add_foreign_key "trace_events", "traces"
  add_foreign_key "traces", "claims"
  add_foreign_key "traces", "work_items"
  add_foreign_key "transition_logs", "work_items"
  add_foreign_key "work_items", "pipes"
  add_foreign_key "work_items", "work_items", column: "parent_id"
  add_foreign_key "work_items", "work_queues"
end

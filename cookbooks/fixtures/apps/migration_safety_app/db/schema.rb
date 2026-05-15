ActiveRecord::Schema[8.0].define(version: 2024_01_01_000000) do
  create_table "orders", force: :cascade do |t|
    t.string "number", null: false
    t.decimal "total_cents", precision: 12, scale: 0, null: false, default: 0
    t.timestamps
  end
end

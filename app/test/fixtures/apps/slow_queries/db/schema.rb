ActiveRecord::Schema[8.0].define(version: 2026_05_05_070000) do
  create_table "authors", force: :cascade do |t|
    t.string "name", null: false
    t.timestamps
  end

  create_table "posts", force: :cascade do |t|
    t.bigint "author_id", null: false
    t.string "title", null: false
    t.string "status", null: false
    t.text "body"
    t.timestamps

    t.index ["author_id"], name: "index_posts_on_author_id"
  end

  create_table "comments", force: :cascade do |t|
    t.bigint "post_id", null: false
    t.text "body", null: false
    t.timestamps

    t.index ["post_id"], name: "index_comments_on_post_id"
  end

  create_table "wide_reports", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "title", null: false
    t.string "category"
    t.string "region"
    t.string "owner_email"
    t.jsonb "payload", default: {}, null: false
    t.text "internal_notes"
    t.timestamps

    t.index ["account_id"], name: "index_wide_reports_on_account_id"
  end
end

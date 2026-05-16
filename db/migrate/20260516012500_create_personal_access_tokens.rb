class CreatePersonalAccessTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :personal_access_tokens, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.string :token_digest, null: false
      t.string :token_prefix, null: false
      t.string :scopes, array: true, default: [], null: false
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.datetime :expires_at

      t.timestamps null: false
    end

    add_index :personal_access_tokens, :token_digest, unique: true
    add_index :personal_access_tokens, [:user_id, :revoked_at]
  end
end

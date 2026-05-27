class DropFlavortimeSessions < ActiveRecord::Migration[8.1]
  def change
    drop_table :flavortime_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :session_id
      t.integer :discord_shared_seconds, default: 0, null: false
      t.integer :discord_status_seconds, default: 0, null: false
      t.datetime :last_heartbeat_at, null: false
      t.datetime :expires_at, null: false
      t.datetime :ended_at
      t.string :platform
      t.string :app_version
      t.string :ended_reason
      t.timestamps

      t.index :expires_at
      t.index :session_id, unique: true
      t.index [ :user_id, :created_at ]
    end
  end
end

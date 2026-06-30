class AddStreakSyncedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :streak_synced_at, :datetime
  end
end

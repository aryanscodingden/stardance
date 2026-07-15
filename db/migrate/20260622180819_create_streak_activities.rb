class CreateStreakActivities < ActiveRecord::Migration[8.1]
  def change
    create_table :streak_activities do |t|
      t.references :user, null: false, foreign_key: true
      t.date :activity_date, null: false
      t.integer :coded_seconds, default: 0, null: false
      t.timestamps
    end

    add_index :streak_activities, [ :user_id, :activity_date ], unique: true
  end
end

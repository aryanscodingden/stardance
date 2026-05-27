class CreateVoteAssignments < ActiveRecord::Migration[8.1]
  def change
    create_table :vote_assignments do |t|
      t.references :user, null: false, foreign_key: true
      t.references :ship_event, null: false, foreign_key: { to_table: :post_ship_events }
      t.references :vote, foreign_key: true
      t.string :status, null: false, default: "assigned"

      t.timestamps
    end

    add_index :vote_assignments, [ :user_id, :ship_event_id ], unique: true
    add_index :vote_assignments, [ :user_id, :status ]
  end
end

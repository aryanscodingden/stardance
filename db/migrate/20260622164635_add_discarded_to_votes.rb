class AddDiscardedToVotes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :votes, :discarded, :boolean, null: false, default: false
    add_index :votes, [ :discarded, :ship_event_id ], algorithm: :concurrently
  end
end

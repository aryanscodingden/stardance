class AddUserRefToRsvps < ActiveRecord::Migration[8.1]
  def change
    add_column :rsvps, :user_ref, :string
  end
end

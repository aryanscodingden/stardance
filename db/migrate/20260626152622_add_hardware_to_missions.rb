class AddHardwareToMissions < ActiveRecord::Migration[8.1]
  def change
    add_column :missions, :hardware, :boolean, default: false, null: false
  end
end

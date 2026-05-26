class RemoveTutorialStepsCompletedFromUsers < ActiveRecord::Migration[8.1]
  def change
    safety_assured { remove_column :users, :tutorial_steps_completed, :string, array: true, default: [] }
  end
end

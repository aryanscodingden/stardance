class AddClaimingToMissionSubmissions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :mission_submissions, :claimed_at, :datetime
    add_column :mission_submissions, :claim_expires_at, :datetime
    add_index :mission_submissions, [ :status, :claim_expires_at ],
              name: "idx_mission_submissions_on_status_claim_expires",
              algorithm: :concurrently
  end
end

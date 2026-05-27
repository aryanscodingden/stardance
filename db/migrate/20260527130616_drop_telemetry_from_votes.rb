class DropTelemetryFromVotes < ActiveRecord::Migration[8.1]
  def up
    remove_index :votes, name: "index_votes_on_reason_quality_label"
    remove_index :votes, name: "index_votes_on_suspicious_and_created_at"
    remove_index :votes, name: "index_votes_on_verdict"

    safety_assured do
      remove_column :votes, :demo_url_clicked
      remove_column :votes, :repo_url_clicked
      remove_column :votes, :time_taken_to_vote
      remove_column :votes, :reason_quality_label
      remove_column :votes, :reason_quality_score
      remove_column :votes, :suspicious
      remove_column :votes, :verdict
    end
  end

  def down
    add_column :votes, :demo_url_clicked, :boolean, default: false
    add_column :votes, :repo_url_clicked, :boolean, default: false
    add_column :votes, :time_taken_to_vote, :integer
    add_column :votes, :reason_quality_label, :string
    add_column :votes, :reason_quality_score, :float
    add_column :votes, :suspicious, :boolean, default: false, null: false
    add_column :votes, :verdict, :string

    add_index :votes, :reason_quality_label
    add_index :votes, [ :suspicious, :created_at ]
    add_index :votes, :verdict
  end
end

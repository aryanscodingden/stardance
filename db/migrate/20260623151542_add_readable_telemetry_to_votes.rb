class AddReadableTelemetryToVotes < ActiveRecord::Migration[8.1]
  def up
    add_column :votes, :time_taken_to_vote_in_seconds, :integer
    add_column :votes, :demo_opened, :boolean, default: false, null: false
    add_column :votes, :repo_opened, :boolean, default: false, null: false

    safety_assured do
      execute <<~SQL.squish
        UPDATE votes
        SET
          time_taken_to_vote_in_seconds = telemetry.time_taken_to_vote_in_seconds,
          demo_opened = telemetry.demo_opened,
          repo_opened = telemetry.repo_opened
        FROM (
          SELECT
            votes.id AS vote_id,
            COALESCE(
              MAX((vote_events.properties->>'seconds_since_first_view')::integer)
                FILTER (
                  WHERE vote_events.event_type = 'vote_submitted'
                    AND vote_events.properties ? 'seconds_since_first_view'
                    AND vote_events.properties->>'seconds_since_first_view' ~ '^[0-9]+$'
                ),
              EXTRACT(EPOCH FROM (
                COALESCE(vote_assignments.submitted_at, votes.created_at) -
                vote_assignments.first_viewed_at
              ))::integer
            ) AS time_taken_to_vote_in_seconds,
            COALESCE(BOOL_OR(vote_events.event_type = 'vote_demo_opened'), false) AS demo_opened,
            COALESCE(BOOL_OR(vote_events.event_type = 'vote_repo_opened'), false) AS repo_opened
          FROM votes
          LEFT JOIN vote_assignments ON vote_assignments.vote_id = votes.id
          LEFT JOIN vote_events ON vote_events.vote_id = votes.id
          GROUP BY votes.id, vote_assignments.submitted_at, vote_assignments.first_viewed_at
        ) telemetry
        WHERE votes.id = telemetry.vote_id
      SQL
    end
  end

  def down
    remove_column :votes, :repo_opened
    remove_column :votes, :demo_opened
    remove_column :votes, :time_taken_to_vote_in_seconds
  end
end

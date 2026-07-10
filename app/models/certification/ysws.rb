# == Schema Information
#
# Table name: certification_ysws_reviews
#
#  id                    :bigint           not null, primary key
#  airtable_synced_at    :datetime
#  approved_minutes      :integer
#  claimed_at            :datetime
#  demo_checked_at       :datetime
#  in_unified_db         :string
#  original_minutes      :integer
#  repo_checked_at       :datetime
#  returned_at           :datetime
#  reviewed_at           :datetime
#  spotchecked_at        :datetime
#  summary_justification :text
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  claimed_by_id         :bigint
#  post_ship_event_id    :bigint           not null
#  project_id            :bigint           not null
#  reviewer_id           :bigint
#  ship_cert_id          :bigint
#  spotchecked_by_id     :bigint
#  user_id               :bigint           not null
#
# Indexes
#
#  index_certification_ysws_reviews_on_claimed_by_id       (claimed_by_id)
#  index_certification_ysws_reviews_on_post_ship_event_id  (post_ship_event_id)
#  index_certification_ysws_reviews_on_project_id          (project_id)
#  index_certification_ysws_reviews_on_reviewer_id         (reviewer_id)
#  index_certification_ysws_reviews_on_ship_cert_id        (ship_cert_id)
#  index_certification_ysws_reviews_on_spotchecked_by_id   (spotchecked_by_id)
#  index_certification_ysws_reviews_on_user_id             (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (claimed_by_id => users.id)
#  fk_rails_...  (post_ship_event_id => post_ship_events.id)
#  fk_rails_...  (project_id => projects.id)
#  fk_rails_...  (reviewer_id => users.id)
#  fk_rails_...  (ship_cert_id => certification_ship_reviews.id)
#  fk_rails_...  (spotchecked_by_id => users.id)
#  fk_rails_...  (user_id => users.id)
#
module Certification
  class Ysws < ApplicationRecord
    self.table_name = "certification_ysws_reviews"

    belongs_to :reviewer, class_name: "User", optional: true
    belongs_to :user
    belongs_to :project, -> { with_deleted }, optional: true
    belongs_to :ship_cert, class_name: "Certification::Ship", optional: true
    belongs_to :post_ship_event, class_name: "Post::ShipEvent"
    belongs_to :spotchecked_by, class_name: "User", optional: true
    belongs_to :claimed_by, class_name: "User", optional: true

    has_many :devlog_reviews, class_name: "Certification::Devlog", foreign_key: :ysws_review_id, dependent: :destroy

    validates :original_minutes, numericality: { greater_than_or_equal_to: 0 }, allow_nil: false
    validates :approved_minutes, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

    MIN_APPROVED_MINUTES = 6

    # How long a reviewer's claim on a review holds before it's up for grabs
    # again. There's no separate expiry column — expiry is just claimed_at + TTL.
    CLAIM_TTL = 20.minutes

    # ---- Review-queue scopes ---------------------------------------------

    scope :pending, -> { where(reviewed_at: nil, returned_at: nil) }

    # A review is visible to a reviewer if nobody holds an active claim on it,
    # or they're the one holding it.
    scope :unclaimed_or_claimed_by, ->(user) {
      where("claimed_by_id IS NULL OR claimed_at IS NULL OR claimed_at < :expired OR claimed_by_id = :user_id",
            expired: CLAIM_TTL.ago, user_id: user.id)
    }

    # Correlated subquery counting a review's still-pending child devlog
    # reviews — the "todo" work left on it. Reused by the count select and the
    # "todo" column sort so they stay in sync.
    TODO_DEVLOG_COUNT_SQL = <<~SQL.squish.freeze
      (SELECT COUNT(*) FROM certification_devlog_reviews
        WHERE certification_devlog_reviews.ysws_review_id = certification_ysws_reviews.id
          AND certification_devlog_reviews.status = 'pending')
    SQL

    # Exposes a `todo_devlog_count` attribute on each loaded record without an
    # N+1 — read it via #todo_devlog_count.
    scope :with_todo_devlog_count, -> {
      select("certification_ysws_reviews.*", "#{TODO_DEVLOG_COUNT_SQL} AS todo_devlog_count")
    }

    scope :by_project_type, ->(type) {
      type == "unclassified" \
        ? joins(:project).where(projects: { project_type: nil })
        : joins(:project).where(projects: { project_type: type })
    }

    # Claims (or refreshes an existing claim on) a pending review for the
    # given user, unless someone else already holds an active claim on it.
    # Conditioned atomically in the UPDATE itself so two reviewers opening the
    # same review at once can't both win the claim. Returns the claimed
    # record, or nil if another reviewer's claim is still active.
    def self.atomic_claim!(record_id, user)
      now = Time.current
      updated = pending.where(id: record_id)
        .where("claimed_by_id IS NULL OR claimed_at IS NULL OR claimed_at < :expired OR claimed_by_id = :user_id",
               expired: CLAIM_TTL.ago, user_id: user.id)
        .update_all(claimed_by_id: user.id, claimed_at: now, updated_at: now)
      updated.zero? ? nil : find(record_id)
    end

    # Count of still-pending child devlog reviews. Available only on records
    # loaded through .with_todo_devlog_count.
    def todo_devlog_count
      self[:todo_devlog_count].to_i
    end

    # Estimated stardust a reviewer would earn per reviewed devlog. YSWS
    # reviewing isn't a real payout source yet (no stardust_earned column), so
    # the dashboard leaderboard uses this to show a projected payout.
    STARDUST_PER_DEVLOG = 0.2

    # Default per-reviewer target for completed devlog reviews. Shown as a
    # "reviews left until goal reached" widget on the review queue.
    DEFAULT_DEVLOG_REVIEW_GOAL = 222

    # Limited-time bonus rate: devlogs whose parent review was completed within
    # BONUS_WINDOW pay out at this higher rate instead of STARDUST_PER_DEVLOG.
    BONUS_STARDUST_PER_DEVLOG = 0.3

    # 11am EDT July 9 2026 → 4pm EDT July 13 2026 (uses the New York zone so the
    # EDT offset is applied correctly regardless of the app's default zone).
    BONUS_WINDOW = Time.find_zone!("America/New_York").local(2026, 7, 9, 11, 0)..
      Time.find_zone!("America/New_York").local(2026, 7, 13, 16, 0)

    # All-time devlog-review leaderboard. A devlog counts as reviewed once its
    # parent YSWS review is completed (reviewed_at present); completion already
    # forces every child devlog out of :pending. Devlogs reviewed within
    # BONUS_WINDOW pay out at the higher BONUS_STARDUST_PER_DEVLOG rate.
    #   => [{ reviewer_id:, name:, devlogs:, stardust: }, ...] desc by devlogs
    def self.reviewer_devlog_leaderboard
      bonus_sql = sanitize_sql_array([
        "certification_ysws_reviews.reviewed_at BETWEEN ? AND ?",
        BONUS_WINDOW.begin, BONUS_WINDOW.end
      ])

      # Count devlogs per reviewer, split by whether they fall in the bonus
      # window, so each bucket can be paid out at its own rate.
      Certification::Devlog
        .joins(ysws_review: :reviewer)
        .where.not(certification_ysws_reviews: { reviewed_at: nil })
        .group("users.id", "users.display_name", Arel.sql("(#{bonus_sql})"))
        .count
        .group_by { |(reviewer_id, name, _bonus), _count| [ reviewer_id, name ] }
        .map do |(reviewer_id, name), entries|
          devlogs  = entries.sum { |_key, count| count }
          stardust = entries.sum do |(_id, _name, bonus), count|
            count * (bonus ? BONUS_STARDUST_PER_DEVLOG : STARDUST_PER_DEVLOG)
          end
          {
            reviewer_id: reviewer_id,
            name: name,
            devlogs: devlogs,
            stardust: stardust.round(1)
          }
        end
        .sort_by { |row| [ -row[:devlogs], row[:name] ] }
    end

    # All-time count of devlogs a given reviewer has reviewed. A devlog counts
    # as reviewed once its parent YSWS review is completed (reviewed_at present),
    # matching the leaderboard's definition.
    def self.reviewer_devlog_count(reviewer_id)
      Certification::Devlog
        .joins(:ysws_review)
        .where.not(certification_ysws_reviews: { reviewed_at: nil })
        .where(certification_ysws_reviews: { reviewer_id: reviewer_id })
        .count
    end

    # Devlogs reviewed per reviewer per day over the trailing window, bucketed by
    # the parent review's reviewed_at. Shape is the contract the chart relies on:
    #   => { labels: ["6/1", ...], series: [{ name:, data: [n, ...] }, ...] }
    def self.reviewer_daily_devlog_data(days: 30, now: Time.current)
      start = (now.to_date - (days - 1)).to_time.beginning_of_day

      rows = Certification::Devlog
        .joins(ysws_review: :reviewer)
        .where(certification_ysws_reviews: { reviewed_at: start.. })
        .group("users.id", "users.display_name", Arel.sql("DATE(certification_ysws_reviews.reviewed_at)"))
        .count

      dates  = (0...days).map { |i| now.to_date - (days - 1 - i) }
      labels = dates.map { |d| d.strftime("%-m/%-d") }

      series = rows
        .group_by { |(reviewer_id, name, _day), _count| [ reviewer_id, name ] }
        .sort_by { |_key, entries| -entries.sum { |_key, count| count } }
        .map do |(_reviewer_id, name), entries|
          per_day = entries.to_h { |(_id, _name, day), count| [ day.to_date, count ] }
          { name: name, data: dates.map { |d| per_day[d].to_i } }
        end

      { labels: labels, series: series }
    end

    def pending?
      reviewed_at.nil? && returned_at.nil?
    end

    def claim_active?
      claimed_by_id.present? && claimed_at.present? && claimed_at > CLAIM_TTL.ago
    end

    def claimed_by?(user)
      claim_active? && claimed_by_id == user.id
    end

    def approved_minutes_total
      devlog_reviews.sum { |dr| dr.approved_minutes.to_i }
    end

    def review_rejected?
      user.banned? || approved_minutes_total < MIN_APPROVED_MINUTES
    end

    def review_status
      return :in_unified_db if in_unified_db.present?
      return :returned if returned_at.present?
      return :pending unless reviewed_at.present?

      review_rejected? ? :rejected : :approved
    end

    def check_and_update_unified_db_status!
      api_key  = Rails.application.credentials.dig(:ysws_review, :airtable_api_key) ||
                 Rails.application.credentials&.airtable&.api_key ||
                 ENV["AIRTABLE_API_KEY"]
      base_id  = Rails.application.credentials.dig(:ysws_review, :airtable_base_id) ||
                 ENV["YSWS_REVIEW_AIRTABLE_BASE_ID"]
      tbl_name = Rails.application.credentials.dig(:ysws_review, :airtable_table_name) ||
                 ENV["YSWS_REVIEW_AIRTABLE_TABLE"] ||
                 "YSWS Project Submission"

      table = Norairrecord.table(api_key, base_id, tbl_name)
      record = table.all(filter: "{review_id} = '#{id}'").first
      unified_record_id = record&.[]("Automation - YSWS Record ID").presence

      update_column(:in_unified_db, unified_record_id) if unified_record_id.present? && in_unified_db != unified_record_id
    rescue Faraday::Error => e
      Rails.logger.warn "[Certification::Ysws] Could not check unified DB status for ##{id}: #{e.message}"
    end
  end
end

# frozen_string_literal: true

module TimelinePostPreloading
  extend ActiveSupport::Concern

  private

  def preload_timeline_postables(posts)
    grouped = posts.group_by(&:postable_type)

    preload_timeline_group(grouped["Post::Devlog"], postable: :attachments_attachments)
    preload_timeline_group(
      grouped["Post::ShipEvent"],
      postable: [ :attachments_attachments, { mission_submission: :mission } ]
    )
    preload_timeline_group(grouped[Post::PRIVATE_SHIP_DECISION_TYPE], postable: :reviewer)
  end

  def preload_timeline_group(records, associations)
    return if records.blank?

    ActiveRecord::Associations::Preloader
      .new(records: records, associations: associations)
      .call
  end
end

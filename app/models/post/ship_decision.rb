# frozen_string_literal: true

# == Schema Information
#
# Table name: certification_ship_reviews
#
#  id               :bigint           not null, primary key
#  claim_expires_at :datetime
#  claimed_at       :datetime
#  decided_at       :datetime
#  feedback         :text
#  internal_reason  :text
#  lock_version     :integer          default(0), not null
#  recert_reason    :text
#  stardust_earned  :integer
#  status           :integer          default("pending"), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  project_id       :bigint           not null
#  returned_by_id   :bigint
#  reviewer_id      :bigint
#
# Indexes
#
#  idx_on_status_claim_expires_at_c7a5e87a52        (status,claim_expires_at)
#  index_certification_ship_reviews_on_decided_at   (decided_at)
#  index_certification_ship_reviews_on_reviewer_id  (reviewer_id)
#  index_ship_reviews_unique_pending_project        (project_id) UNIQUE WHERE (status = 0)
#
# Foreign Keys
#
#  fk_rails_...  (project_id => projects.id)
#  fk_rails_...  (reviewer_id => users.id)
#
class Post::ShipDecision < Certification::Ship
  include Postable

  def verdict = status

  def decided_on = decided_at || updated_at
end

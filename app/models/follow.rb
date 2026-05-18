# == Schema Information
#
# Table name: follows
#
#  id          :bigint           not null, primary key
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  followed_id :bigint           not null
#  follower_id :bigint           not null
#
# Indexes
#
#  index_follows_on_followed_id                  (followed_id)
#  index_follows_on_follower_id                  (follower_id)
#  index_follows_on_follower_id_and_followed_id  (follower_id,followed_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (followed_id => users.id)
#  fk_rails_...  (follower_id => users.id)
#
class Follow < ApplicationRecord
  belongs_to :follower, class_name: "User"
  belongs_to :followed, class_name: "User"

  validates :follower_id, uniqueness: { scope: :followed_id }
  validate :not_self_follow

  after_create_commit :notify_followed

  private

  def not_self_follow
    return unless follower_id.present? && follower_id == followed_id

    errors.add(:followed_id, "can't follow yourself")
  end

  def notify_followed
    return unless followed.send_notifications_for_new_followers? && followed.slack_id.present?

    followed.dm_user("✨ <@#{follower.slack_id}> just started following you on Stardance!")
  end
end

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
require "test_helper"

class FollowTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @alice = create_user(slack_id: "U_ALICE", display_name: "alice")
    @bob   = create_user(slack_id: "U_BOB",   display_name: "bob")
  end

  test "follow creates link between two users" do
    follow = Follow.new(follower: @alice, followed: @bob)
    assert follow.save
  end

  test "rejects duplicate follows at the model level" do
    Follow.create!(follower: @alice, followed: @bob)
    duplicate = Follow.new(follower: @alice, followed: @bob)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:follower_id], "has already been taken"
  end

  test "rejects self-follow" do
    follow = Follow.new(follower: @alice, followed: @alice)
    assert_not follow.valid?
    assert_includes follow.errors[:followed_id], "can't follow yourself"
  end

  test "fires Slack DM to followed user when notifications enabled" do
    @bob.update!(send_notifications_for_new_followers: true)
    assert_enqueued_with(job: SendSlackDmJob) do
      Follow.create!(follower: @alice, followed: @bob)
    end
  end

  test "does not fire Slack DM if followed user opted out" do
    @bob.update!(send_notifications_for_new_followers: false)
    assert_no_enqueued_jobs(only: SendSlackDmJob) do
      Follow.create!(follower: @alice, followed: @bob)
    end
  end

  private

  def create_user(slack_id:, display_name:)
    User.create!(slack_id: slack_id, display_name: display_name, email: "#{display_name}@example.test")
  end
end

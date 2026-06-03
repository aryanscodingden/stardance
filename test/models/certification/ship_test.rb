# frozen_string_literal: true

require "test_helper"

class Certification::ShipTest < ActiveSupport::TestCase
  setup do
    Flipper.disable(:week_1_release)

    @owner = create_user(slack_id: "U_SHIP_OWNER", display_name: "shipowner")
    @owner.update!(slack_id: nil, verification_status: "verified")
    @reviewer = create_user(slack_id: "U_SHIP_REVIEWER", display_name: "shipreviewer")
    @outsider = create_user(slack_id: "U_SHIP_OUTSIDER", display_name: "shipoutsider")
    @contributor = create_user(slack_id: "U_SHIP_CONTRIBUTOR", display_name: "shipcontributor")

    @project = Project.create!(
      title: "Visible Verdicts",
      description: "A project with review feedback",
      ship_status: "submitted"
    )
    @project.memberships.create!(user: @owner, role: :owner)
    @project.memberships.create!(user: @contributor, role: :contributor)
  end

  teardown do
    Flipper.disable(:week_1_release)
  end

  test "a verdict posts a private decision card to the project timeline" do
    Flipper.enable(:week_1_release)
    review = @project.ship_reviews.create!(status: :pending)

    assert_difference -> { Post.where(postable_type: Post::PRIVATE_SHIP_DECISION_TYPE).count }, 1 do
      review.update!(status: :returned, feedback: "Tighten the demo video.", reviewer: @reviewer)
    end

    post = Post.find_by!(postable_type: Post::PRIVATE_SHIP_DECISION_TYPE, postable_id: review.id)
    decision = post.postable

    assert_equal @owner, post.user
    assert_equal @project, post.project
    assert_instance_of Post::ShipDecision, decision
    assert_equal "returned", decision.verdict
    assert_equal "Tighten the demo video.", decision.feedback
    assert Post.visible_to(@owner).where(id: post.id).exists?
    assert Post.visible_to(@contributor).where(id: post.id).exists?
    assert_not Post.visible_to(@outsider).where(id: post.id).exists?
    assert_not Post.visible_to(nil).where(id: post.id).exists?
    assert_not Post.authored_by_verified.where(id: post.id).exists?
    assert Gorse::PostPayload.new(post).hidden?

    Flipper.disable(:week_1_release)
    assert_not Post.visible_to(@owner).where(id: post.id).exists?
  end

  test "an approved verdict posts a private decision card" do
    Flipper.enable(:week_1_release)
    review = @project.ship_reviews.create!(status: :pending)

    assert_difference -> { Post.where(postable_type: Post::PRIVATE_SHIP_DECISION_TYPE).count }, 1 do
      review.update!(status: :approved, feedback: "Ready for voting.", reviewer: @reviewer)
    end

    post = Post.find_by!(postable_type: Post::PRIVATE_SHIP_DECISION_TYPE, postable_id: review.id)

    assert_equal "approved", post.postable.verdict
    assert_equal "Ready for voting.", post.postable.feedback
    assert_equal @reviewer, post.postable.reviewer
  end

  test "later verdict changes reuse the same decision card" do
    Flipper.enable(:week_1_release)
    review = @project.ship_reviews.create!(status: :pending)

    review.update!(status: :returned, feedback: "Tighten the demo video.", reviewer: @reviewer)
    post = Post.find_by!(postable_type: Post::PRIVATE_SHIP_DECISION_TYPE, postable_id: review.id)

    assert_no_difference -> { Post.where(postable_type: Post::PRIVATE_SHIP_DECISION_TYPE).count } do
      review.update!(status: :approved, feedback: "Ready for voting.")
    end

    decision_post = Post.find_by!(
      postable_type: Post::PRIVATE_SHIP_DECISION_TYPE,
      postable_id: review.id
    )

    assert_equal post.id, decision_post.id
    assert_equal "approved", post.reload.postable.verdict
    assert_equal "Ready for voting.", post.postable.feedback
  end

  test "a verdict does not post a decision card while the release flag is off" do
    review = @project.ship_reviews.create!(status: :pending)

    assert_no_difference -> { Post.where(postable_type: Post::PRIVATE_SHIP_DECISION_TYPE).count } do
      review.update!(status: :returned, feedback: "Tighten the demo video.", reviewer: @reviewer)
    end
  end

  test "a pending review does not post a decision card" do
    Flipper.enable(:week_1_release)

    assert_no_difference -> { Post.where(postable_type: Post::PRIVATE_SHIP_DECISION_TYPE).count } do
      @project.ship_reviews.create!(status: :pending, reviewer: @reviewer)
    end
  end
end

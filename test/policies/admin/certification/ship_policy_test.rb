require "test_helper"

class Admin::Certification::ShipPolicyTest < ActiveSupport::TestCase
  setup do
    @reviewer = create_user(slack_id: "U_SHIP_POLICY_REVIEWER", display_name: "ship_policy_reviewer")
    @reviewer.update!(granted_roles: [ "project_certifier" ])
  end

  test "show? is false for a reviewer's own project" do
    ship = ship_for_project(member: @reviewer)

    refute Admin::Certification::ShipPolicy.new(@reviewer, ship).show?
  end

  test "show? is true for another user's project" do
    owner = create_user(slack_id: "U_SHIP_POLICY_OWNER", display_name: "ship_policy_owner")
    ship = ship_for_project(member: owner)

    assert Admin::Certification::ShipPolicy.new(@reviewer, ship).show?
  end

  private

  def ship_for_project(member:)
    project = Project.create!(
      title: "Ship policy project #{SecureRandom.hex(4)}",
      description: "Test project"
    )
    Project::Membership.create!(project:, user: member)
    Certification::Ship.create!(project:)
  end
end

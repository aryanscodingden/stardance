require "test_helper"

class Mission::MigrateProjectsToHardwareJobTest < ActiveJob::TestCase
  setup do
    @mission = create_mission
    @software = Project.create!(title: "Software project")
    @hardware = Project.create!(title: "Hardware project", hardware_stage: "build")
    @software.mission_attachments.create!(mission: @mission)
    @hardware.mission_attachments.create!(mission: @mission)
  end

  test "converts attached software projects to the design stage" do
    @mission.update!(hardware: true)

    Mission::MigrateProjectsToHardwareJob.perform_now(@mission.id)

    assert_equal "design", @software.reload.hardware_stage
  end

  test "leaves already-hardware projects untouched" do
    @mission.update!(hardware: true)

    Mission::MigrateProjectsToHardwareJob.perform_now(@mission.id)

    assert_equal "build", @hardware.reload.hardware_stage
  end

  test "ignores detached projects" do
    @software.current_mission_attachment.detach!
    @mission.update!(hardware: true)

    Mission::MigrateProjectsToHardwareJob.perform_now(@mission.id)

    assert_nil @software.reload.hardware_stage
  end

  test "flipping the mission to hardware enqueues the migration" do
    assert_enqueued_with(job: Mission::MigrateProjectsToHardwareJob) do
      @mission.update!(hardware: true)
    end
  end

  test "flipping the mission back to software does not enqueue" do
    @mission.update!(hardware: true)

    assert_no_enqueued_jobs only: Mission::MigrateProjectsToHardwareJob do
      @mission.update!(hardware: false)
    end
  end
end

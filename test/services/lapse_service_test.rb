require "test_helper"

class LapseServiceTest < ActiveSupport::TestCase
  test "timelapses_for_project returns [] for a blank hackatime id without hitting the network" do
    assert_equal [], LapseService.timelapses_for_project(hackatime_user_id: nil, project_keys: %w[foo])
    assert_equal [], LapseService.timelapses_for_project(hackatime_user_id: "", project_keys: %w[foo])
  end

  test "timelapses_for_project returns [] for blank project keys without hitting the network" do
    assert_equal [], LapseService.timelapses_for_project(hackatime_user_id: "123", project_keys: [])
    assert_equal [], LapseService.timelapses_for_project(hackatime_user_id: "123", project_keys: nil)
  end

  test "timelapses_for_project returns [] when every key is blank, without hitting the network" do
    assert_equal [], LapseService.timelapses_for_project(hackatime_user_id: "123", project_keys: [ "", nil, "  " ])
  end
end

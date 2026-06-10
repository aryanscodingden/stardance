require "test_helper"

class ContributorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Flipper.enable(:week_2_release)
  end

  teardown do
    Flipper.disable(:week_2_release)
  end

  test "index responds not found when week_2_release is not enabled" do
    Flipper.disable(:week_2_release)

    get contributors_path

    assert_response :not_found
  end

  test "index is publicly accessible and shows contributors with their counts" do
    leaderboard = [
      {
        login: "alice",
        avatar_url: "https://example.com/a.png",
        url: "https://github.com/alice",
        merged_pr_count: 5
      }
    ]

    stub_leaderboard(leaderboard) do
      get contributors_path
    end

    assert_response :success
    assert_includes response.body, "alice"
    assert_includes response.body, "5"
  end

  test "index shows an unavailable message when the leaderboard is empty" do
    stub_leaderboard([]) do
      get contributors_path
    end

    assert_response :success
    assert_includes response.body, "unavailable"
  end

  private

  # Minitest 6 dropped Object#stub (extracted to the minitest-mock gem),
  # so stub GithubContributors.leaderboard by hand.
  def stub_leaderboard(leaderboard)
    GithubContributors.singleton_class.alias_method :original_leaderboard, :leaderboard
    GithubContributors.define_singleton_method(:leaderboard) { leaderboard }
    yield
  ensure
    GithubContributors.singleton_class.alias_method :leaderboard, :original_leaderboard
    GithubContributors.singleton_class.remove_method :original_leaderboard
  end
end

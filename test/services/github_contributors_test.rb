require "test_helper"

class GithubContributorsTest < ActiveSupport::TestCase
  test "build_leaderboard excludes bots, counts merged PRs, and carries through author fields" do
    pulls = [
      pull(number: 1, login: "alice"),
      pull(number: 2, login: "alice"),
      pull(number: 3, login: "alice"),
      pull(number: 4, login: "bob"),
      pull(number: 5, login: "dependabot[bot]"),
      pull(number: 6, login: "dependabot[bot]")
    ]

    leaderboard = GithubContributors.build_leaderboard(pulls)

    assert_equal 2, leaderboard.size
    assert_not leaderboard.any? { |entry| entry[:login] == "dependabot[bot]" }

    alice, bob = leaderboard

    assert_equal "alice", alice[:login]
    assert_equal 3, alice[:merged_pr_count]
    assert_equal "https://avatars.example.com/alice.png", alice[:avatar_url]
    assert_equal "https://github.com/alice", alice[:url]

    assert_equal "bob", bob[:login]
    assert_equal 1, bob[:merged_pr_count]
    assert_equal "https://avatars.example.com/bob.png", bob[:avatar_url]
    assert_equal "https://github.com/bob", bob[:url]
  end

  test "build_leaderboard breaks count ties by login case-insensitively" do
    pulls = [
      pull(number: 1, login: "Zelda"),
      pull(number: 2, login: "apple"),
      pull(number: 3, login: "Banana"),
      pull(number: 4, login: "Banana")
    ]

    leaderboard = GithubContributors.build_leaderboard(pulls)

    assert_equal %w[Banana apple Zelda], leaderboard.map { |entry| entry[:login] }
    assert_equal [ 2, 1, 1 ], leaderboard.map { |entry| entry[:merged_pr_count] }
  end

  private

  def pull(number:, login:)
    {
      number: number,
      author_login: login,
      author_avatar_url: "https://avatars.example.com/#{login}.png",
      author_url: "https://github.com/#{login}",
      merged_at: Time.utc(2026, 6, 1)
    }
  end
end

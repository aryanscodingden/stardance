module VotingFactory
  def create_eligible_voter
    user = create_voting_user
    project = Project.create!(title: "Voter project #{SecureRandom.hex(4)}")
    Project::Membership.create!(project: project, user: user, role: :owner)
    ship_event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true, certification_status: "approved", hours_at_ship: 1)
    Post.create!(project: project, user: user, postable: ship_event)
    ship_event.update!(hours_at_ship: 1)
    user.update!(vote_balance: -1)
    user
  end

  def create_voting_user
    create_user(
      slack_id: "U#{SecureRandom.hex(8)}",
      display_name: "voter#{SecureRandom.hex(5)}"
    ).tap { |user| user.update!(verification_status: "verified", vote_balance: -1) }
  end

  def create_voteable_ship_event(demo_url: "https://demo.example.com", repo_url: "https://github.com/acme/project")
    owner = create_user(slack_id: "U#{SecureRandom.hex(8)}", display_name: "owner#{SecureRandom.hex(5)}")
    project = Project.create!(
      title: "Vote target #{SecureRandom.hex(4)}",
      demo_url: demo_url,
      repo_url: repo_url
    )
    Project::Membership.create!(project: project, user: owner, role: :owner)

    ship_event = Post::ShipEvent.create!(
      body: "Ship it",
      uploading_attachments: true,
      certification_status: "approved",
      hours_at_ship: 1
    )
    Post.create!(project: project, user: owner, postable: ship_event)
    ship_event.update!(hours_at_ship: 1)
    ship_event
  end
end

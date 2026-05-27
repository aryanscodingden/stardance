require "test_helper"

class Onboarding::WizardControllerTest < ActionDispatch::IntegrationTest
  test "POST /onboarding/start with valid email creates a guest user and redirects to welcome" do
    assert_difference "User.count", 1 do
      post onboarding_start_path, params: { email: "fresh@example.com" }
    end
    assert_redirected_to onboarding_welcome_path

    user = User.find_by(email: "fresh@example.com")
    assert_not_nil user
    assert user.guest?
    assert_nil user.onboarded_at
    assert_equal user.id, session[:user_id]
  end

  test "POST /onboarding/start with invalid email re-renders root with alert and creates no user" do
    assert_no_difference "User.count" do
      post onboarding_start_path, params: { email: "not-an-email" }
    end
    assert_redirected_to root_path
    assert_nil session[:user_id]
  end

  test "POST /onboarding/start signs in an existing guest with that email and skips the wizard" do
    existing = User.create!(email: "returning@example.com", display_name: "Returning Guest")

    assert_no_difference "User.count" do
      post onboarding_start_path, params: { email: "returning@example.com" }
    end
    assert_redirected_to home_path
    assert_equal existing.id, session[:user_id]
  end

  test "GET /onboarding/welcome without a signed-in guest redirects to root" do
    get onboarding_welcome_path
    assert_redirected_to root_path
  end

  test "POST /onboarding/birthday with teen_13_18 sets attestation on the user" do
    post onboarding_start_path, params: { email: "teen@example.com" }
    post onboarding_birthday_path, params: { attestation: "teen_13_18" }

    assert_redirected_to onboarding_experience_path
    assert_equal "teen_13_18", User.find_by(email: "teen@example.com").age_attestation
  end

  test "POST /onboarding/birthday with ineligible destroys the guest and routes to age-gate" do
    post onboarding_start_path, params: { email: "tooold@example.com" }

    assert_difference "User.count", -1 do
      post onboarding_birthday_path, params: { attestation: "ineligible" }
    end
    assert_redirected_to onboarding_age_gate_path
    assert_nil session[:user_id]
    assert_nil User.find_by(email: "tooold@example.com")
  end

  test "experience step gated when no teen attestation" do
    post onboarding_start_path, params: { email: "x@example.com" }
    get onboarding_experience_path
    assert_redirected_to onboarding_birthday_path
  end

  test "interests step accepts the 'I don't know' sentinel and routes to result" do
    post onboarding_start_path,    params: { email: "skip@example.com" }
    post onboarding_birthday_path, params: { attestation: "teen_13_18" }
    post onboarding_experience_path, params: { level: "little" }
    post onboarding_interests_path, params: { interests: [ User::INTERESTS_UNKNOWN, "web_dev" ] }

    assert_redirected_to onboarding_interests_result_path
    assert_equal [ User::INTERESTS_UNKNOWN ], User.find_by(email: "skip@example.com").interests
  end

  test "full happy path populates the existing guest and redirects to complete" do
    assert_difference "User.count", 1 do
      post onboarding_start_path, params: { email: "happy@example.com" }
    end

    post onboarding_birthday_path,   params: { attestation: "teen_13_18" }
    post onboarding_experience_path, params: { level: "some" }
    post onboarding_interests_path,  params: { interests: %w[web_dev hardware] }

    assert_no_difference "User.count" do
      post onboarding_name_path, params: { display_name: "Happy Hacker" }
    end

    assert_redirected_to home_path(welcome: 1)
    user = User.find_by(email: "happy@example.com")
    assert_equal "Happy Hacker", user.display_name
    assert_equal "teen_13_18", user.age_attestation
    assert_equal "some", user.experience_level
    assert_equal %w[web_dev hardware], user.interests
    assert user.onboarded?
    assert user.guest?
    assert_equal user.id, session[:user_id]
  end
end

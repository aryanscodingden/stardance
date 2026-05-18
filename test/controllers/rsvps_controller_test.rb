require "test_helper"

class RsvpsControllerTest < ActionDispatch::IntegrationTest
  test "confirm with a valid token stamps click_confirmed_at" do
    rsvp = Rsvp.create!(email: "fan@example.com")

    get confirm_rsvp_url(token: rsvp.confirmation_token)

    assert_redirected_to root_path
    assert_not_nil rsvp.reload.click_confirmed_at
  end

  test "confirm with an unknown token is a no-op redirect" do
    get confirm_rsvp_url(token: "not-a-real-token")

    assert_redirected_to root_path
  end

  test "confirm is idempotent" do
    rsvp = Rsvp.create!(email: "again@example.com")
    get confirm_rsvp_url(token: rsvp.confirmation_token)
    first = rsvp.reload.click_confirmed_at

    travel 1.minute do
      get confirm_rsvp_url(token: rsvp.confirmation_token)
    end

    assert_equal first, rsvp.reload.click_confirmed_at
  end

  test "create sets a user_ref token in flash for a fresh RSVP" do
    post rsvps_url, params: { rsvp: { email: "fresh@example.com" } }

    assert_redirected_to root_path
    assert flash[:user_ref_token].present?
  end

  test "create does not set flash token on duplicate email" do
    Rsvp.create!(email: "returning@example.com")
    post rsvps_url, params: { rsvp: { email: "returning@example.com" } }

    assert_redirected_to root_path
    assert_nil flash[:user_ref_token]
  end

  test "user_ref updates the rsvp with a preset option" do
    rsvp = Rsvp.create!(email: "picker@example.com")
    token = rsvp.signed_id(purpose: :user_ref, expires_in: 1.hour)

    patch user_ref_rsvps_url, params: { token: token, user_ref: "GitHub" }

    assert_redirected_to root_path
    assert_equal "GitHub", rsvp.reload.user_ref
  end

  test "user_ref stores the free-text value when Other is selected" do
    rsvp = Rsvp.create!(email: "other@example.com")
    token = rsvp.signed_id(purpose: :user_ref, expires_in: 1.hour)

    patch user_ref_rsvps_url, params: { token: token, user_ref: "Other", user_ref_other: "Reddit" }

    assert_equal "Reddit", rsvp.reload.user_ref
  end

  test "user_ref redirects with alert on invalid token" do
    patch user_ref_rsvps_url, params: { token: "not-a-real-token", user_ref: "GitHub" }

    assert_redirected_to root_path
    assert_equal "That referral link expired.", flash[:alert]
  end

  test "user_ref truncates Other free-text input to 100 chars" do
    rsvp = Rsvp.create!(email: "long@example.com")
    token = rsvp.signed_id(purpose: :user_ref, expires_in: 1.hour)
    long_value = "x" * 500

    patch user_ref_rsvps_url, params: { token: token, user_ref: "Other", user_ref_other: long_value }

    assert_equal 100, rsvp.reload.user_ref.length
  end

  test "user_ref token cannot be reused after a successful update" do
    rsvp = Rsvp.create!(email: "replay@example.com")
    token = rsvp.signed_id(purpose: :user_ref, expires_in: 1.hour)

    patch user_ref_rsvps_url, params: { token: token, user_ref: "GitHub" }
    assert_equal "GitHub", rsvp.reload.user_ref

    patch user_ref_rsvps_url, params: { token: token, user_ref: "Teacher" }
    assert_equal "GitHub", rsvp.reload.user_ref
    assert_equal "Already recorded — thanks!", flash[:notice]
  end
end

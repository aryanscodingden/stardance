module Onboarding
  class GuestBannerComponent < ViewComponent::Base
    GRACE_PERIOD = 1.day

    def render?
      return false if helpers.controller.is_a?(LandingController)

      visitor? || stale_guest?
    end

    def visitor?
      helpers.current_user.nil?
    end

    private

    def stale_guest?
      user = helpers.current_user
      user&.guest? && user.created_at < GRACE_PERIOD.ago
    end
  end
end

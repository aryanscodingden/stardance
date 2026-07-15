class ShipEventPayoutRefreshJob < ApplicationJob
  queue_as :default

  def perform
    Post::ShipEvent.refresh_payouts!
  end
end

module User::Certificates
  extend ActiveSupport::Concern

  included do
    has_one :certificate, dependent: :destroy
  end

  def approved_ship_hours
    Post.approved_ship_events_by(self).sum("post_ship_events.hours_at_ship")
  end

  def certificate_eligible?
    approved_ship_hours >= Certificate::REQUIRED_APPROVED_HOURS
  end
end

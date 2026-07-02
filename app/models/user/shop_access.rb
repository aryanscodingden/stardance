module User::ShopAccess
  # this needs more work
  extend ActiveSupport::Concern

  def seller? = ShopItem::HackClubberItem.exists?(user_id: id)

  def has_regions?
    regions.present? && regions.any?
  end

  def has_region?(region_code)
    regions.include?(region_code.to_s.upcase)
  end

  def regions_display
    regions.map { |region| Shop::Regionalizable.region_name(region) }.join(", ")
  end

  def reject_pending_orders!(reason: "User banned")
    shop_orders.where(aasm_state: %w[pending awaiting_periodical_fulfillment]).find_each do |order|
      order.mark_rejected(reason)
      order.save!
    end
  end

  def addresses
    identity = hack_club_identity
    return [] unless identity&.access_token.present?

    identity_payload = HCAService.identity(identity.access_token)
    addresses = identity_payload["addresses"] || [      {
        "id": "addr!JAPune",
        "first_name": "Helena",
        "last_name": "Ackfoundation",
        "line_1": "8605 Santa Monica Blvd",
        "line_2": "PMB 86294",
        "city": "West Hollywood",
        "state": "CA",
        "postal_code": "90069",
        "country": "US",
        "phone_number": "+18028675309",
        "primary": true
      } ]
    phone_number = identity_payload["phone_number"]
    addresses.map { |address| address.merge("phone_number" => phone_number) }
  end

  def birthday
    identity = hack_club_identity
    return nil unless identity&.access_token.present?

    identity_payload = HCAService.identity(identity.access_token)
    birthday_str = identity_payload["birthday"]
    return nil if birthday_str.blank?

    Date.parse(birthday_str)
  rescue ArgumentError
    nil
  end
end

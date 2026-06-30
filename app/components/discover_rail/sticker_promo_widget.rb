# frozen_string_literal: true

module DiscoverRail
  class StickerPromoWidget < BaseWidget
    register_as :sticker_promo

    DEADLINE = Time.new(2026, 6, 30, 4, 59, 0, "+00:00").freeze
    WINDOW_START = DEADLINE - 7.days

    def render?
      user.present? && user.onboarded? && Time.current < DEADLINE
    end

    def deadline_iso
      DEADLINE.iso8601
    end

    def eligible?
      user.projects.where("shipped_at >= ?", WINDOW_START).exists?
    end
  end
end

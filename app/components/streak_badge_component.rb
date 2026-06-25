# frozen_string_literal: true

class StreakBadgeComponent < ViewComponent::Base
  attr_reader :user

  TIERS = [
    { min: 10, icon: "streak/10day.png" },
    { min: 7,  icon: "streak/7day.png" },
    { min: 5,  icon: "streak/5day.png" },
    { min: 3,  icon: "streak/3day.png" },
    { min: 1,  icon: "streak/1day.png" }
  ].freeze

  def initialize(user:, size: :default)
    @user = user
    @size = size
  end

  def render?
    user.present? && streak_days >= 2
  end

  def tooltip
    "#{streak_days}-day streak"
  end

  def streak_days
    @streak_days ||= user.current_streak
  end

  def css_classes
    classes = [ "streak-badge" ]
    classes << "streak-badge--large" if @size == :large
    classes.join(" ")
  end

  def icon_path
    TIERS.find { |t| streak_days >= t[:min] }[:icon]
  end
end

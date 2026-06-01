# frozen_string_literal: true

# == Schema Information
#
# Table name: reviewer_payout_requests
#
#  id              :bigint           not null, primary key
#  aasm_state      :string           default("pending"), not null
#  adjust_reason   :text
#  adjusted_amount :integer
#  amount          :integer
#  paid_amount     :integer
#  paid_at         :datetime
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  admin_id        :bigint
#  user_id         :bigint           not null
#
# Indexes
#
#  index_reviewer_payout_requests_on_admin_id  (admin_id)
#  index_reviewer_payout_requests_on_user_id   (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (admin_id => users.id)
#  fk_rails_...  (user_id => users.id)
#
class ReviewerPayoutRequest < ApplicationRecord
  include AASM

  has_paper_trail

  belongs_to :user
  belongs_to :admin, class_name: "User", optional: true

  validates :amount, numericality: { greater_than: 0, only_integer: true }
  validates :adjusted_amount, numericality: { greater_than: 0, only_integer: true }, allow_nil: true
  validates :adjust_reason, presence: { message: "is required when adjusting the amount" },
    if: -> { adjusted_amount.present? && adjusted_amount != amount }
  validate :sufficient_balance, on: :create
  validate :no_pending_request, on: :create

  scope :for_user, ->(user) { where(user: user) }

  aasm timestamps: true do
    state :pending, initial: true
    state :paid
    state :rejected

    event :pay do
      transitions from: :pending, to: :paid
    end

    event :reject do
      transitions from: :pending, to: :rejected
    end
  end

  def final_amount
    adjusted_amount || amount
  end

  def self.total_earned_for(user)
    return 0 unless user
    Certification::Ship
      .where(reviewer: user)
      .where.not(status: :pending)
      .sum(:stardust_earned)
  end

  def self.paid_for(user)
    return 0 unless user
    where(user: user, aasm_state: "paid").sum(:paid_amount)
  end

  def self.unclaimed_for(user)
    return 0 unless user
    total_earned = total_earned_for(user)
    total_deducted = where(user: user, aasm_state: "paid").sum("LEAST(paid_amount, amount)")
    [total_earned - total_deducted, 0].max
  end

  def self.pending_for(user)
    return nil unless user
    find_by(user: user, aasm_state: "pending")
  end

  private

  def sufficient_balance
    return unless user

    unclaimed = self.class.unclaimed_for(user)
    errors.add(:amount, "exceeds your unclaimed earnings (#{unclaimed} ✦)") if amount.to_i > unclaimed
  end

  def no_pending_request
    return unless user

    if ReviewerPayoutRequest.where(user: user, aasm_state: "pending").exists?
      errors.add(:base, "You already have a pending payout request")
    end
  end
end

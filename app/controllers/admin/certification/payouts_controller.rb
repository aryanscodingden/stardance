# frozen_string_literal: true

class Admin::Certification::PayoutsController < Admin::Certification::ApplicationController
  before_action :set_body_class
  before_action :set_payout_request, only: [ :show, :pay, :reject ]

  def index
    authorize ReviewerPayoutRequest

    @status = params[:status].presence_in(%w[pending paid rejected all]) || "all"
    scope = ReviewerPayoutRequest.includes(:user, :admin).order(created_at: :desc)
    scope = scope.where(aasm_state: @status) unless @status == "all"
    @payout_requests = scope
  end

  def show
    authorize @payout_request
  end

  def pay
    authorize @payout_request

    unless @payout_request.may_pay?
      redirect_to admin_certification_payout_path(@payout_request),
        alert: "This request cannot be paid in its current state."
      return
    end

    adjusted = params[:adjusted_amount].presence&.to_i
    adjust_reason = params[:adjust_reason].presence

    @payout_request.adjusted_amount = adjusted
    @payout_request.adjust_reason = adjust_reason

    unless @payout_request.valid?
      redirect_to admin_certification_payout_path(@payout_request),
        alert: @payout_request.errors.full_messages.to_sentence
      return
    end

    paid_amount = @payout_request.final_amount
    payout_number = ReviewerPayoutRequest.where(aasm_state: "paid").count + 1

    @payout_request.paid_amount = paid_amount
    @payout_request.admin = current_user
    @payout_request.paid_at = Time.current
    @payout_request.pay!

    # Credit the reviewer's real ledger balance
    @payout_request.user.ledger_entries.create!(
      amount: paid_amount,
      reason: "Shipwrights ##{payout_number} payout",
      created_by: "Admin (#{current_user.display_name})",
      ledgerable: @payout_request
    )

    ::PaperTrail::Version.create!(
      item_type: "ReviewerPayoutRequest",
      item_id: @payout_request.id,
      event: "paid",
      whodunnit: current_user.id,
      object_changes: { aasm_state: %w[pending paid], paid_amount: paid_amount }.to_json
    )

    redirect_to admin_certification_payouts_path,
      notice: "Paid #{paid_amount} ✦ to #{@payout_request.user.display_name} (Shipwrights ##{payout_number})."
  end

  def reject
    authorize @payout_request

    unless @payout_request.may_reject?
      redirect_to admin_certification_payout_path(@payout_request),
        alert: "This request cannot be rejected in its current state."
      return
    end

    @payout_request.reject!

    ::PaperTrail::Version.create!(
      item_type: "ReviewerPayoutRequest",
      item_id: @payout_request.id,
      event: "rejected",
      whodunnit: current_user.id,
      object_changes: { aasm_state: %w[pending rejected] }.to_json
    )

    redirect_to admin_certification_payouts_path,
      notice: "Payout request from #{@payout_request.user.display_name} rejected."
  end

  private

  def set_payout_request
    @payout_request = ReviewerPayoutRequest.find(params[:id])
  end

  def set_body_class
    @body_class = "app-layout-page"
  end
end

# frozen_string_literal: true

class Admin::Certification::MystatsController < Admin::Certification::ApplicationController
  before_action :set_body_class

  def show
    authorize :mystats, policy_class: Admin::Certification::MystatsPolicy

    @reviews = Certification::Ship
      .where(reviewer_id: current_user.id)
      .where.not(status: :pending)
      .includes(:project)
      .order(decided_at: :desc)

    @total_earned = ReviewerPayoutRequest.total_earned_for(current_user)
    @total_paid = ReviewerPayoutRequest.paid_for(current_user)
    @unclaimed = ReviewerPayoutRequest.unclaimed_for(current_user)
    @pending_request = ReviewerPayoutRequest.pending_for(current_user)
  end

  def create_payout_request
    authorize :mystats, :create_payout_request?, policy_class: Admin::Certification::MystatsPolicy

    @request = ReviewerPayoutRequest.new(
      user: current_user,
      amount: params[:amount].to_i
    )

    if @request.save
      redirect_to admin_certification_mystats_path, notice: "Payout request submitted!"
    else
      redirect_to admin_certification_mystats_path, alert: @request.errors.full_messages.to_sentence
    end
  end

  private

  def set_body_class
    @body_class = "app-layout-page"
  end
end

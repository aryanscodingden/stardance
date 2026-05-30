class SessionsController < ApplicationController
  include OnboardingResumable

  def create
    result = Sessions::HCALoginService.new(
      auth: request.env["omniauth.auth"],
      current_user: current_user,
      referral_code: cookies[:referral_code]
    ).call

    unless result.ok?
      if result.status == :age_violation
        reset_session
        return redirect_to(onboarding_age_gate_path, alert: result.alert)
      end
      return redirect_to(root_path, alert: result.alert)
    end

    reset_session if result.guest_collision
    session[:user_id] = result.user.id

    return_to = safe_return_to(session.delete(:return_to))

    destination = if result.user.onboarded_at.nil? && result.user.age_attestation_ineligible?
      onboarding_age_gate_path
    elsif result.user.onboarded_at.nil? && result.is_new_user
      onboarding_welcome_path
    elsif result.user.onboarded_at.nil?
      onboarding_resume_path(result.user)
    elsif return_to
      return_to
    elsif result.user.setup_complete?
      profile_projects_path(result.user.display_name)
    else
      home_path
    end

    redirect_to destination, notice: "Signed in with Hack Club"
  end

  def destroy
    reset_session
    redirect_to root_path, notice: "Signed out"
  end

  def failure
    redirect_to root_path, alert: "Authentication failed"
  end

  def dev_login
    return head :not_found unless Rails.env.development? || Rails.env.test?

    user = if params[:id].present?
      User.find_by(id: params[:id])
    else
      User.find_by(id: ENV["DEV_ADMIN_USER_ID"]) || User.order(:id).first
    end

    unless user
      return redirect_to(root_path, alert: "No users found for dev login. Create a user first.")
    end

    session[:user_id] = user.id
    if Rails.env.test?
      head :ok
    else
      redirect_to "/projects", notice: "Dev logged in as #{user.display_name}"
    end
  end

  private

  def safe_return_to(path)
    return nil if path.blank?

    uri = URI.parse(path)
    return nil if uri.host.present? || uri.scheme.present?
    return nil unless path.start_with?("/")
    return nil if path.start_with?("//", "/\\")
    path
  rescue URI::InvalidURIError
    nil
  end
end

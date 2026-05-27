class Onboarding::WizardController < ApplicationController
  layout "onboarding"

  before_action :require_onboarding_guest!,  only: %i[welcome birthday submit_birthday
                                                      experience submit_experience experience_result
                                                      interests submit_interests interests_result
                                                      name submit_name]
  before_action :require_teen_attestation!,  only: %i[experience submit_experience experience_result
                                                      interests submit_interests interests_result
                                                      name submit_name]

  def start
    if current_user.present?
      redirect_to home_path and return
    end

    email = params[:email].to_s.strip
    if email.blank? || !email.match?(URI::MailTo::EMAIL_REGEXP)
      redirect_to root_path, alert: "Please enter a valid email address." and return
    end

    normalized = email.downcase
    existing = User.find_by(email: normalized)

    if existing&.hca_linked?
      # OmniAuth 2.x with omniauth-rails_csrf_protection blocks GET, so we
      # render an auto-submitting POST form instead of redirecting.
      @login_hint = normalized
      return render :redirecting_to_hca
    end

    if existing
      session[:user_id] = existing.id
      redirect_to home_path and return
    end

    user = create_guest!(normalized)
    session[:user_id] = user.id
    redirect_to onboarding_welcome_path
  end

  def welcome; end

  def birthday; end

  def submit_birthday
    case params[:attestation]
    when "teen_13_18"
      current_user.update!(age_attestation: "teen_13_18")
      redirect_to onboarding_experience_path
    when "ineligible"
      current_user.destroy
      reset_session
      redirect_to onboarding_age_gate_path
    else
      redirect_to onboarding_birthday_path, alert: "Please pick one."
    end
  end

  def age_gate; end

  def experience; end

  def submit_experience
    level = params[:level].to_s
    unless User.experience_levels.key?(level)
      redirect_to onboarding_experience_path, alert: "Please pick one." and return
    end

    current_user.update!(experience_level: level)
    redirect_to onboarding_experience_result_path
  end

  def experience_result
    @level = current_user.experience_level
  end

  def interests
    @selected = current_user.interests || []
  end

  def submit_interests
    submitted = Array(params[:interests])
    if submitted.include?(User::INTERESTS_UNKNOWN)
      current_user.update!(interests: [ User::INTERESTS_UNKNOWN ])
      redirect_to onboarding_interests_result_path and return
    end

    selected = submitted & User::ALLOWED_INTERESTS
    if selected.empty?
      redirect_to onboarding_interests_path, alert: "Pick at least one." and return
    end

    current_user.update!(interests: selected)
    redirect_to onboarding_interests_result_path
  end

  def interests_result
    @interests = current_user.interests || []
  end

  def name
    @display_name_default = default_name_from_email
  end

  MAX_DISPLAY_NAME_LENGTH = 60

  def submit_name
    display_name = params[:display_name].to_s.strip
    if display_name.blank?
      redirect_to onboarding_name_path, alert: "Please enter a name." and return
    end
    if display_name.length > MAX_DISPLAY_NAME_LENGTH
      redirect_to onboarding_name_path, alert: "That's a really long name — please keep it under #{MAX_DISPLAY_NAME_LENGTH} characters." and return
    end

    current_user.update!(display_name: display_name, onboarded_at: Time.current)
    redirect_to home_path(welcome: 1)
  end

  private

  def create_guest!(email)
    User.create!(email: email, display_name: User.random_funny_display_name)
  rescue ActiveRecord::RecordNotUnique
    User.find_by(email: email) or raise
  end

  def require_onboarding_guest!
    return if current_user&.guest?
    redirect_to root_path, alert: "Please start signup from the homepage."
  end

  def require_teen_attestation!
    return if current_user&.age_attestation_teen_13_18?
    redirect_to onboarding_birthday_path
  end

  def default_name_from_email
    local = current_user.email.to_s.split("@").first.to_s
    return nil if local.blank?

    normalized = local.tr("._-", " ")
    normalized.split.map(&:capitalize).join(" ").presence
  end
end

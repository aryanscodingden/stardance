class Admin::Certification::Ysws::DashboardController < Admin::Certification::ApplicationController
  # Lazy-loaded (Turbo Frame) reviewer stats banner for the YSWS review queue.
  # Read-only, so no PaperTrail/audit entry is needed.
  def show
    authorize ::Certification::Ysws, :dashboard?

    @leaderboard = ::Certification::Ysws.reviewer_devlog_leaderboard
    @chart_data  = ::Certification::Ysws.reviewer_daily_devlog_data.to_json
  end
end

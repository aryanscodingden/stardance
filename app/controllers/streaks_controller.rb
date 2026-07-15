class StreaksController < ApplicationController
  EARLIEST_MONTH = Date.new(2026, 6, 1)
  LATEST_MONTH = Date.new(2026, 9, 1)

  before_action :require_user

  def month
    authorize :streak, :calendar?

    year = (params[:year] || Date.current.year).to_i.clamp(EARLIEST_MONTH.year, Date.current.year + 1)
    month = (params[:month] || Date.current.month).to_i.clamp(1, 12)
    @date = Date.new(year, month, 1).clamp(EARLIEST_MONTH, LATEST_MONTH)

    @calendar_days = current_user.streak_month_calendar(@date.year, @date.month)
    @show_next = (@date + 1.month) <= LATEST_MONTH && (@date + 1.month).beginning_of_month <= Date.current
    @show_prev = (@date - 1.month) >= EARLIEST_MONTH

    render partial: "streaks/month_grid",
           locals: { date: @date, calendar_days: @calendar_days, show_next: @show_next, show_prev: @show_prev },
           layout: false
  end

  def update_timezone
    authorize :streak, :calendar?

    tz = params[:timezone]
    if tz.present? && ActiveSupport::TimeZone[tz]
      current_user.update!(timezone: tz)
      head :ok
    else
      head :unprocessable_entity
    end
  end

  private

  def require_user
    redirect_to root_path unless current_user
  end
end

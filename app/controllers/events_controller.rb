class EventsController < ApplicationController
  before_action :set_body_class

  def index
    @missions = Mission.enabled
                       .includes(icon_attachment: :blob)
                       .order(featured_at: :desc, name: :asc)
  end

  private

  def set_body_class
    @body_class = "app-layout-page"
  end
end

module Admin
  class ApplicationController < ::ApplicationController
    include Pundit::Authorization

    layout "admin"

    before_action :prevent_admin_access_while_impersonating
    before_action :set_paper_trail_whodunnit

    def index
      authorize :admin, :index?
      redirect_to admin_users_path
    end

    private
    def user_for_paper_trail
      impersonating? ? real_user&.id : current_user&.id
    end

    def prevent_admin_access_while_impersonating
      if impersonating?
        flash[:alert] = "You cannot access admin panels while impersonating. Stop impersonation first."
        redirect_to root_path
      end
    end
  end
end

class LandingController < ApplicationController
  def index
    @hide_sidebar = true
    @user_ref_token = flash[:user_ref_token]

    if current_user
      redirect_to home_path
    else
      respond_to do |format|
        format.html { render :index }
      end
    end
  end

  def edu
    @hide_sidebar = true
  end
end

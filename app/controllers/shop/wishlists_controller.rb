# frozen_string_literal: true

class Shop::WishlistsController < Shop::BaseController
  def create
    authorize :shop
    current_user.shop_wishlists.find_or_create_by!(shop_item_id: params[:id])
    respond_to do |format|
      format.json { render json: { wishlisted: true } }
      format.turbo_stream
    end
  end

  def destroy
    authorize :shop
    current_user.shop_wishlists.where(shop_item_id: params[:id]).destroy_all
    respond_to do |format|
      format.json { render json: { wishlisted: false } }
      format.turbo_stream
      format.html { redirect_to shop_path }
    end
  end
end

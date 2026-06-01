class AddStardustEarnedToCertificationShipReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :certification_ship_reviews, :stardust_earned, :integer
  end
end

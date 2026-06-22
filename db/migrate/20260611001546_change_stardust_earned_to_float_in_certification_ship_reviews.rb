class ChangeStardustEarnedToFloatInCertificationShipReviews < ActiveRecord::Migration[8.1]
  def change
    safety_assured do
      change_column :certification_ship_reviews, :stardust_earned, :float
    end
  end
end

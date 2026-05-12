module Admin
  class ReviewsController < Admin::ApplicationController
    def index
      authorize :admin, :access_reviews?

      @reviews = YswsReview.all
    end
  end
end
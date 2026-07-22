class Admin::Certification::IntegrityController < Admin::Certification::ApplicationController
  def index
    authorize :integrity, policy_class: Admin::Certification::IntegrityPolicy

    reviews = ::Certification::Integrity
      .pending
      .includes(ship_event: [ :project, { post: :user } ])
      .order(created_at: :asc)
      .to_a

    @total_pending = reviews.size
    all_flags = ::Certification::Integrity::FLAGS_BY_BIT.values

    # Flags actually present across the queue, in canonical bit order — drives
    # the filter pills so we don't show a pill nobody can match.
    @available_flags = all_flags & reviews.flat_map(&:flag_names).uniq

    # Selected flags come from ?flags[]=. No param means the default "all
    # selected" view; an explicitly empty list (flags[]=) means none selected.
    @selected_flags =
      if params.key?(:flags)
        Array(params[:flags]).map(&:to_sym) & all_flags
      else
        @available_flags
      end

    # OR semantics: a review shows when it has no flags, or when any of its
    # flags is currently selected.
    @reviews = reviews.select do |review|
      names = review.flag_names
      names.empty? || names.intersect?(@selected_flags)
    end
  end

  def show
    @review = ::Certification::Integrity.find(params[:id])
    authorize @review, policy_class: Admin::Certification::IntegrityPolicy

    @shop_orders = @review.user&.shop_orders&.includes(:shop_item)&.order(created_at: :desc) || ShopOrder.none
  end
end

class SidebarComponent < ViewComponent::Base
  # ViewComponent doesn't auto-expose gem-provided view helpers, so the
  # template would otherwise have to call `helpers.inline_svg_tag`. Forward
  # it so the template stays readable. (ActionView's own helpers like
  # link_to, image_tag, form_with, etc. are already available.)
  delegate :inline_svg_tag, to: :helpers

  attr_reader :user

  def initialize(user:)
    @user = user
  end

  # Ordered list of nav items rendered in the sidebar. Each entry:
  #   slug:           data-onboarding-target value + identifier
  #   label:          visible text
  #   path:           href (or "#" for inert items)
  #   icon:           file basename in app/assets/images/icons (e.g. "home" -> home.svg),
  #                   or :avatar for the user's profile picture
  #   locked:         when truthy, render as a locked <button> with a tooltip
  #   locked_message: tooltip copy for locked items
  #   active_prefix:  optional path prefix that overrides default match (used to
  #                   highlight "my projects" on any /users/* route)
  def nav_items
    items = [
      { slug: "home",          label: "home",          path: helpers.home_path, icon: "home" },
      { slug: "notifications", label: "notifications", path: "#", icon: "bell" },
      { slug: "vote",          label: "vote",          path: helpers.new_vote_path, icon: "star_outline",
        locked: !user.has_shipped?,
        locked_message: "The Vote tab unlocks once you ship your first project!" },
      { slug: "events",        label: "events",        path: "#", icon: "code_outline" },
      { slug: "shop",          label: "shop",          path: "/shop", icon: "cart_outline" },
      { slug: "resources",     label: "resources",     path: helpers.guides_path, icon: "resources" },
      { slug: "projects",      label: "my projects",   path: helpers.user_path(user, tab: "projects"),
        icon: :avatar, active_prefix: "/users/" }
    ]

    items << { slug: "admin",   label: "admin",   path: helpers.admin_root_path, icon: "code" } if helpers.policy(:admin).access_admin_dashboard?
    items << { slug: "fulfil",  label: "fulfil",  path: helpers.admin_shop_orders_path(view: "fulfillment"), icon: "shopping_cart_1_fill" } if user.fulfillment_person? && !user.admin?
    items << { slug: "seller",  label: "seller",  path: helpers.seller_orders_path, icon: "shopping_cart_1_fill" } if user.seller?
    items << { slug: "helper",  label: "helper",  path: helpers.helper_root_path, icon: "help" } if helpers.policy(:helper).access_helper_dashboard?
    items << { slug: "certify", label: "certify", path: helpers.reviewer_ships_path, icon: "ship" } if user.project_certifier?

    items
  end

  # First-render active state (the sidebar_active Stimulus controller takes
  # over once the page is interactive and keeps the highlight in sync as the
  # user navigates Turbo-style).
  def active?(item)
    candidate_path = item[:path]
    return false if candidate_path == "#"

    if item[:active_prefix].present?
      helpers.request.path.start_with?(item[:active_prefix])
    else
      helpers.current_page?(candidate_path) ||
        helpers.request.path == candidate_path ||
        helpers.request.path.start_with?("#{candidate_path}/")
    end
  end

  def link_classes_for(item)
    [ "sidebar__nav-link", ("sidebar__nav-link--active" if active?(item)) ].compact.join(" ")
  end
end

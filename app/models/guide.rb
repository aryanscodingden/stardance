Guide = Data.define(:slug, :title, :description, :category, :icon, :reading_minutes, :related) do
  include ActiveModel::Conversion
  extend ActiveModel::Naming

  self::CATEGORY_ORDER = %i[shipping craft program].freeze

  self::CATEGORY_LABELS = {
    shipping: "Shipping",
    craft: "Craft",
    program: "Program"
  }.freeze

  def initialize(params = {})
    params[:related] ||= []
    params[:icon] ||= "info"
    params[:reading_minutes] ||= 5
    super(**params)
  end

  self::ALL = [
    new(
      slug: :what_is_shipping,
      title: "What does shipping mean?",
      description: "What it means to ship a project on Stardance, what review looks for, and what happens after you click the button.",
      category: :shipping,
      icon: "ship",
      reading_minutes: 5,
      related: %i[how_to_ship great_readme]
    ),
    new(
      slug: :how_to_ship,
      title: "How to ship: by project type",
      description: "Pick what you built, get a tailored checklist of what 'shipped' means for that kind of project — from web apps to hardware to OSS contributions.",
      category: :shipping,
      icon: "compass_fill",
      reading_minutes: 4,
      related: %i[what_is_shipping great_readme]
    ),
    new(
      slug: :great_readme,
      title: "Writing a README that doesn't suck",
      description: "Structure, must-haves, and common mistakes — the README is the first thing reviewers and voters see.",
      category: :craft,
      icon: "edit",
      reading_minutes: 5,
      related: %i[github_repository what_is_shipping how_to_ship]
    ),
    new(
      slug: :github_repository,
      title: "Create your GitHub repository",
      description: "Set up a public GitHub repository for your project's code and link it back to Stardance.",
      category: :craft,
      icon: "code",
      reading_minutes: 4,
      related: %i[good_git_commits great_readme]
    ),
    new(
      slug: :good_git_commits,
      title: "Good git commits",
      description: "Small, atomic, well-named commits make your project easier to read, review, and revisit. Here's how.",
      category: :craft,
      icon: "code",
      reading_minutes: 4,
      related: %i[github_repository great_readme]
    ),
    new(
      slug: :devlogs,
      title: "Devlogs that get noticed",
      description: "What to put in a devlog, how often to post, and why this affects voting.",
      category: :craft,
      icon: "edit",
      reading_minutes: 4,
      related: %i[what_is_shipping]
    ),
    new(
      slug: :why_we_ask,
      title: "Why we ask for your info",
      description: "What Stardance does with your birthday, region, and address — and what we don't do.",
      category: :program,
      icon: "info",
      reading_minutes: 3,
      related: []
    )
  ].freeze

  self::SLUGGED = self::ALL.index_by(&:slug).freeze

  class << self
    def all = self::ALL
    def find(s) = self::SLUGGED[s.to_sym] or raise ActiveRecord::RecordNotFound, "Unknown guide: #{s}"
    def find_by_slug(s) = self::SLUGGED[s&.to_sym]
    def by_category = self::ALL.group_by(&:category)
    def category_label(c) = self::CATEGORY_LABELS[c.to_sym]
    def category_order = self::CATEGORY_ORDER
  end

  def to_param = slug.to_s
  def persisted? = true

  def category_label = self.class::CATEGORY_LABELS[category]

  def related_guides = related.map { |s| Guide.find_by_slug(s) }.compact

  def partial_path = "guides/topics/#{slug}"
end

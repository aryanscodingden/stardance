# frozen_string_literal: true

namespace :search do
  desc "Rebuild the Redis semantic search index"
  task reindex: :environment do
    abort "SEARCH_REDIS_URL or REDIS_CACHE_URL is required" if SemanticSearch.redis_url.blank?
    abort "OPENAI_API_KEY or credentials.openai.api_key is required" if SemanticSearch.openai_api_key.blank?

    redis = SemanticSearch.redis

    begin
      redis.call("FT.DROPINDEX", SemanticSearch::INDEX_NAME, "DD")
    rescue Redis::CommandError => e
      raise unless e.message.match?(/Unknown Index name|no such index/i)
    end

    SemanticSearch.ensure_index!

    indexed = Hash.new(0)

    Project.not_deleted.find_each do |project|
      indexed["project"] += 1 if SemanticSearch.upsert(project)
    end

    Post.of_devlogs(join: true)
        .where(post_devlogs: { deleted_at: nil })
        .includes(:postable, :project, :user)
        .find_each do |post|
      indexed["devlog"] += 1 if post.postable && SemanticSearch.upsert(post.postable)
    end

    Post.of_ship_events(join: true)
        .where.not(post_ship_events: { certification_status: "rejected" })
        .includes(:postable, :project, :user)
        .find_each do |post|
      indexed["ship"] += 1 if post.postable && SemanticSearch.upsert(post.postable)
    end

    User.discoverable.where.not(display_name: [ nil, "" ]).find_each do |user|
      indexed["user"] += 1 if SemanticSearch.upsert(user)
    end

    puts "Indexed #{indexed.sort.map { |type, count| "#{count} #{type}" }.join(', ')}"
  end
end

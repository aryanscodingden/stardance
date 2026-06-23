namespace :backfill do
  desc "Enqueue jobs to cache missing vote reason embeddings"
  task vote_reason_embeddings: :environment do
    scope = Vote
      .left_outer_joins(:reason_embedding)
      .where(vote_reason_embeddings: { id: nil })
      .where.not(reason: [ nil, "" ])

    total = scope.count
    enqueued = 0

    scope.find_each do |vote|
      Vote::CacheReasonEmbeddingJob.perform_later(vote.id)
      enqueued += 1
    end

    puts "Enqueued #{enqueued} Vote::CacheReasonEmbeddingJob jobs for #{total} votes missing embeddings."
  end
end

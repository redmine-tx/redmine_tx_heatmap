namespace :redmine_tx_heatmap do
  desc 'Rebuild pending MD estimation candidates (MIN_SAMPLES=5 DRY_RUN=1 KEEP_UNAPPROVED=1)'
  task rebuild_estimation_candidates: :environment do
    min_samples = (ENV['MIN_SAMPLES'].presence || RedmineTxHeatmap::EstimationCandidateBuilder::DEFAULT_MIN_SAMPLES).to_i
    dry_run = ENV['DRY_RUN'] == '1'
    purge_unapproved = ENV['KEEP_UNAPPROVED'] != '1'

    result = RedmineTxHeatmap::EstimationCandidateBuilder.rebuild(
      min_samples: min_samples,
      dry_run: dry_run,
      purge_unapproved: purge_unapproved
    )

    puts "dry_run=#{result[:dry_run]}"
    puts "purged=#{result[:purged_count]}"
    puts "scanned=#{result[:scanned]}"
    puts "buckets=#{result[:bucket_count]}"
    puts "candidates=#{result[:candidate_count]}"
    puts "persisted=#{result[:persisted_count]}"
    puts "error=#{result[:error]}" if result[:error].present?
  end
end

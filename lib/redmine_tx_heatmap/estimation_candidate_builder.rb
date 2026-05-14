require 'json'

module RedmineTxHeatmap
  class EstimationCandidateBuilder
    DEFAULT_MIN_SAMPLES = 5
    PHRASE_MIN_SAMPLES = 4

    def initialize(settings: Settings.new)
      @settings = settings
      @team_resolver = TeamResolver.new(settings: settings)
      @hours_per_md = settings.hours_per_md
    end

    def self.rebuild(scope: nil, min_samples: DEFAULT_MIN_SAMPLES, dry_run: false, purge_unapproved: true, settings: Settings.new)
      new(settings: settings).rebuild(
        scope: scope,
        min_samples: min_samples,
        dry_run: dry_run,
        purge_unapproved: purge_unapproved
      )
    end

    def rebuild(scope: nil, min_samples: DEFAULT_MIN_SAMPLES, dry_run: false, purge_unapproved: true)
      return unavailable_result(dry_run) unless EstimationCandidate.available?

      purged_count = purge_unapproved_candidates(dry_run) if purge_unapproved
      buckets = build_buckets(historical_scope(scope), min_samples.to_i)
      candidates = candidate_payloads(buckets, min_samples.to_i)
      persisted = dry_run ? [] : persist_candidates(candidates)

      {
        :dry_run => dry_run,
        :scanned => @scanned_count.to_i,
        :bucket_count => buckets.length,
        :candidate_count => candidates.length,
        :persisted_count => persisted.length,
        :purged_count => purged_count.to_i,
        :candidates => candidates
      }
    end

    private

    def unavailable_result(dry_run)
      {
        :dry_run => dry_run,
        :scanned => 0,
        :bucket_count => 0,
        :candidate_count => 0,
        :persisted_count => 0,
        :purged_count => 0,
        :candidates => [],
        :error => 'estimation candidate table is not available'
      }
    end

    def purge_unapproved_candidates(dry_run)
      scope = EstimationCandidate.where.not(:status => 'approved')
      count = scope.count
      scope.delete_all unless dry_run
      count
    end

    def historical_scope(scope)
      base = scope || Issue.all
      base = IssueFilters.exclude_discarded(base)
      base = IssueFilters.exclude_bug_trackers(base)

      closed_ids = IssueStatus.where(:is_closed => true).pluck(:id)
      base = base.where(:status_id => closed_ids) if closed_ids.any?
      base.where.not(:tracker_id => nil)
          .where.not(:category_id => nil)
          .where('estimated_hours > 0')
          .includes(*issue_preload_associations)
    end

    def build_buckets(scope, min_samples)
      buckets = {}
      coarse_groups = {}
      @scanned_count = 0

      scope.find_each do |issue|
        owner_group = @team_resolver.actual_owner_group(issue)
        next unless owner_group

        md = issue.estimated_hours.to_f / @hours_per_md
        next unless md.positive?

        signature = IssueSignature.build(issue, owner_group_id: owner_group.id)
        direct_candidate_signatures(signature).each do |candidate_signature|
          add_bucket_sample(buckets, candidate_signature, md, issue.id, min_samples)
        end
        add_coarse_group_sample(coarse_groups, signature, md, issue.id)
        @scanned_count += 1
      end

      add_phrase_template_buckets(buckets, coarse_groups, phrase_min_samples(min_samples))
      buckets
    end

    def direct_candidate_signatures(signature)
      base = storage_signature(signature).merge(:category_id => nil)
      signatures = []
      signatures << base if base[:title_template].present?

      if base[:prefix_signature].present? && base[:stage_token].present?
        signatures << base.merge(:title_template => nil)
      end

      signatures.uniq { |item| EstimationRule.fingerprint_for(item) }
    end

    def add_coarse_group_sample(groups, signature, md, issue_id)
      group_signature = storage_signature(signature).merge(:category_id => nil, :title_template => nil, :stage_token => nil)
      key = EstimationRule.fingerprint_for(group_signature)
      group = groups[key] ||= {
        :signature => group_signature,
        :observations => []
      }
      group[:observations] << {
        :issue_id => issue_id,
        :md => md,
        :subject => signature[:title_template].presence || signature[:normalized_subject]
      }
    end

    def storage_signature(signature)
      EstimationRule.signature_attributes(signature)
    end

    def add_phrase_template_buckets(buckets, coarse_groups, minimum_samples)
      coarse_groups.each_value do |group|
        observations = group[:observations]
        next if observations.length < minimum_samples

        templates = TitleTemplateMiner.templates_for(
          observations.map { |observation| observation[:subject] },
          :min_samples => minimum_samples
        )

        templates.each do |template|
          signature = group[:signature].merge(:title_template => template[:template], :stage_token => nil)
          issue_ids = template[:indexes].map { |index| observations[index][:issue_id] }
          next if duplicate_issue_set_bucket?(buckets, signature, issue_ids)

          template[:indexes].each do |index|
            observation = observations[index]
            add_bucket_sample(buckets, signature, observation[:md], observation[:issue_id], minimum_samples)
          end
        end
      end
    end

    def duplicate_issue_set_bucket?(buckets, signature, issue_ids)
      sorted_issue_ids = issue_ids.sort

      buckets.values.any? do |bucket|
        bucket_signature = bucket[:signature]
        next false unless same_coarse_signature?(bucket_signature, signature)
        next false if bucket_signature[:title_template].blank?

        bucket[:issue_ids].sort == sorted_issue_ids
      end
    end

    def same_coarse_signature?(left, right)
      [:owner_group_id, :tracker_id, :category_name_key, :prefix_signature].all? do |field|
        left[field].to_s == right[field].to_s
      end
    end

    def add_bucket_sample(buckets, signature, md, issue_id, minimum_samples)
      fingerprint = EstimationRule.fingerprint_for(signature)
      bucket = buckets[fingerprint] ||= {
        :signature => signature,
        :minimum_samples => minimum_samples,
        :mds => [],
        :issue_ids => []
      }
      return if bucket[:issue_ids].include?(issue_id)

      bucket[:minimum_samples] = [bucket[:minimum_samples].to_i, minimum_samples.to_i].min
      bucket[:mds] << md
      bucket[:issue_ids] << issue_id
    end

    def candidate_payloads(buckets, min_samples)
      buckets.values.filter_map do |bucket|
        mds = bucket[:mds]
        next if mds.length < bucket.fetch(:minimum_samples, min_samples)

        stats = stats_for(mds)
        next unless stats[:median_md].to_f.positive?

        bucket[:signature].merge(
          :status => 'pending',
          :sample_count => mds.length,
          :median_md => stats[:median_md],
          :p25_md => stats[:p25_md],
          :p75_md => stats[:p75_md],
          :dispersion => stats[:dispersion],
          :confidence => confidence_for(mds.length, stats[:dispersion], stats[:range_dispersion]),
          :example_issue_ids => bucket[:issue_ids].sort.first(5),
          :stats_snapshot => stats,
          :fingerprint => EstimationRule.fingerprint_for(bucket[:signature])
        )
      end
    end

    def persist_candidates(candidates)
      candidates.map do |payload|
        candidate = EstimationCandidate.where(:fingerprint => payload[:fingerprint]).first_or_initialize
        candidate.assign_attributes(payload.except(:example_issue_ids, :stats_snapshot))
        candidate.status = candidate.status.presence || 'pending'
        candidate.example_issue_ids = JSON.dump(payload[:example_issue_ids])
        candidate.stats_snapshot = JSON.dump(payload[:stats_snapshot])
        candidate.save!
        candidate
      end
    end

    def stats_for(values)
      sorted = values.map(&:to_f).sort
      p25 = percentile(sorted, 0.25)
      median = percentile(sorted, 0.50)
      p75 = percentile(sorted, 0.75)
      dispersion = median.positive? ? ((p75 - p25) / median) : nil
      range_dispersion = median.positive? ? ((sorted.last - sorted.first) / median) : nil

      {
        :median_md => round_md(median),
        :p25_md => round_md(p25),
        :p75_md => round_md(p75),
        :dispersion => dispersion ? dispersion.round(4) : nil,
        :min_md => round_md(sorted.first),
        :max_md => round_md(sorted.last),
        :range_dispersion => range_dispersion ? range_dispersion.round(4) : nil
      }
    end

    def percentile(sorted, fraction)
      return nil if sorted.empty?
      return sorted.first if sorted.length == 1

      rank = fraction * (sorted.length - 1)
      lower_index = rank.floor
      upper_index = rank.ceil
      lower = sorted[lower_index]
      upper = sorted[upper_index]
      lower + ((upper - lower) * (rank - lower_index))
    end

    def confidence_for(sample_count, dispersion, range_dispersion)
      return 'low' if dispersion.nil?
      return 'high' if sample_count >= 8 && dispersion <= 0.25 && (!range_dispersion || range_dispersion <= 0.75)
      return 'medium' if sample_count >= 5 && dispersion <= 0.35
      return 'medium' if sample_count >= 4 && dispersion <= 0.10 && (!range_dispersion || range_dispersion <= 0.25)

      'low'
    end

    def phrase_min_samples(min_samples)
      [min_samples.to_i, PHRASE_MIN_SAMPLES].min
    end

    def round_md(value)
      value.to_f.round(2)
    end

    def issue_preload_associations
      associations = [:assigned_to, :category, :fixed_version, :status, :tracker]
      associations << :worker if Issue.reflect_on_association(:worker)
      associations
    end
  end
end

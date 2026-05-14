module RedmineTxHeatmap
  class IssueEstimator
    def initialize(settings: Settings.new)
      @settings = settings
    end

    def self.estimate(issue, owner_group_id:, settings: Settings.new)
      new(settings: settings).estimate(issue, owner_group_id: owner_group_id)
    end

    def estimate(issue, owner_group_id:)
      hours = issue.estimated_hours.to_f
      if hours.positive?
        return EstimateResult.new(
          :md => hours / @settings.hours_per_md,
          :source => 'estimated_hours',
          :confidence => 'exact',
          :rule_id => nil,
          :explanation => "#{hours}h / #{@settings.hours_per_md}h"
        )
      end

      rule = matching_rule(issue, owner_group_id)
      if rule
        return EstimateResult.new(
          :md => rule.md.to_f,
          :source => 'approved_rule',
          :confidence => rule.confidence.presence || 'manual',
          :rule_id => rule.id,
          :explanation => rule_explanation(rule)
        )
      end

      EstimateResult.new(
        :md => nil,
        :source => 'unknown',
        :confidence => nil,
        :rule_id => nil,
        :explanation => 'No estimated_hours or approved MD rule'
      )
    end

    private

    def matching_rule(issue, owner_group_id)
      return nil if ordered_rules.empty?

      signature = IssueSignature.build(issue, owner_group_id: owner_group_id)
      ordered_rules.find { |rule| rule.matches_signature?(signature) }
    end

    def ordered_rules
      @ordered_rules ||= EstimationRule.available? ? EstimationRule.ordered_for_matching : []
    end

    def rule_explanation(rule)
      parts = []
      parts << "rule ##{rule.id}"
      parts << "samples #{rule.sample_count}" if rule.sample_count.present?
      parts << "dispersion #{format('%.2f', rule.spread.to_f)}" if rule.spread.present?
      parts.join(', ')
    end
  end
end
